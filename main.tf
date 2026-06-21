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

variable "ssh_public_key" {
  type        = string
  description = "The public key material passed directly from the workflow run"
}

# 1. Map definition for our multi-instance setup
variable "web_servers" {
  type = map(object({
    instance_type = string
    server_role   = string
  }))
  default = {
    "web-server-01" = { instance_type = "t3.micro", server_role = "frontend-primary" }
    "web-server-02" = { instance_type = "t3.micro", server_role = "frontend-secondary" }
  }
}

resource "random_id" "run_suffix" {
  byte_length = 2
}

resource "aws_key_pair" "deployer_key" {
  key_name   = "deployer-key-${random_id.run_suffix.hex}"
  public_key = var.ssh_public_key
}

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

# 2. Dynamic EC2 provisioning using for_each loop
resource "aws_instance" "web_server" {
  for_each               = var.web_servers
  
  ami                    = "ami-0ed9277fb7eb570c9"
  instance_type          = each.value.instance_type
  key_name               = aws_key_pair.deployer_key.key_name
  vpc_security_group_ids = [aws_security_group.nginx_sg.id]

  tags = {
    Name = "Terraform-${each.key}-${random_id.run_suffix.hex}"
    Role = each.value.server_role
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

              # Customize individual index pages slightly to see which server is which
              echo "<h1>Hello from ${each.key} (${each.value.server_role})</h1>" > /usr/share/nginx/html/index.html

              systemctl start nginx
              systemctl enable nginx
              EOF

  user_data_replace_on_change = true
}

# 3. Output map rendering both public IPs cleanly
output "instance_public_ips" {
  value       = { for k, v in aws_instance.web_server : k => v.public_ip }
  description = "The public IP addresses of the newly provisioned web servers"
}
