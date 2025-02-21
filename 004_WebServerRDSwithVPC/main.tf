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
  region  = "${var.aws_region}"
}

data "http" "my_ip" {
  url = "https://api.ipify.org"
}

###############################
########### Network ###########
###############################

# Create a VPC for the deployment
resource "aws_vpc" "main" {
  cidr_block = var.main_vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support = true
}

# Create Internet Gateway to allow traffic to the VPC
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
}

# Create two private subnets for the RDS instances
resource "aws_subnet" "private_subnet_a" {
  vpc_id     = aws_vpc.main.id
  cidr_block = var.private_subnet_range_a
  map_public_ip_on_launch = false
  availability_zone = "eu-north-1a"
}

resource "aws_subnet" "private_subnet_b" {
  vpc_id     = aws_vpc.main.id
  cidr_block = var.private_subnet_range_b
  map_public_ip_on_launch = false
  availability_zone = "eu-north-1b"
}

# Create a public subnet for the WebServer instance
resource "aws_subnet" "public_subnet_a" {
  vpc_id     = aws_vpc.main.id
  cidr_block = var.public_subnet_range_a
  map_public_ip_on_launch = true
  availability_zone = "eu-north-1a"
}

# Route table for the private subnets
resource "aws_route_table" "private_route_table" {
  vpc_id = aws_vpc.main.id
}

# Route table for the public subnet
resource "aws_route_table" "public_route_table" {
  vpc_id = aws_vpc.main.id

  route { # Route all traffic to the internet gateway
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }
}

# Associate the private subnets with the private route table
resource "aws_route_table_association" "private_rt_association_a" {
  subnet_id      = aws_subnet.private_subnet_a.id
  route_table_id = aws_route_table.private_route_table.id
}

resource "aws_route_table_association" "private_rt_association_b" {
  subnet_id      = aws_subnet.private_subnet_b.id
  route_table_id = aws_route_table.private_route_table.id 
}

# Associate the public subnet with the public route table
resource "aws_route_table_association" "public_rt_association_a" {
  subnet_id      = aws_subnet.public_subnet_a.id
  route_table_id = aws_route_table.public_route_table.id
}

######################################
########### Security group ###########
######################################

# Create a default security group to access the resources
resource "aws_security_group" "default" {
  vpc_id = aws_vpc.main.id
  name = "DefaultSecurityGroup"
}

# Allow inbound SSH rule for the default security group
resource "aws_security_group_rule" "allow_ssh_inbound" {
  description       = "Allow inbound SSH traffic"
  type              = "ingress"
  from_port         = 22
  to_port           = 22
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.default.id
}

resource "aws_security_group_rule" "allow_http_inbound" {
  description       = "Allow inbound HTTP traffic"
  type              = "ingress"
  from_port         = 80
  to_port           = 80
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.default.id
}

# Allow all outbound traffic
resource "aws_security_group_rule" "allow_all_out" {
  description       = "Allow outbound traffic"
  type              = "egress"
  from_port         = "0"
  to_port           = "0"
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.default.id
}

###########################
########### RDS ###########
###########################

# RDS Subnet group
resource "aws_db_subnet_group" "private_subnet_group" {
  name       = "rds-subnet-group"
  subnet_ids = [aws_subnet.private_subnet_a.id, aws_subnet.private_subnet_b.id]
}

# RDS Security group
resource "aws_security_group" "rds_sg" {
  name = "rds-sg"
  vpc_id = aws_vpc.main.id
}

# Allow MySQL inbound traffic from default security group
resource "aws_security_group_rule" "allow_mysql_inbound" {
  description               = "Allow MySQL inbound traffic from default sg"
  type                      = "ingress"
  from_port                 = 3306
  to_port                   = 3306
  protocol                  = "tcp"
  security_group_id         = aws_security_group.rds_sg.id  # Attach the rds security group
  source_security_group_id  = aws_security_group.default.id # Allow traffic from default security group
}

# Create an RDS instance
resource "aws_db_instance" "app_database" {
  allocated_storage    = 10                                                 # 10 GB of storage
  db_name              = "sample"                                           # Initial database name
  engine               = "mysql"                                            # Use MySQL
  instance_class       = "db.t3.micro"                                      # Free-tier instance type
  username             = "tutorial_user"                                    # Database username
  password             = "tutorial_password"                                # Database password --> Implement secrets management
  vpc_security_group_ids = [aws_security_group.rds_sg.id]                   # Attach the rds security group
  db_subnet_group_name = aws_db_subnet_group.private_subnet_group.name      # Attach to the private subnet group
  skip_final_snapshot = true                                                # Skip final snapshot when deleting the instance 
  multi_az = true                                                           # Enable Multi-AZ deployment for high availability

  tags = {
    Name = "MyDBInstanceFromTerraform"
  }
    
}

###########################
########### EC2 ###########
###########################

# Create an EC2 instance
resource "aws_instance" "app_server" {  # Create the WebServer instance

  ami           = "ami-031f286cefaaf26c2"                   # Use previously created AMI for WebServer
  instance_type = "t3.micro"                                # Free-tier instance type
  vpc_security_group_ids = [aws_security_group.default.id]  # Attach the default security group
  key_name = "ssh-ec2-keypair"                              # Assign keypair for SSH access
  subnet_id = aws_subnet.public_subnet_a.id                 # Attach the public subnet
  associate_public_ip_address = true                        # Assign a public IP address

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