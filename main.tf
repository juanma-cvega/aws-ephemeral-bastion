locals {
  create_project_description  = <<EOF
    Creates a bastion stack from a terraform script stored in S3. Each bastion stack
is identified based on a unique random ID used as a workspace for the terraform script.
  EOF
  deployment_code_location    = "${var.resources.bucket.name}/${aws_s3_bucket_object.deployment_code.id}"
  destroy_project_description = <<EOF
    Destroys a bastion stack from a terraform script stored in S3. Each bastion stack
is identified based on a unique random ID used as a workspace for the terraform script.
  EOF
  schedule_expression         = "rate(${var.live_time_minutes} minutes)"
  security_group_ids          = format("\"%s\"", join(",", var.security_group_ids))
}

data archive_file deployment_code {
  output_path = "${path.module}/deployment_code.zip"
  source_dir  = "${path.module}/deployment"
  type        = "zip"
}

resource aws_s3_bucket this {
  bucket = var.resources.bucket.name
  lifecycle_rule {
    enabled = true
    expiration {
      days = 1
    }
    id     = "daily_retention"
    prefix = var.resources.bucket.stacks_prefix
  }
  policy = data.aws_iam_policy_document.terraform_state_policy.json
  server_side_encryption_configuration {
    rule {
      apply_server_side_encryption_by_default {
        sse_algorithm = "AES256"
      }
    }
  }
  tags = var.tags
  versioning {
    enabled = true
  }
}

resource aws_s3_bucket_policy this {
  bucket = aws_s3_bucket.this.bucket
  policy = data.aws_iam_policy_document.terraform_state_policy.json
}

resource aws_s3_bucket_object deployment_code {
  bucket = aws_s3_bucket.this.id
  key    = var.resources.bucket.code_key
  etag   = filemd5(data.archive_file.deployment_code.output_path)
  source = data.archive_file.deployment_code.output_path
}

resource aws_codebuild_project create_bastion_stack {
  name          = var.create_instance_stack_name
  description   = local.create_project_description
  service_role  = aws_iam_role.codebuild.arn
  build_timeout = "10"

  artifacts {
    type = "NO_ARTIFACTS"
  }

  environment {
    compute_type = "BUILD_GENERAL1_SMALL"
    environment_variable {
      name  = "ENVIRONMENT"
      value = ""
    }
    environment_variable {
      name  = "INSTANCE_TYPE"
      value = var.instance_type
    }
    environment_variable {
      name  = "SECURITY_GROUP_IDS"
      value = local.security_group_ids
    }
    environment_variable {
      name  = "TABLE_NAME"
      value = aws_dynamodb_table.this.name
    }
    image                       = var.build_image
    image_pull_credentials_type = "SERVICE_ROLE"
    privileged_mode             = "false"
    registry_credential {
      credential          = var.credentials.docker_hub_arn
      credential_provider = "SECRETS_MANAGER"
    }
    type = "LINUX_CONTAINER"
  }
  logs_config {
    cloudwatch_logs {
      group_name  = var.create_instance_stack_name
      stream_name = var.create_instance_stack_name
    }
  }
  source {
    buildspec = file("${path.module}/create_instance_stack_buildspec.yml")
    type      = "S3"
    location  = local.deployment_code_location
  }
  source_version = aws_s3_bucket_object.deployment_code.version_id
  tags           = var.tags
}

resource aws_codebuild_project destroy_bastion_stack {
  name          = var.destroy_instance_stacks_name
  description   = local.destroy_project_description
  service_role  = aws_iam_role.codebuild.arn
  build_timeout = "10"

  artifacts {
    type = "NO_ARTIFACTS"
  }

  environment {
    compute_type = "BUILD_GENERAL1_SMALL"
    environment_variable {
      name  = "ENVIRONMENT"
      value = ""
    }
    environment_variable {
      name  = "INSTANCE_TYPE"
      value = var.instance_type
    }
    environment_variable {
      name  = "STACK_ID"
      value = ""
    }
    environment_variable {
      name  = "SECURITY_GROUP_IDS"
      value = local.security_group_ids
    }
    environment_variable {
      name  = "TABLE_NAME"
      value = aws_dynamodb_table.this.name
    }
    image                       = var.build_image
    image_pull_credentials_type = "CODEBUILD"
    privileged_mode             = "false"
    type                        = "LINUX_CONTAINER"
  }
  logs_config {
    cloudwatch_logs {
      group_name  = var.destroy_instance_stacks_name
      stream_name = var.destroy_instance_stacks_name
    }
  }
  source {
    buildspec = file("${path.module}/destroy_instance_stack_buildspec.yml")
    type      = "S3"
    location  = local.deployment_code_location
  }
  source_version = aws_s3_bucket_object.deployment_code.version_id
  tags           = var.tags
}

resource aws_dynamodb_table this {
  attribute {
    name = "StackId"
    type = "S"
  }
  hash_key       = "StackId"
  name           = var.created_instances_table_name
  read_capacity  = "5"
  tags           = var.tags
  write_capacity = "5"
}

module create_instance {
  count = length(var.environments)

  source = "github.com/claranet/terraform-aws-lambda?ref=v1.2.0"

  description = "Invokes the CodeBuild job responsible to create a bastion stack."
  environment = {
    variables = {
      CODEBUILD_JOB = aws_codebuild_project.create_bastion_stack.name
      ENVIRONMENT   = var.environments[count.index]
    }
  }
  function_name = "${var.create_instance_stack_name}${title(var.environments[count.index])}"
  handler       = "create_instance.lambda_handler"
  memory_size   = 512
  publish       = true
  policy = {
    json = data.aws_iam_policy_document.create_instance_lambda.json
  }
  runtime     = "python3.8"
  source_path = "${path.module}/create_instance.py"
  tags        = var.tags
  timeout     = "60"
}

module destroy_idle_instances {
  source = "github.com/claranet/terraform-aws-lambda?ref=v1.2.0"

  description = "Finds expired/terminated Session Manager sessions and destroys the EC2 instances they started from."
  environment = {
    variables = {
      TABLE_NAME    = aws_dynamodb_table.this.name
      CODEBUILD_JOB = aws_codebuild_project.destroy_bastion_stack.name
    }
  }
  function_name = var.destroy_instance_stacks_name
  handler       = "destroy_idle_instances.lambda_handler"
  memory_size   = 512
  publish       = true
  policy = {
    json = data.aws_iam_policy_document.destroy_idle_instances_lambda.json
  }
  runtime     = "python3.8"
  source_path = "${path.module}/destroy_idle_instances.py"
  tags        = var.tags
  timeout     = "60"
}

resource aws_cloudwatch_event_rule trigger {
  description         = <<EOF
    Triggers a lambda responsible for cleaning any instance meant as a bastion
    without any active session."
  EOF
  name                = var.destroy_instance_stacks_name
  schedule_expression = local.schedule_expression
  tags                = merge({ Name = var.destroy_instance_stacks_name }, var.tags)
}

resource aws_lambda_permission trigger {
  action        = "lambda:InvokeFunction"
  function_name = module.destroy_idle_instances.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.trigger.arn
}

resource aws_cloudwatch_event_target trigger {
  rule = aws_cloudwatch_event_rule.trigger.name
  arn  = module.destroy_idle_instances.function_arn
}
