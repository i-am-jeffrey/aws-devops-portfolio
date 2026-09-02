resource "aws_ecr_repository" "app" {
  name                 = var.project_name
  image_tag_mutability = "IMMUTABLE"
  force_delete         = true # allows `terraform destroy` to remove this repo even with images inside --
                               # fine for an iterative learning project; a real prod repo would likely
                               # leave this false to prevent accidental image loss

  image_scanning_configuration {
    scan_on_push = true
  }
}
