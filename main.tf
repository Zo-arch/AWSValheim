locals {
  common_tags = {
    Project = var.project_name
  }

  backup_bucket_name = "${var.project_name}-${data.aws_caller_identity.current.account_id}-${var.aws_region}-backups"
  site_bucket_name   = "${var.project_name}-${data.aws_caller_identity.current.account_id}-${var.aws_region}-site"
}

data "aws_caller_identity" "current" {}

data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }

  filter {
    name   = "default-for-az"
    values = ["true"]
  }
}

data "aws_subnet" "selected" {
  id = sort(data.aws_subnets.default.ids)[0]
}

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

resource "aws_security_group" "valheim" {
  name        = "${var.project_name}-valheim"
  description = "Valheim UDP access; no SSH ingress"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description = "Valheim game UDP ports"
    from_port   = 2456
    to_port     = 2457
    protocol    = "udp"
    cidr_blocks = var.valheim_udp_cidr_blocks
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-valheim"
  })
}

resource "aws_iam_role" "ec2" {
  name = "${var.project_name}-ec2"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "ec2_ssm" {
  role       = aws_iam_role.ec2.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy" "ec2_backup" {
  name = "${var.project_name}-ec2-backup"
  role = aws_iam_role.ec2.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:AbortMultipartUpload"
        ]
        Resource = "${aws_s3_bucket.backups.arn}/*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:ListBucket"
        ]
        Resource = aws_s3_bucket.backups.arn
      }
    ]
  })
}

resource "aws_iam_instance_profile" "ec2" {
  name = "${var.project_name}-ec2"
  role = aws_iam_role.ec2.name
}

resource "aws_instance" "valheim" {
  ami                         = data.aws_ami.ubuntu.id
  associate_public_ip_address = true
  iam_instance_profile        = aws_iam_instance_profile.ec2.name
  instance_type               = var.instance_type
  subnet_id                   = data.aws_subnet.selected.id
  vpc_security_group_ids      = [aws_security_group.valheim.id]

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }

  root_block_device {
    delete_on_termination = true
    encrypted             = true
    volume_size           = var.root_volume_size_gb
    volume_type           = "gp3"
  }

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-server"
  })
}

resource "aws_s3_bucket" "backups" {
  bucket        = local.backup_bucket_name
  force_destroy = true

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-backups"
  })
}

resource "aws_s3_bucket_public_access_block" "backups" {
  bucket = aws_s3_bucket.backups.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "backups" {
  bucket = aws_s3_bucket.backups.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "backups" {
  bucket = aws_s3_bucket.backups.id

  rule {
    id     = "expire-world-backups"
    status = "Enabled"

    filter {
      prefix = "backups/worlds/"
    }

    expiration {
      days = var.backup_retention_days
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 1
    }
  }
}

data "archive_file" "control_api" {
  type        = "zip"
  source_file = "${path.module}/lambda/control-api.mjs"
  output_path = "${path.module}/.terraform/control-api.zip"
}

resource "aws_iam_role" "lambda" {
  name = "${var.project_name}-lambda"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "lambda_valheim" {
  name = "${var.project_name}-valheim-control"
  role = aws_iam_role.lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ec2:StartInstances",
          "ec2:StopInstances"
        ]
        Resource = aws_instance.valheim.arn
      },
      {
        Effect = "Allow"
        Action = [
          "ec2:DescribeInstances"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "ssm:SendCommand",
          "ssm:GetCommandInvocation"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_lambda_function" "control_api" {
  function_name    = "${var.project_name}-control-api"
  filename         = data.archive_file.control_api.output_path
  handler          = "control-api.handler"
  role             = aws_iam_role.lambda.arn
  memory_size      = 128
  runtime          = "nodejs20.x"
  source_code_hash = data.archive_file.control_api.output_base64sha256
  timeout          = 900

  environment {
    variables = {
      BACKUP_BUCKET_NAME    = aws_s3_bucket.backups.bucket
      BACKUP_PREFIX         = "backups/worlds"
      CONTROL_PASSWORD_HASH = var.control_password_hash
      INSTANCE_HOURLY_USD   = tostring(var.session_hourly_usd)
      INSTANCE_ID           = aws_instance.valheim.id
      INSTANCE_TYPE         = var.instance_type
      USD_TO_BRL_RATE       = tostring(var.usd_to_brl_rate)
      VALHEIM_PORT          = tostring(var.valheim_port)
    }
  }

  tags = local.common_tags
}

resource "aws_lambda_function_url" "control_api" {
  function_name      = aws_lambda_function.control_api.function_name
  authorization_type = "NONE"

  cors {
    allow_credentials = false
    allow_headers     = ["content-type", "x-control-password", "authorization"]
    allow_methods     = ["GET", "POST"]
    allow_origins     = ["*"]
    max_age           = 86400
  }
}

resource "aws_lambda_permission" "control_api_function_url" {
  statement_id           = "AllowPublicFunctionUrlInvoke"
  action                 = "lambda:InvokeFunctionUrl"
  function_name          = aws_lambda_function.control_api.function_name
  principal              = "*"
  function_url_auth_type = "NONE"
}

resource "aws_lambda_permission" "control_api_function_invoke" {
  statement_id  = "AllowPublicFunctionInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.control_api.function_name
  principal     = "*"
}

resource "aws_s3_bucket" "control_site" {
  bucket        = local.site_bucket_name
  force_destroy = true

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-control-site"
  })
}

resource "aws_s3_bucket_public_access_block" "control_site" {
  bucket = aws_s3_bucket.control_site.id

  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

resource "aws_s3_bucket_server_side_encryption_configuration" "control_site" {
  bucket = aws_s3_bucket.control_site.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_website_configuration" "control_site" {
  bucket = aws_s3_bucket.control_site.id

  index_document {
    suffix = "index.html"
  }

  error_document {
    key = "index.html"
  }
}

resource "aws_s3_bucket_policy" "control_site" {
  bucket = aws_s3_bucket.control_site.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = "*"
        Action    = "s3:GetObject"
        Resource  = "${aws_s3_bucket.control_site.arn}/*"
      }
    ]
  })

  depends_on = [aws_s3_bucket_public_access_block.control_site]
}

resource "aws_s3_object" "site_index" {
  bucket       = aws_s3_bucket.control_site.id
  key          = "index.html"
  source       = "${path.module}/site/index.html"
  content_type = "text/html; charset=utf-8"
  etag         = filemd5("${path.module}/site/index.html")
}

resource "aws_s3_object" "site_styles" {
  bucket       = aws_s3_bucket.control_site.id
  key          = "styles.css"
  source       = "${path.module}/site/styles.css"
  content_type = "text/css; charset=utf-8"
  etag         = filemd5("${path.module}/site/styles.css")
}

resource "aws_s3_object" "site_app" {
  bucket       = aws_s3_bucket.control_site.id
  key          = "app.js"
  source       = "${path.module}/site/app.js"
  content_type = "application/javascript; charset=utf-8"
  etag         = filemd5("${path.module}/site/app.js")
}

resource "aws_s3_object" "site_config" {
  bucket       = aws_s3_bucket.control_site.id
  key          = "config.js"
  content      = "window.VALHEIM_CONTROL_CONFIG = ${jsonencode({ apiUrl = aws_lambda_function_url.control_api.function_url })};"
  content_type = "application/javascript; charset=utf-8"
  etag         = md5("window.VALHEIM_CONTROL_CONFIG = ${jsonencode({ apiUrl = aws_lambda_function_url.control_api.function_url })};")
}
