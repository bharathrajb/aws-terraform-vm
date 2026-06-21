terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

# Variable loaded directly from the GitHub runner environment
variable "ssh_public_key" {
  type        = string
  description = "The public key material passed from GitHub secrets"
  # Bypasses empty secret configurations by providing a fallback default
  default     = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHacypVVtfDUvkpgwrxV4uu5WkOS9RSBSHM+c68VZkRR root@terraform"
}

# 1. Generates a unique execution suffix to avoid duplication conflicts
resource "random_id" "run_suffix" {
  byte_length = 2
}

# 2. Configures the SSH Key Pair using the direct string variable
resource "aws_key_pair" "deployer_key" {
  key_name   = "deployer-key-${random_id.run_suffix.hex}"
  public_key = var.ssh_public_key
}

# 3. Creates the Security Group allowing SSH and HTTP traffic
resource "aws_security_group" "nginx_sg" {
  name        = "nginx_sg_${random_id.run_suffix.hex}"
  description = "Allow HTTP and SSH traffic"

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 80
    to_port     = 80
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

# 4. Provisions the EC2 Instance and Bootstrap-installs Nginx via User Data
resource "aws_instance" "web_server" {
  ami                    = "ami-0ed9277fb7eb570c9"
  instance_type          = "t3.micro"
  key_name               = aws_key_pair.deployer_key.key_name
  vpc_security_group_ids = [aws_security_group.nginx_sg.id]

  tags = {
    Name = "Terraform-Managed-Nginx-Server-${random_id.run_suffix.hex}"
  }

  user_data = <<-EOF
              #!/bin/bash
              echo '[nginx-stable]' > /etc/yum.repos.d/nginx.repo
              echo 'name=nginx stable repo' >> /etc/yum.repos.d/nginx.repo
              echo 'baseurl=http://nginx.org/packages/rhel/9/x86_64/' >> /etc/yum.repos.d/nginx.repo
              echo 'gpgcheck=0' >> /etc/yum.repos.d/nginx.repo
              echo 'enabled=1' >> /etc/yum.repos.d/nginx.repo
              echo 'module_hotfixes=true' >> /etc/yum.repos.d/nginx.repo

              dnf clean all
              dnf makecache -y
              dnf install -y nginx

              systemctl start nginx
              systemctl enable nginx
              EOF

  user_data_replace_on_change = true
}

output "instance_public_ip" {
  value       = aws_instance.web_server.public_ip
  description = "The public IP address of the newly provisioned web server"
}
