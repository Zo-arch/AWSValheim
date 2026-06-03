locals {
  common_tags = {
    Project = var.project_name
  }
}

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

resource "aws_iam_instance_profile" "ec2" {
  name = "${var.project_name}-ec2"
  role = aws_iam_role.ec2.name
}

resource "aws_instance" "valheim" {
  ami                         = data.aws_ami.ubuntu.id
  associate_public_ip_address = true
  iam_instance_profile        = aws_iam_instance_profile.ec2.name
  instance_type               = var.instance_type
  subnet_id                   = sort(data.aws_subnets.default.ids)[0]
  vpc_security_group_ids      = [aws_security_group.valheim.id]

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }

  root_block_device {
    encrypted   = true
    volume_size = var.root_volume_size_gb
    volume_type = "gp3"
  }

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-server"
  })
}

data "archive_file" "lambda" {
  type        = "zip"
  source_file = "${path.module}/lambda/handler.mjs"
  output_path = "${path.module}/.terraform/lambda.zip"
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
          "lambda:InvokeFunction"
        ]
        Resource = aws_lambda_function.discord.arn
      }
    ]
  })
}

resource "aws_lambda_function" "discord" {
  function_name    = "${var.project_name}-discord"
  filename         = data.archive_file.lambda.output_path
  handler          = "handler.handler"
  role             = aws_iam_role.lambda.arn
  runtime          = "nodejs20.x"
  source_code_hash = data.archive_file.lambda.output_base64sha256
  timeout          = 300

  environment {
    variables = {
      DISCORD_ALLOWED_ROLE_ID = var.discord_allowed_role_id
      DISCORD_APPLICATION_ID  = var.discord_application_id
      DISCORD_GUILD_ID        = var.discord_guild_id
      DISCORD_PUBLIC_KEY      = var.discord_public_key
      INSTANCE_ID             = aws_instance.valheim.id
      LAMBDA_FUNCTION_NAME    = "${var.project_name}-discord"
    }
  }

  tags = local.common_tags
}

resource "aws_lambda_function_url" "discord" {
  function_name      = aws_lambda_function.discord.function_name
  authorization_type = "NONE"
}

resource "aws_lambda_permission" "discord_function_url" {
  statement_id           = "AllowPublicFunctionUrlInvoke"
  action                 = "lambda:InvokeFunctionUrl"
  function_name          = aws_lambda_function.discord.function_name
  principal              = "*"
  function_url_auth_type = "NONE"
}

resource "aws_lambda_permission" "discord_function_url_invoke" {
  statement_id  = "AllowPublicFunctionUrlFunctionInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.discord.function_name
  principal     = "*"
}
