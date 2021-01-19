variable environment {
  description = "The environment needs to have connection to."
  type        = string
}

variable instance_type {
  description = "EC2 instance type to deploy"
  type        = string
}

variable security_group_ids {
  description = "Security groups to attach to the instance deployed."
  type        = list(string)
}

variable source_version {
  description = "Version used to deploy the code."
  type        = string
}

variable stack_id {
  description = "Unique identifier for the stack"
  type        = string
}

variable table_name {
  description = "DynamoDB table where information related to new instance stacks is stored."
  type        = string
}

variable tags {
  description = "Tags to add to created AWS resources."
  type        = map(string)
}

variable template_name {
  description = "Template file name without the extension used to create the user data string."
  type        = string
}

variable template_vars {
  description = "User data to use when the instance is started."
  type        = map(string)
}

variable role_name_prefix {
  description = "Prefix to add to the stack ID as the name for the instance profile created."
  default     = "TemporaryBastionSSMAccess"
}
