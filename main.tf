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

# 1. Generates a unique execution suffix to avoid duplication conflicts
resource "random_id" "run_suffix" {
  byte_length = 2
}

<<<<<<< Updated upstream
# 2. Configures the SSH Key Pair for the EC2 Instance
=======
# 2. Configures the SSH Key Pair using the local workspace file path
>>>>>>> Stashed changes
resource "aws_key_pair" "deployer_key" {
  key_name   = "deployer-key-${random_id.run_suffix.hex}"
  public_key = file("${path.module}/aws_key.pub")
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

  # Cloud-init User Data script that executes natively at the root system level on bootup
  user_data = <<-EOF
              #!/bin/bash
              # Setup the upstream stable repo configuration safely
              echo '[nginx-stable]' > /etc/yum.repos.d/nginx.repo
              echo 'name=nginx stable repo' >> /etc/yum.repos.d/nginx.repo
              echo 'baseurl=http://nginx.org/packages/rhel/9/x86_64/' >> /etc/yum.repos.d/nginx.repo
              echo 'gpgcheck=0' >> /etc/yum.repos.d/nginx.repo
              echo 'enabled=1' >> /etc/yum.repos.d/nginx.repo
              echo 'module_hotfixes=true' >> /etc/yum.repos.d/nginx.repo

              # Clean cache and install packages natively
              dnf clean all
              dnf makecache -y
              dnf install -y nginx

              # Start the service engines and enable boot hooks
              systemctl start nginx
              systemctl enable nginx
              EOF

  # Ensure user data run finishes execution processing hooks gracefully
  user_data_replace_on_change = true
}

output "instance_public_ip" {
  value       = aws_instance.web_server.public_ip
  description = "The public IP address of the newly provisioned web server"
}
