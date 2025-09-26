terraform {
  required_version = ">= 1.3.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# Change the region if your Learner Lab uses a different one
variable "aws_region" {
  type        = string
  default     = "us-east-1"
  description = "AWS region to deploy into"
}

provider "aws" {
  region = var.aws_region
}

# ----------------------------
# ECR repositories
# ----------------------------
resource "aws_ecr_repository" "app" {
  name = "my-app"
}

resource "aws_ecr_repository" "mysql" {
  name = "my-mysql"
}

# ----------------------------
# Networking (use default VPC)
# ----------------------------
data "aws_vpc" "default" {
  default = true
}

# Get one default subnet in that VPC
data "aws_subnets" "default" {
  filter {
    name   = "default-for-az"
    values = ["true"]
  }
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

# Security group: SSH + 8081–8083 for the three app containers
resource "aws_security_group" "web_sg" {
  name   = "clo835-web-sg"
  vpc_id = data.aws_vpc.default.id

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  dynamic "ingress" {
    for_each = toset([8081, 8082, 8083])
    content {
      description = "app"
      from_port   = ingress.value
      to_port     = ingress.value
      protocol    = "tcp"
      cidr_blocks = ["0.0.0.0/0"]
    }
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# ----------------------------
# EC2 instance with Docker
# ----------------------------
resource "aws_instance" "app_server" {
  ami                         = "ami-0c02fb55956c7d316" # Amazon Linux 2 in us-east-1
  instance_type               = "t2.micro"
  subnet_id                   = data.aws_subnets.default.ids[0]
  associate_public_ip_address = true
  vpc_security_group_ids      = [aws_security_group.web_sg.id]

  user_data = <<-UD
    #!/bin/bash
    yum update -y
    amazon-linux-extras install docker -y
    systemctl enable docker
    systemctl start docker
    usermod -aG docker ec2-user
  UD

  tags = {
    Name = "clo835-app-server"
  }
}

output "ec2_public_ip" {
  value = aws_instance.app_server.public_ip
}
