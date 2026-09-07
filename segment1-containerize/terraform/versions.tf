# segment1-containerize/terraform/versions.tf
#
# Two changes from the original file, marked below with CHANGED:
#   1. required_version bumped 1.5 -> 1.10 (needed for S3 native locking)
#   2. a new backend "s3" block
# Everything else (providers, the helm data source, the helm provider
# block) is unchanged.

terraform {
  required_version = ">= 1.11" # CHANGED — was >= 1.5. Needed for the S3 backend's
                                # native use_lockfile locking. Sources disagree on
                                # whether 1.10 (introduction) or 1.11 is the real
                                # minimum -- pinned to 1.11 as the safer floor after
                                # cross-checking multiple sources. See
                                # terraform/bootstrap/README.md.

  # CHANGED — new block. Backend blocks cannot reference variables, locals,
  # or outputs — Terraform must resolve the backend before it evaluates any
  # of those — so the bucket name below is a manual, literal copy from
  # `terraform output tfstate_bucket_name` in terraform/bootstrap/, done
  # once. See terraform/bootstrap/README.md for the full migration steps;
  # this project already has a populated local terraform.tfstate, so wiring
  # this in is a migration (`terraform init -migrate-state`), not a fresh
  # init.
  backend "s3" {
    bucket       = "segment1-app-tfstate-411714852651"
    key          = "segment1-app/terraform.tfstate"
    region       = "ap-southeast-1"
    encrypt      = true
    use_lockfile = true # native S3 locking -- deliberately no dynamodb_table
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.13"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.4" # already resolved to 4.4.0 transitively via the eks module -- pinning explicitly now that
                          # ci-cd-iam.tf's data "tls_certificate" uses it directly in the root module, not just the module internally
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# The helm provider needs its own connection details for the cluster --
# this was missing, which is why helm_release.aws_load_balancer_controller
# failed with "Kubernetes cluster unreachable".
data "aws_eks_cluster_auth" "this" {
  name = module.eks.cluster_name
}

provider "helm" {
  kubernetes {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
    token                  = data.aws_eks_cluster_auth.this.token
  }
}
