variable ami_creation {
  description = "Configuration required to create a pipeline to create a base AMI for the bastion."
  type = object({
    name              = string
    pipeline_schedule = string
    subnet_id         = string
    vpc_id            = string
  })
}

variable build_image {
  description = "Image to be used by CodeBuild to create and destroy instance stacks."
  type        = string
}

variable code_build_role_name {
  description = "Name to give to the role created for the CodeBuild jobs."
  type        = string
}

variable create_instance_stack_name {
  description = "CodeBuild project name responsible to create a bastion stack."
  type        = string
}

variable created_instances_table_name {
  description = "Name of the table that holds information about created instances."
  type        = string
}

variable credentials {
  description = "Credentials to access external services."
  type = object({
    docker_hub_arn = string
  })
}

variable destroy_instance_stacks_name {
  description = "CodeBuild project name responsible to destroy a bastion stack."
  type        = string
}

variable environments {
  description = "Environments the stack can be deployed for. For each environment there will be a Lambda deployed."
  type        = list(string)
}

variable instance_type {
  description = "EC2 instance type to deploy"
  type        = string
}

variable live_time_minutes {
  description = "Time in seconds the bastion stack should remain before it is destroyed."
  type        = number
}

variable resources {
  description = "Information to access and store common resources."
  type = object({
    bucket = object({
      code_key      = string
      name          = string
      stacks_prefix = string
    })
    security = object({
      principal_arns = list(string)
    })
  })
}

variable security_group_ids {
  description = "Security groups to attach to the instance deployed."
  type        = list(string)
}

variable tags {
  description = "Tags to add to created AWS resources."
  type        = map(string)
}
