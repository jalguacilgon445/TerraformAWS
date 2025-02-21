###########################
########### EC2 ###########
###########################

output "ec2_public_dns" {
  value = aws_instance.app_server.public_dns
  description = "WebServer public DNS"
}

output "ec2_public_ipv4" {
  value = aws_instance.app_server.public_ip
  description = "WebServer public IP"
}

output "ec2_private_ipv4" {
  value = aws_instance.app_server.private_ip
  description = "WebServer private IP"
}

###########################
########### RDS ###########
###########################

output "rds_address" {
  value = aws_db_instance.app_database.address
  description = "RDS address"
}

output "rds_private_endpoint" {
  value = aws_db_instance.app_database.endpoint
  description = "RDS endpoint"
}