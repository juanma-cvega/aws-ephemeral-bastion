locals {
  ami_distribution_name = "${var.ami_creation.name}-{{ imagebuilder:buildDate }}"
  role_name             = "EC2InstanceProfileForImageBuilder"
  security_group_name   = "${var.ami_creation.name}-ami-creation"
  reboot_component_arn  = "arn:aws:imagebuilder:eu-west-1:aws:component/reboot-linux/1.0.1/1"
  ssm_agent_url         = "https://s3.eu-west-1.amazonaws.com/amazon-ssm-eu-west-1/latest/linux_amd64/amazon-ssm-agent.rpm"
}

data "aws_region" "current" {}

data "aws_partition" "current" {}

resource "aws_imagebuilder_component" "this" {
  data = yamlencode({
    phases = [{
      name = "build"
      steps = [{
        action = "ExecuteBash"
        inputs = {
          commands = [
            "sudo -i",
            "yum update",
            "yum -y install ${local.ssm_agent_url}",
            "yum -y update --security"
          ]
        }
        name      = "UpdateSoftware"
        onFailure = "Continue"
      }]
    }]
    schemaVersion = 1.0
  })
  description = "Installs the latest security patches and the most recent version of the AWS SSM agent."
  name        = "UpdateSecurityPatchesAndSSMAgent"
  platform    = "Linux"
  tags        = var.tags
  version     = "1.0.0"
}

resource "aws_imagebuilder_distribution_configuration" "this" {
  distribution {
    ami_distribution_configuration {
      ami_tags = var.tags
      name     = local.ami_distribution_name
    }
    region = data.aws_region.current.name
  }
  name = var.ami_creation.name
  tags = var.tags
}

resource "aws_security_group" "this" {
  description = "Used to create the AMI ${var.ami_creation.name}"
  name        = local.security_group_name
  tags        = var.tags
  vpc_id      = var.ami_creation.vpc_id
}

resource "aws_security_group_rule" "this" {
  cidr_blocks       = ["0.0.0.0/0"]
  description       = "Gives access to updates"
  from_port         = 0
  protocol          = "TCP"
  security_group_id = aws_security_group.this.id
  to_port           = 65535
  type              = "egress"
}

resource "aws_imagebuilder_infrastructure_configuration" "this" {
  description                   = "Creates the image in the given VPC, Subnet and Security Group using t3.micro or t3.small instances."
  instance_profile_name         = local.role_name
  instance_types                = ["t3.micro", "t3.small"]
  name                          = var.ami_creation.name
  security_group_ids            = [aws_security_group.this.id]
  subnet_id                     = var.ami_creation.subnet_id
  terminate_instance_on_failure = true
  tags                          = var.tags
}

resource "aws_imagebuilder_image_recipe" "this" {
  block_device_mapping {
    device_name = "/dev/xvda"
    ebs {
      delete_on_termination = true
      volume_size           = 8
      volume_type           = "gp2"
    }
  }
  component {
    component_arn = aws_imagebuilder_component.this.arn
  }
  component {
    component_arn = local.reboot_component_arn
  }
  name         = var.ami_creation.name
  parent_image = "arn:${data.aws_partition.current.partition}:imagebuilder:${data.aws_region.current.name}:aws:image/amazon-linux-2-x86/x.x.x"
  version      = "1.0.0"
}

resource "aws_imagebuilder_image_pipeline" "this" {
  distribution_configuration_arn   = aws_imagebuilder_distribution_configuration.this.arn
  image_recipe_arn                 = aws_imagebuilder_image_recipe.this.arn
  infrastructure_configuration_arn = aws_imagebuilder_infrastructure_configuration.this.arn
  name                             = var.ami_creation.name
  schedule {
    schedule_expression = var.ami_creation.pipeline_schedule
  }
  tags = var.tags
}
