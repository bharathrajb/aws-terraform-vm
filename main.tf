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

# 2. Configures the SSH Key Pair for the EC2 Instance
resource "aws_key_pair" "deployer_key" {
  key_name   = "deployer-key-${random_id.run_suffix.hex}"
  public_key = file("/home/runner/.ssh/aws_key.pub")
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

# 4. Provisions the EC2 Instance and installs Nginx via native SSH
resource "aws_instance" "web_server" {
  ami                    = "ami-0ed9277fb7eb570c9"
  instance_type          = "t3.micro"
  key_name               = aws_key_pair.deployer_key.key_name
  vpc_security_group_ids = [aws_security_group.nginx_sg.id]

  tags = {
    Name = "Terraform-Managed-Nginx-Server-${random_id.run_suffix.hex}"
  }

  # Configures the connection information for the remote-exec provisioner
  connection {
    type        = "ssh"
    user        = "ec2-user"
    private_key = file("/home/runner/.ssh/aws_key")
    host        = self.public_ip
  }

  # Executes native shell commands directly over the SSH pipe
  provisioner "remote-exec" {
    inline = [
      # 1. Force enable RHEL 9 AppStream module repositories where Nginx lives
      "sudo dnf config-manager --set-enabled rhel-9-for-x86_64-appstream-rpms || true",
      
      # 2. Clean and build package indexes
      "sudo dnf clean all",
      "sudo dnf makecache -y",
      
      # 3. Explicitly pull down the nginx module package stream
      "sudo dnf module enable -y nginx:1.22 || true",
      "sudo dnf install -y nginx",
      
      # 4. Start and confirm daemon runtime operations
      "sudo systemctl start nginx",
      "sudo systemctl enable nginx"
    ]
  }
}

output "instance_public_ip" {
  value       = aws_instance.web_server.public_ip
  description = "The public IP address of the newly provisioned web server"
}
