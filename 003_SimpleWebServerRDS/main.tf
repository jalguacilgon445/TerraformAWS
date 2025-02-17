# Use the AWS provider
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.16"
    }
  }

  required_version = ">= 1.2.0"
}

# Set the AWS region to eu-north-1
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

resource "aws_security_group" "rds_sg" {

  ingress { # Allow MySQL inbound traffic from EC2 instance
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    security_groups = [aws_security_group.ec2_sg.id]
  }

    egress {  # Allow all outbound traffic
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Create an EC2 instance
resource "aws_instance" "app_server" {  # Create the WebServer instance

  ami           = "ami-031f286cefaaf26c2"                   # Use previously created AMI for WebServer
  instance_type = "t3.micro"                                # Free-tier instance type
  vpc_security_group_ids = [aws_security_group.ec2_sg.id]   # Attach the ec2 security group
  key_name = "ssh-ec2-keypair"                              # Assign keypair for SSH access

  # Run a script on instance startup to configure the RDS endpoint
  user_data = <<-EOF
              #!/bin/bash
              echo "
              <?php

              define('DB_SERVER', '${aws_db_instance.app_database.address}');
              define('DB_USERNAME', 'tutorial_user');
              define('DB_PASSWORD', 'tutorial_password');
              define('DB_DATABASE', 'sample');
              ?>
              " > /var/www/inc/dbinfo.inc
              EOF

  tags = {
    Name = "MyWebServerFromTerraform"
  }

}

# Create an RDS instance
resource "aws_db_instance" "app_database" {
  allocated_storage    = 10                                 # 10 GB of storage
  db_name              = "sample"                           # Initial database name
  engine               = "mysql"                            # Use MySQL
  instance_class       = "db.t3.micro"                      # Free-tier instance type
  username             = "tutorial_user"                    # Database username
  password             = "tutorial_password"                # Database password --> Implement secrets management
  vpc_security_group_ids = [aws_security_group.rds_sg.id]   # Attach the rds security group
  skip_final_snapshot = true                                # Skip final snapshot when deleting the instance 

  tags = {
    Name = "MyDBInstanceFromTerraform"
  }
    
}