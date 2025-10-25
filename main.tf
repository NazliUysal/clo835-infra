terraform {
  required_version = ">= 1.3.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# ----------------------------
# Variables
# ----------------------------
variable "aws_region" {
  type        = string
  default     = "us-east-1"              # Change if your Learner Lab is in a different region
  description = "AWS region to deploy into"
}

# Use an EXISTING key you already imported (e.g., 'c9key')
variable "key_name" {
  type        = string
  default     = "c9key"
  description = "Existing EC2 key pair name for SSH"
}

provider "aws" {
  region = var.aws_region
}

# ----------------------------
# ECR repositories (web + MySQL)
# ----------------------------
resource "aws_ecr_repository" "webapp" {
  name = "webapp-repo"
}

resource "aws_ecr_repository" "mysql" {
  name = "mysql-repo"
}

# ----------------------------
# Networking: default VPC + default subnets
# ----------------------------
data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default_subnets" {
  filter {
    name   = "default-for-az"
    values = ["true"]
  }
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

# Security group: SSH + single NodePort (30000)
resource "aws_security_group" "kind_sg" {
  name        = "clo835-kind-sg"
  description = "Allow SSH and NodePort access"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "K8s Web NodePort"
    from_port   = 30000
    to_port     = 30000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# ----------------------------
# AMI: latest Amazon Linux 2
# ----------------------------
data "aws_ami" "amazon_linux2" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }
}

# ----------------------------
# EC2 Instance: t3.large (kind-ready host)
# ----------------------------
resource "aws_instance" "kind_host" {
  ami                         = data.aws_ami.amazon_linux2.id
  instance_type               = "t3.large"
  subnet_id                   = data.aws_subnets.default_subnets.ids[0]
  vpc_security_group_ids      = [aws_security_group.kind_sg.id]
  associate_public_ip_address = true
  key_name                    = var.key_name

  root_block_device {
    volume_size           = 30
    volume_type           = "gp3"
    delete_on_termination = true
    encrypted             = true
  }

  # Install Docker, kind, kubectl
  user_data = <<-EOF
    #!/bin/bash
    set -euxo pipefail
    yum update -y
    yum install -y docker git
    systemctl enable docker
    systemctl start docker
    usermod -aG docker ec2-user

    # kind v0.23.0
    curl -Lo /usr/local/bin/kind https://kind.sigs.k8s.io/dl/v0.23.0/kind-linux-amd64
    chmod +x /usr/local/bin/kind

    # kubectl v1.29.0
    curl -LO "https://dl.k8s.io/release/v1.29.0/bin/linux/amd64/kubectl"
    install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
    rm -f kubectl
  EOF

  tags = {
    Name = "clo835-kind-host"
  }
}

# ----------------------------
# Outputs
# ----------------------------
output "ec2_public_ip" {
  value = aws_instance.kind_host.public_ip
}

output "ecr_webapp_repo" {
  value = aws_ecr_repository.webapp.repository_url
}

output "ecr_mysql_repo" {
  value = aws_ecr_repository.mysql.repository_url
}
