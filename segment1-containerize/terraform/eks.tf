module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"

  cluster_name    = "${var.project_name}-cluster"
  cluster_version = var.cluster_version

  vpc_id                          = module.vpc.vpc_id
  subnet_ids                      = module.vpc.private_subnets
  cluster_endpoint_public_access  = true

  enable_cluster_creator_admin_permissions = true

  eks_managed_node_groups = {
    default = {
      instance_types = ["t3.medium"]
      capacity_type  = "SPOT" # cheaper, can be interrupted -- fine for a portfolio project, not for real prod
      min_size       = 1
      max_size       = 3
      desired_size   = 2
    }
  }
}

# Optional: grant an IAM user (as opposed to the SSO role above) access to
# view/manage this cluster -- e.g. for browsing the EKS console under an
# admin IAM user separate from the SSO session used to run Terraform.
# Skipped entirely if console_iam_user_arn is left unset.
resource "aws_eks_access_entry" "console_iam_user" {
  count         = var.console_iam_user_arn != null ? 1 : 0
  cluster_name  = module.eks.cluster_name
  principal_arn = var.console_iam_user_arn
}

resource "aws_eks_access_policy_association" "console_iam_user_admin" {
  count         = var.console_iam_user_arn != null ? 1 : 0
  cluster_name  = module.eks.cluster_name
  principal_arn = var.console_iam_user_arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"

  access_scope {
    type = "cluster"
  }
}
