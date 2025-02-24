terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.16"
    }
    http = {
      source  = "hashicorp/http"
      version = "~> 2.0"
    }
  }

  required_version = ">= 1.2.0"
}

provider "aws" {
  region  = "eu-north-1"
}

data "http" "my_ip" {
  url = "https://api.ipify.org"
}

# Create a security group to allow traffic to the resources and between them
resource "aws_security_group" "ec2_sg" {

  ingress { # Allow SSH inbound traffic from developer's IP
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["${data.http.my_ip.response_body}/32"]
  }

  ingress { # Allow all HTTP inbound traffic (for WebServer access)
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {  # Allow all outbound traffic
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_instance" "app_server" {
  ami           = "ami-031f286cefaaf26c2"
  instance_type = "t3.micro"
  vpc_security_group_ids = [aws_security_group.ec2_sg.id]
  key_name = "ssh-ec2-keypair"

  tags = {
    Name = "MyWebServerFromTerraform"
  }
}
