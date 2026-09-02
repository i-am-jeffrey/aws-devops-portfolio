variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "ap-southeast-1"
}

variable "project_name" {
  description = "Name prefix for all resources"
  type        = string
  default     = "segment1-app"
}

variable "cluster_version" {
  description = "Kubernetes version for EKS -- 1.30 fell out of support around mid-2026; verify the current supported version list in the EKS console before applying, since this changes over time"
  type        = string
  default     = "1.33"
}

variable "console_iam_user_arn" {
  description = "Optional: ARN of an IAM user (not the SSO role) to grant EKS cluster-admin access, e.g. for browsing the EKS console with an admin IAM user separate from the SSO session. Leave null to skip -- the SSO role that runs terraform apply already gets access automatically."
  type        = string
  default     = null
}
