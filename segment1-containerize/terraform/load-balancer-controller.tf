# Installs the AWS Load Balancer Controller so a Service (type=LoadBalancer)
# or Ingress provisions a real NLB/ALB, using IRSA for pod-level AWS auth
# (no static credentials in the cluster).
#
# NOTE: the IAM policy this controller needs is maintained by AWS and
# changes over time -- rather than embed a possibly-stale copy here, fetch
# the current version before applying:
#   curl -o iam_policy_lb_controller.json \
#     https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/main/docs/install/iam_policy.json
# and place it alongside this file.

data "aws_iam_policy_document" "lb_controller_assume" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    effect  = "Allow"

    condition {
      test     = "StringEquals"
      variable = "${replace(module.eks.oidc_provider, "https://", "")}:sub"
      values   = ["system:serviceaccount:kube-system:aws-load-balancer-controller"]
    }

    principals {
      identifiers = [module.eks.oidc_provider_arn]
      type        = "Federated"
    }
  }
}

resource "aws_iam_role" "lb_controller" {
  name               = "${var.project_name}-lb-controller"
  assume_role_policy = data.aws_iam_policy_document.lb_controller_assume.json
}

resource "aws_iam_policy" "lb_controller" {
  name   = "${var.project_name}-lb-controller-policy"
  policy = file("${path.module}/iam_policy_lb_controller.json") # fetched manually, see note above
}

resource "aws_iam_role_policy_attachment" "lb_controller" {
  role       = aws_iam_role.lb_controller.name
  policy_arn = aws_iam_policy.lb_controller.arn
}

resource "helm_release" "aws_load_balancer_controller" {
  name       = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  namespace  = "kube-system"

  # Without this, Terraform has no reason to wait for the node group --
  # this chart needs a schedulable node to run its controller pod on, or
  # the install times out waiting for a pod that can never start.
  depends_on = [module.eks]

  set {
    name  = "clusterName"
    value = module.eks.cluster_name
  }
  set {
    name  = "serviceAccount.create"
    value = "true"
  }
  set {
    name  = "serviceAccount.name"
    value = "aws-load-balancer-controller"
  }
  set {
    name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = aws_iam_role.lb_controller.arn
  }
}
