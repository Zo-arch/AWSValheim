output "instance_id" {
  description = "EC2 instance ID controlled by the web panel."
  value       = aws_instance.valheim.id
}

output "control_site_url" {
  description = "S3 website URL for the Valheim control panel."
  value       = "http://${aws_s3_bucket_website_configuration.control_site.website_endpoint}"
}

output "control_api_url" {
  description = "Public Lambda Function URL used by the control panel."
  value       = aws_lambda_function_url.control_api.function_url
}

output "ssm_instance_target" {
  description = "Instance target to use with AWS Systems Manager Session Manager."
  value       = aws_instance.valheim.id
}

output "current_public_ip" {
  description = "Best-effort public IPv4 at the time Terraform last refreshed state. This changes after stop/start."
  value       = aws_instance.valheim.public_ip
}

output "backup_bucket_name" {
  description = "S3 bucket used for automatic Valheim world backups."
  value       = aws_s3_bucket.backups.bucket
}
