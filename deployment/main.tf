locals {
  ami_name_filter            = "${var.ami_name}*"
  instance_role_name         = "${var.role_name_prefix}-${var.stack_id}"
  session_manager_policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  subnet_name                = "Access${title(var.environment)}"
  user_data = (var.template_name != ""
    ? templatefile("${path.module}/resources/${var.template_name}", var.template_vars)
  : null)
}

data aws_ami this {
  most_recent = true
  owners      = ["self"]

  filter {
    name   = "name"
    values = [local.ami_name_filter]
  }
}

data aws_iam_policy_document assume_role {
  statement {
    actions = ["sts:AssumeRole"]
    effect  = "Allow"
    principals {
      identifiers = ["ec2.amazonaws.com"]
      type        = "Service"
    }
  }
}

data aws_subnet this {
  filter {
    name   = "tag:Name"
    values = [local.subnet_name]
  }
}

resource aws_iam_instance_profile this {
  name = aws_iam_role.this.name
  role = aws_iam_role.this.name
}

resource aws_iam_role this {
  assume_role_policy = data.aws_iam_policy_document.assume_role.json
  description        = "Gives bastion access to the required AWS resources."
  name               = local.instance_role_name
  tags               = var.tags
}

resource aws_iam_role_policy_attachment session_manager_access {
  policy_arn = local.session_manager_policy_arn
  role       = aws_iam_role.this.name
}

resource aws_instance this {
  ami           = data.aws_ami.this.id
  instance_type = var.instance_type
  subnet_id     = data.aws_subnet.this.id
  tags = merge({
    Name    = var.stack_id
    StackId = var.stack_id
  }, var.tags)
  iam_instance_profile   = aws_iam_instance_profile.this.name
  user_data              = local.user_data
  vpc_security_group_ids = var.security_group_ids
}

resource aws_dynamodb_table_item this {
  hash_key   = "StackId"
  item       = <<ITEM
{
  "Environment": {"S": "${var.environment}"},
  "InstanceId": {"S": "${aws_instance.this.id}"},
  "StackId": {"S": "${var.stack_id}"},
  "SourceVersion": {"S": "${var.source_version}"}
}
ITEM
  table_name = var.table_name
}
