terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.16"
    }
  }

  required_version = ">= 1.2.0"
}

provider "aws" {
  region  = "eu-north-1"
}

resource "aws_instance" "app_server" {
  ami           = "ami-031f286cefaaf26c2"
  instance_type = "t3.micro"

  tags = {
    Name = "MyWebServerFromTerraform"
  }
}
