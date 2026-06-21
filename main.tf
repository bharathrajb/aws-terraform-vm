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

# 1. Primary Provider Configuration (Default: us-east-1)
provider "aws" {
  region = "us-east-1"
}

# 2. Secondary Provider Configuration (Aliased: us-west-2)
provider "aws" {
  alias  = "us_west_2"
  region = "us-west-2"
}

variable "ssh_public_key" {
  type        = string
  description = "The public key material passed directly from the workflow run"
}

# The total number of instances you want to exist per region
variable "target_count" {
  type        = number
  default     = 1
}

resource "random_id" "run_suffix" {
  byte_length = 2
}

# Key Pair for Primary Region
resource "aws_key_pair" "deployer_key_east" {
  key_name   = "deployer-key-east-${random_id.run_suffix.hex}"
  public_key = var.ssh_public_key
}

# Key Pair for Secondary Region (Requires explicit provider mapping)
resource "aws_key_pair" "deployer_key_west" {
  provider   = aws.us_west_2
  key_name   = "deployer-key-west-${random_id.run_suffix.hex}"
  public_key = var.ssh_public_key
}

# Security Group for Primary Region
resource "aws_security_group" "nginx_sg_east" {
  name        = "nginx_sg_east_${random_id.run_suffix.hex}"
  description = "Allow HTTP and SSH traffic in us-east-1"

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

# Security Group for Secondary Region
resource "aws_security_group" "nginx_sg_west" {
  provider    = aws.us_west_2
  name        = "nginx_sg_west_${random_id.run_suffix.hex}"
  description = "Allow HTTP and SSH traffic in us-west-2"

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

# ==========================================
# COMPUTE RESOURCES - US-EAST-1 (PRIMARY)
# ==========================================
resource "aws_instance" "web_server_east" {
  count                  = var.target_count
  
  # RHEL 9 AMI in us-east-1
  ami                    = "ami-0ed9277fb7eb570c9"
  instance_type          = "t3.micro"
  key_name               = aws_key_pair.deployer_key_east.key_name
  vpc_security_group_ids = [aws_security_group.nginx_sg_east.id]

  tags = {
    Name = "East-Server-${count.index + 1}-${random_id.run_suffix.hex}"
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

              echo "<h1>Hello from East Region Server ${count.index + 1}</h1>" > /usr/share/nginx/html/index.html

              systemctl start nginx
              systemctl enable nginx
              EOF

  user_data_replace_on_change = true
}

# ==========================================
# COMPUTE RESOURCES - US-WEST-2 (SECONDARY)
# ==========================================
resource "aws_instance" "web_server_west" {
  # Tells Terraform to explicitly use the us-west-2 aliased provider
  provider               = aws.us_west_2
  count                  = var.target_count
  
  # RHEL 9 AMI in us-west-2 (Note: AMIs are region-specific, this is verified for west-2)
  ami                    = "ami-03c7c1f17fe054016"
  instance_type          = "t3.micro"
  key_name               = aws_key_pair.deployer_key_west.key_name
  vpc_security_group_ids = [aws_security_group.nginx_sg_west.id]

  tags = {
    Name = "West-Server-${count.index + 1}-${random_id.run_suffix.hex}"
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

              echo "<h1>Hello from West Region Server ${count.index + 1}</h1>" > /usr/share/nginx/html/index.html

              systemctl start nginx
              systemctl enable nginx
              EOF

  user_data_replace_on_change = true
}

# Outputs for tracking both environments
output "us_east_1_public_ips" {
  value       = aws_instance.web_server_east[*].public_ip
  description = "Public IPs of running servers in us-east-1"
}

output "us_west_2_public_ips" {
  value       = aws_instance.web_server_west[*].public_ip
  description = "Public IPs of running servers in us-west-2"
}
