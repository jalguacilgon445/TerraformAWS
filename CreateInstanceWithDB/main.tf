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

# Create a VPC for the deployment
resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"
}

# Create a subnet to interconnect the resources
resource "aws_subnet" "main" {
  vpc_id     = aws_vpc.main.id
  cidr_block = "10.0.1.0/24"
  availability_zone = "eu-north-1a"
}

# Second subnet that is not used for first deployment 
# > Improve to use RDS in private subnet, EC2 in public subnet with Internet Gateway
resource "aws_subnet" "secondary" {
  vpc_id     = aws_vpc.main.id
  cidr_block = "10.0.2.0/24"
  availability_zone = "eu-north-1b"
}

# Create a security group to allow traffic to the resources and between them
resource "aws_security_group" "ec2_sg" {
  vpc_id = aws_vpc.main.id

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
  vpc_id = aws_vpc.main.id

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
  subnet_id     = aws_subnet.main.id                        # Attach to the main subnet
  vpc_security_group_ids = [aws_security_group.ec2_sg.id]   # Attach the ec2 security group
  key_name = "ssh-ec2-keypair"                              # Assign keypait for SSH access

  tags = {
    Name = "MyWebServerFromTerraform"
  }

}

# Create a DB subnet group for the main subnet --> Improve to use multiple subnets in different AZs
resource "aws_db_subnet_group" "main" {
  name       = "main"
  subnet_ids = [aws_subnet.main.id, aws_subnet.secondary.id]

  tags = {
    Name = "Main DB subnet group"
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
  db_subnet_group_name = aws_db_subnet_group.main.name      # Attach to the main subnet group
  skip_final_snapshot = true                                # Skip final snapshot when deleting the instance 

  tags = {
    Name = "MyDBInstanceFromTerraform"
  }
    
}

