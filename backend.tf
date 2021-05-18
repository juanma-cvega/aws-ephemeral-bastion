terraform {
  backend s3 {
    bucket         = "terraform-backend"
    dynamodb_table = "terraform-locks-table"
    encrypt        = true
    key            = "terraform.tfstate"
    region         = "eu-west-1"
  }
}
