output "instance_id" {
  description = "EC2 instance ID controlled by Discord."
  value       = aws_instance.valheim.id
}

output "lambda_function_url" {
  description = "Public URL to configure as the Discord interactions endpoint."
  value       = aws_lambda_function_url.discord.function_url
}

output "ssm_instance_target" {
  description = "Instance target to use with AWS Systems Manager Session Manager."
  value       = aws_instance.valheim.id
}

output "current_public_ip" {
  description = "Best-effort public IPv4 at the time Terraform last refreshed state. This changes after stop/start."
  value       = aws_instance.valheim.public_ip
}
