resource "aws_instance" "web_server" {
  ami                    = "ami-0ed9277fb7eb570c9"
  instance_type          = "t3.micro"
  key_name               = aws_key_pair.deployer_key.key_name
  vpc_security_group_ids = [aws_security_group.nginx_sg.id]

  tags = {
    Name = "Terraform-Managed-Nginx-Server-${random_id.run_suffix.hex}"
  }

  # Connect to the instance directly over native SSH
  connection {
    type        = "ssh"
    user        = "ec2-user"
    private_key = file("/home/runner/.ssh/aws_key")
    host        = self.public_ip
  }

  # Execute raw shell scripts natively—bypassing Ansible completely
  provisioner "remote-exec" {
    inline = [
      "sudo dnf install -y nginx",
      "sudo systemctl start nginx",
      "sudo systemctl enable nginx"
    ]
  }
}
