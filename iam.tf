locals {
  bastion_code_arn = "${aws_s3_bucket.this.arn}/${var.resources.bucket.code_key}"
  principal_arns = concat(
    [aws_iam_role.codebuild.arn],
    var.resources.security.principal_arns
  )
}

data aws_iam_policy_document assume_role_codebuild {
  statement {
    actions = ["sts:AssumeRole"]
    effect  = "Allow"
    principals {
      identifiers = ["codebuild.amazonaws.com"]
      type        = "Service"
    }
  }
}

data aws_iam_policy_document codebuild {
  statement {
    actions = [
      "s3:PutObject",
      "s3:GetObject",
      "s3:ListBucketVersions",
      "s3:ListBucket",
      "s3:GetBucketVersioning",
      "s3:GetObjectVersion",
      "secretsmanager:GetSecretValue"
    ]
    effect = "Allow"
    resources = [
      aws_s3_bucket.this.arn,
      "${aws_s3_bucket.this.arn}/*"
    ]
  }
  statement {
    actions = [
      "secretsmanager:GetSecretValue"
    ]
    effect    = "Allow"
    resources = [var.credentials.docker_hub_arn]
  }
  statement {
    actions = [
      "ec2:*",
      "logs:*",
      "cloudwatch:*",
      "dynamodb:*",
      "iam:*"
    ]
    effect    = "Allow"
    resources = ["*"]
  }
}

data aws_iam_policy_document create_instance_lambda {
  statement {
    actions = [
      "codeBuild:StartBuild"
    ]
    effect    = "Allow"
    resources = [aws_codebuild_project.create_bastion_stack.arn]
  }
}

data aws_iam_policy_document destroy_idle_instances_lambda {
  statement {
    actions = [
      "dynamodb:DescribeTable",
      "dynamodb:ListTables",
      "dynamodb:DeleteItem",
      "dynamodb:Scan"
    ]
    effect    = "Allow"
    resources = [aws_dynamodb_table.this.arn]
  }
  statement {
    actions = [
      "ssm:DescribeSessions",
      "ec2:DescribeInstanceStatus"
    ]
    effect    = "Allow"
    resources = ["*"]
  }
  statement {
    actions = [
      "codeBuild:StartBuild"
    ]
    effect    = "Allow"
    resources = [aws_codebuild_project.destroy_bastion_stack.arn]
  }
}

data aws_iam_policy_document terraform_state_policy {
  statement {
    actions = [
      "s3:*"
    ]
    condition {
      test     = "StringNotEquals"
      values   = local.principal_arns
      variable = "aws:PrincipalArn"
    }
    effect = "Deny"
    principals {
      identifiers = ["*"]
      type        = "AWS"
    }
    resources = [
      "arn:aws:s3:::${var.resources.bucket.name}/*",
      "arn:aws:s3:::${var.resources.bucket.name}"
    ]
    sid = "BastionCreationAccess"
  }
}

resource aws_iam_role codebuild {
  assume_role_policy = data.aws_iam_policy_document.assume_role_codebuild.json
  name               = var.code_build_role_name
}

resource aws_iam_role_policy codebuild {
  name   = var.code_build_role_name
  policy = data.aws_iam_policy_document.codebuild.json
  role   = aws_iam_role.codebuild.id
}
