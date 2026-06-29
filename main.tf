# ==============================================================================
# 1. TERRAFORM ROOT & BACKEND CONFIGURATION
# ==============================================================================
terraform {
  required_version = ">= 1.10.0"
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
    bucket       = "raj-cloud-terraform-state-2026"
    key          = "build-ec2/terraform.tfstate"
    region       = "us-east-1"
    use_lockfile = true # Uses native S3 object locking instead of DynamoDB
  }
}

# ==============================================================================
# 2. GLOBAL VARIABLE DECLARATIONS
# ==============================================================================
variable "ssh_public_key" {
  type        = string
  description = "Public SSH key passed dynamically from the Jenkins host profile"
}

variable "instance_type" {
  type        = string
  default     = "t3.micro"
  description = "The target hardware configuration sizing for deployment web nodes"
}

# Unique suffix generator to prevent name collisions on resource creation
resource "random_id" "run_suffix" {
  byte_length = 2
}

# ==============================================================================
# 3. US-EAST-1 REGIONAL INFRASTRUCTURE (PRIMARY ARCHITECTURE)
# ==============================================================================
provider "aws" {
  region = "us-east-1"
}

resource "aws_key_pair" "deployer_key_east" {
  key_name   = "deployer-key-east-${random_id.run_suffix.hex}"
  public_key = var.ssh_public_key
}

resource "aws_security_group" "nginx_sg_east" {
  name        = "nginx-access-east-${random_id.run_suffix.hex}"
  description = "Allow inbound web traffic"

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

resource "aws_instance" "web_east" {
  count                  = 1
  ami                    = "ami-04a81a99f5ec58529" # Ubuntu 24.04 LTS in us-east-1
  instance_type          = var.instance_type
  key_name               = aws_key_pair.deployer_key_east.key_name
  vpc_security_group_ids = [aws_security_group.nginx_sg_east.id]

  user_data = <<-EOF
              #!/bin/bash
              apt-get update -y
              apt-get install nginx -y
              systemctl start nginx
              systemctl enable nginx
              echo "<h1>Hello from US-EAST-1 Production Cluster</h1>" > /var/www/html/index.html
              EOF

  tags = {
    Name = "Web-Node-East-${random_id.run_suffix.hex}"
  }
}

# ==============================================================================
# 4. US-WEST-2 REGIONAL INFRASTRUCTURE (REDUNDANT ARCHITECTURE)
# ==============================================================================
provider "aws" {
  alias  = "west"
  region = "us-west-2"
}

resource "aws_key_pair" "deployer_key_west" {
  provider   = aws.west
  key_name   = "deployer-key-west-${random_id.run_suffix.hex}"
  public_key = var.ssh_public_key
}

resource "aws_security_group" "nginx_sg_west" {
  provider    = aws.west
  name        = "nginx-access-west-${random_id.run_suffix.hex}"
  description = "Allow inbound web traffic"

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

resource "aws_instance" "web_west" {
  count                  = 1
  provider               = aws.west
  ami                    = "ami-038230b986e39564c" # Ubuntu 24.04 LTS in us-west-2
  instance_type          = var.instance_type
  key_name               = aws_key_pair.deployer_key_west.key_name
  vpc_security_group_ids = [aws_security_group.nginx_sg_west.id]

  user_data = <<-EOF
              #!/bin/bash
              apt-get update -y
              apt-get install nginx -y
              systemctl start nginx
              systemctl enable nginx
              echo "<h1>Hello from US-WEST-2 Production Cluster</h1>" > /var/www/html/index.html
              EOF

  tags = {
    Name = "Web-Node-West-${random_id.run_suffix.hex}"
  }
}

# ==============================================================================
# 5. ARCHITECTURE VALUE OUTPUTS
# ==============================================================================
output "us_east_1_public_ips" {
  value       = aws_instance.web_east[*].public_ip
  description = "The public infrastructure entrypoints for the primary East cluster"
}

output "us_west_2_public_ips" {
  value       = aws_instance.web_west[*].public_ip
  description = "The public infrastructure entrypoints for the standby West cluster"
}
