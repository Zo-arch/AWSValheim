variable "aws_region" {
  description = "AWS region where the Valheim server will be created."
  type        = string
  default     = "sa-east-1"
}

variable "project_name" {
  description = "Name prefix used for AWS resources."
  type        = string
  default     = "valheim-control"
}

variable "instance_type" {
  description = "EC2 instance type for the Valheim server."
  type        = string
  default     = "t3.large"
}

variable "root_volume_size_gb" {
  description = "Root EBS volume size in GiB."
  type        = number
  default     = 40
}

variable "valheim_udp_cidr_blocks" {
  description = "CIDR blocks allowed to reach the Valheim UDP ports."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "control_password_hash" {
  description = "Lowercase SHA-256 hex hash of the password used by the web control panel."
  type        = string
  sensitive   = true
}

variable "valheim_port" {
  description = "Valheim UDP port displayed in the control panel."
  type        = number
  default     = 2456
}

variable "session_hourly_usd" {
  description = "Manual hourly USD estimate used by the control panel for the current EC2 instance type."
  type        = number
  default     = 0.0
}

variable "usd_to_brl_rate" {
  description = "Manual USD to BRL exchange rate used by the control panel estimate."
  type        = number
  default     = 5.5
}

variable "backup_retention_days" {
  description = "Number of days to retain Valheim world backups in S3."
  type        = number
  default     = 30
}
