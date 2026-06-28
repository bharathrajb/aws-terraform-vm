# ==========================================
# 1. TERRAFORM CORE CONFIGURATION & BACKEND
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
    bucket         = "raj-cloud-terraform-state-2026"
    key            = "dev/automated-ec2-deployment/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "terraform-lock-table"
    encrypt        = true
  }
}

# ==========================================
# 2. PROVIDER DEFINITIONS (MULTI-REGION)
# ==========================================
provider "aws" {
  region = "us-east-1"
}

provider "aws" {
  alias  = "us_west_2"
  region = "us-west-2"
}

# ==========================================
# 3. GLOBAL INPUT VARIABLES
# ==========================================
variable "target_count" {
  type        = number
  description = "Number of instances deployed per region"
  default     = 1
}

variable "ssh_public_key" {
  type        = string
  description = "The plain text public key material injected securely via Jenkins credentials"
}

# Unique suffix to avoid resource naming collisions across deployments
resource "random_id" "run_suffix" {
  byte_length = 2
}

# ==========================================
# 4. REGIONAL RESOURCES: US-EAST-1 (VIRGINIA)
# ==========================================
data "aws_ami" "rhel9_east" {
  most_recent = true
  owners      = ["309956199498"] # Official Red Hat Owner ID
  filter {
    name   = "name"
    values = ["RHEL-9.*_HVM-*-x86_64-*"]
  }
}

resource "aws_security_group" "nginx_sg_east" {
  name        = "nginx-sg-${random_id.run_suffix.hex}-east"
  description = "Allow HTTP and SSH access in us-east-1"

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

resource "aws_key_pair" "deployer_key_east" {
  key_name   = "deployer-key-east-${random_id.run_suffix.hex}"
  public_key = var.ssh_public_key
}

resource "aws_instance" "web_east" {
  count                  = var.target_count
  ami                    = data.aws_ami.rhel9_east.id
  instance_type          = "t2.micro"
  key_name               = aws_key_pair.deployer_key_east.key_name
  vpc_security_group_ids = [aws_security_group.nginx_sg_east.id]

  user_data = <<-EOF
              #!/bin/bash
              dnf update -y
              dnf install -y nginx
              systemctl enable nginx
              systemctl start nginx
              echo "<h1>Welcome to your Cloud VM in US-EAST-1</h1>" > /usr/share/nginx/html/index.html
              EOF

  tags = {
    Name        = "nginx-web-east-${count.index + 1}"
    Environment = "Dev"
  }
}

# ==========================================
# 5. REGIONAL RESOURCES: US-WEST-2 (OREGON)
# ==========================================
data "aws_ami" "rhel9_west" {
  provider    = aws.us_west_2
  most_recent = true
  owners      = ["309956199498"]
  filter {
    name   = "name"
    values = ["RHEL-9.*_HVM-*-x86_64-*"]
  }
}

resource "aws_security_group" "nginx_sg_west" {
  provider    = aws.us_west_2
  name        = "nginx-sg-${random_id.run_suffix.hex}-west"
  description = "Allow HTTP and SSH access in us-west-2"

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

resource "aws_key_pair" "deployer_key_west" {
  provider   = aws.us_west_2
  key_name   = "deployer-key-west-${random_id.run_suffix.hex}"
  public_key = var.ssh_public_key
}

resource "aws_instance" "web_west" {
  provider               = aws.us_west_2
  count                  = var.target_count
  ami                    = data.aws_ami.rhel9_west.id
  instance_type          = "t2.micro"
  key_name               = aws_key_pair.deployer_key_west.key_name
  vpc_security_group_ids = [aws_security_group.nginx_sg_west.id]

  user_data = <<-EOF
              #!/bin/bash
              dnf update -y
              dnf install -y nginx
              systemctl enable nginx
              systemctl start nginx
              echo "<h1>Welcome to your Cloud VM in US-WEST-2</h1>" > /usr/share/nginx/html/index.html
              EOF

  tags = {
    Name        = "nginx-web-west-${count.index + 1}"
    Environment = "Dev"
  }
}

# ==========================================
# 6. OUTPUTS
# ==========================================
output "us_east_1_public_ips" {
  value       = aws_instance.web_east[*].public_ip
  description = "Public IP addresses for Virginia instances"
}

output "us_west_2_public_ips" {
  value       = aws_instance.web_west[*].public_ip
  description = "Public IP addresses for Oregon instances"
}
