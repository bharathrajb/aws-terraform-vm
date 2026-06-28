# ==========================================
# 1. TERRAFORM INITIALIZATION & S3 BACKEND
# ==========================================
terraform {
  required_version = ">= 1.0.0"
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

  backend "s3" {
    bucket  = "raj-cloud-terraform-state-2026"
    key     = "build-ec2/terraform.tfstate"
    region  = "us-east-1"
    encrypt = true
  }
}

# ==========================================
# 2. PROVIDERS (MULTI-REGION CONFIG)
# ==========================================
provider "aws" {
  region = "us-east-1" # Primary Region
}

provider "aws" {
  alias  = "us_west_2"
  region = "us-west-2" # Secondary Region
}

# ==========================================
# 3. VARIABLES
# ==========================================
variable "target_count" {
  type        = number
  description = "Number of instances per region"
  default     = 1
}


# ==========================================
# 4. RANDOM UNIQUE SUFFIX GENERATOR
# ==========================================
resource "random_id" "run_suffix" {
  byte_length = 2
}

# ==========================================
# 5. DATA SOURCES (DYNAMIC RHEL 9 AMI LOOKUP)
# ==========================================
data "aws_ami" "rhel9_east" {
  most_recent = true
  owners      = ["309956199498"] # Red Hat Owner ID

  filter {
    name   = "name"
    values = ["RHEL-9.*-x86_64-*"]
  }
  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
}

data "aws_ami" "rhel9_west" {
  provider    = aws.us_west_2
  most_recent = true
  owners      = ["309956199498"]

  filter {
    name   = "name"
    values = ["RHEL-9.*-x86_64-*"]
  }
  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
}

# ==========================================
# 6. SECURITY GROUPS (HTTP & SSH ALLOWED)
# ==========================================
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
# 7. SSH KEY PAIRS
# ==========================================
resource "aws_key_pair" "deployer_key_east" {
  key_name   = "deployer-key-east-${random_id.run_suffix.hex}"
  public_key = var.ssh_public_key
}

resource "aws_key_pair" "deployer_key_west" {
  provider   = aws.us_west_2
  key_name   = "deployer-key-west-${random_id.run_suffix.hex}"
  public_key = var.ssh_public_key
}

# ==========================================
# 8. EC2 COMPUTE INSTANCES WITH USER DATA
# ==========================================
resource "aws_instance" "web_server_east" {
  count                  = var.target_count
  ami                    = data.aws_ami.rhel9_east.id
  instance_type          = "t3.micro"
  key_name               = aws_key_pair.deployer_key_east.key_name
  vpc_security_group_ids = [aws_security_group.nginx_sg_east.id]

  user_data = <<-EOF
              #!/bin/bash
              sudo dnf install -y nginx
              sudo systemctl enable --now nginx
              EOF

  tags = {
    Name = "WebServer-East-${random_id.run_suffix.hex}-${count.index}"
  }
}

resource "aws_instance" "web_server_west" {
  provider               = aws.us_west_2
  count                  = var.target_count
  ami                    = data.aws_ami.rhel9_west.id
  instance_type          = "t3.micro"
  key_name               = aws_key_pair.deployer_key_west.key_name
  vpc_security_group_ids = [aws_security_group.nginx_sg_west.id]

# Add this line to stop the replacement!
  user_data_replace_on_change = false

  user_data = <<-EOF
              #!/bin/bash
              sudo dnf install -y nginx
              sudo systemctl enable --now nginx
              EOF

  tags = {
    Name = "WebServer-West-${random_id.run_suffix.hex}-${count.index}"
  }
}

# ==========================================
# 9. OUTPUTS
# ==========================================
output "us_east_1_public_ips" {
  value       = aws_instance.web_server_east[*].public_ip
  description = "Public IP addresses of instances in East region"
}

output "us_west_2_public_ips" {
  value       = aws_instance.web_server_west[*].public_ip
  description = "Public IP addresses of instances in West region"
}
