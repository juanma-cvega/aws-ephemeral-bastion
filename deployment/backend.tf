terraform {
  backend s3 {
    bucket               = "terraform-bastion-backend"
    dynamodb_table       = "terraform-locks-table"
    encrypt              = true
    key                  = "terraform.tfstate"
    region               = "eu-west-1"
    workspace_key_prefix = "stacks"
  }
}
