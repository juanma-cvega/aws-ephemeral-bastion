output instance_id {
  value = aws_instance.this.id
}

output environment {
  value = var.environment
}
