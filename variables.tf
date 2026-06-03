variable "aws_region" {
  description = "AWS region where the Valheim server will be created."
  type        = string
  default     = "sa-east-1"
}

variable "project_name" {
  description = "Name prefix used for AWS resources."
  type        = string
  default     = "valheim-discord"
}

variable "instance_type" {
  description = "EC2 instance type for the Valheim server."
  type        = string
  default     = "t3.large"
}

variable "root_volume_size_gb" {
  description = "Root EBS volume size in GiB."
  type        = number
  default     = 30
}

variable "valheim_udp_cidr_blocks" {
  description = "CIDR blocks allowed to reach the Valheim UDP ports."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "discord_application_id" {
  description = "Discord application ID."
  type        = string
}

variable "discord_public_key" {
  description = "Discord application's Ed25519 public key."
  type        = string
  sensitive   = true
}

variable "discord_guild_id" {
  description = "Discord guild ID allowed to use the endpoint."
  type        = string
}

variable "discord_allowed_role_id" {
  description = "Discord role ID allowed to run /valheim commands."
  type        = string
}

variable "discord_command_name" {
  description = "Top-level Discord slash command name."
  type        = string
  default     = "valheim"
}
