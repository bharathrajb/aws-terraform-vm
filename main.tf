terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

# Fix applied: Points directly to the absolute runner path
resource "aws_key_pair" "deployer_key" {
  key_name   = "deployer-key"
  public_key = file("/home/runner/.ssh/aws_key.pub")
}

resource "aws_security_group" "nginx_sg" {
  name        = "nginx_sg"
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

resource "aws_instance" "web_server" {
  ami                    = "ami-0ed9277fb7eb570c9"
  instance_type          = "t2.micro"
  key_name               = aws_key_pair.deployer_key.key_name
  vpc_security_group_ids = [aws_security_group.nginx_sg.id]

  tags = {
    Name = "Ansible-Managed-Nginx-Server"
  }

  provisioner "local-exec" {
    command = "echo '[webservers]\n${self.public_ip} ansible_user=ec2-user ansible_ssh_private_key_file=/home/runner/.ssh/aws_key ansible_ssh_common_args=\"-o StrictHostKeyChecking=no\"' > inventory.ini"
  }
}

output "instance_public_ip" {
  value       = aws_instance.web_server.public_ip
  description = "The public IP address of the newly provisioned web server"
}
