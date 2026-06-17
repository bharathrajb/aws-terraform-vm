provider "aws" {
  region = "us-east-1"
}

# 1. Import your local public key to AWS
resource "aws_key_pair" "deployer_key" {
  key_name   = "centos-vm-key"
  public_key = file("~/.ssh/aws_key.pub")
}

# 2. Configure Firewall / Security Group
resource "aws_security_group" "allow_ssh" {
  name        = "allow_ssh_centos"
  description = "Allow inbound SSH traffic"

  ingress {
    description = "SSH from anywhere"
    from_port   = 22
    to_port     = 22
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

# 3. Provision the Free-Tier Instance (Switching to t3.micro)
resource "aws_instance" "free_vm" {
  ami                    = "ami-0c7217cdde317cfec" # Ubuntu 22.04 LTS in us-east-1
  instance_type          = "t3.micro"             # Free Tier Eligible
  key_name               = aws_key_pair.deployer_key.key_name
  vpc_security_group_ids = [aws_security_group.allow_ssh.id]

  tags = {
    Name = "CentOS-Triggered-VM"
  }
}

# 4. Show the target connection string when finished
output "ssh_connection_command" {
  value = "ssh -i ~/.ssh/aws_key ubuntu@${aws_instance.free_vm.public_ip}"
}
