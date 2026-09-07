module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"
  cluster_name    = "${var.project_name}-cluster"
  cluster_version = var.cluster_version
  vpc_id                          = module.vpc.vpc_id
  subnet_ids                      = module.vpc.private_subnets
  cluster_endpoint_public_access  = true
  enable_cluster_creator_admin_permissions = true

  cluster_enabled_log_types = ["api", "audit", "authenticator", "controllerManager", "scheduler"]
  cloudwatch_log_group_retention_in_days = 365

  eks_managed_node_groups = {
    default = {
      instance_types = ["t3.medium"]
      capacity_type  = "SPOT"
      min_size       = 1
      max_size       = 3
      desired_size   = 2
    }
  }
}

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
