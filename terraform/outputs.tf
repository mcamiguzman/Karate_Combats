output "api_public_ip" {
  description = "Public IP address of the API server"
  value       = aws_eip.api_eip.public_ip
}

output "api_private_ip" {
  description = "Private IP address of the API server"
  value       = aws_network_interface.api_eni.private_ip
}

output "api_url" {
  description = "URL to access the API server"
  value       = "http://${aws_eip.api_eip.public_ip}:5000"
}

output "rabbitmq_public_ip" {
  description = "Public IP address of the RabbitMQ server"
  value       = aws_eip.rabbitmq_eip.public_ip
}

output "rabbitmq_private_ip" {
  description = "Private IP address of the RabbitMQ server"
  value       = aws_network_interface.rabbitmq_eni.private_ip
}

output "rabbitmq_management_url" {
  description = "URL to access RabbitMQ Management Dashboard"
  value       = "http://${aws_eip.rabbitmq_eip.public_ip}:15672"
}

output "postgresql_public_ip" {
  description = "Public IP address of the PostgreSQL server"
  value       = aws_eip.postgresql_eip.public_ip
}

output "postgresql_private_ip" {
  description = "Private IP address of the PostgreSQL server"
  value       = aws_network_interface.postgresql_eni.private_ip
}

output "postgresql_connection_string" {
  description = "Connection string for PostgreSQL database"
  value       = "postgresql://${var.db_user}:${var.db_password}@${aws_eip.postgresql_eip.public_ip}:5432/${var.db_name}"
  sensitive   = true
}

output "worker_public_ip" {
  description = "Public IP address of the Worker server"
  value       = aws_eip.worker_eip.public_ip
}

output "worker_private_ip" {
  description = "Private IP address of the Worker server"
  value       = aws_network_interface.worker_eni.private_ip
}

output "vpc_id" {
  description = "ID of the VPC"
  value       = aws_vpc.karate_vpc.id
}

output "subnet_id" {
  description = "ID of the public subnet"
  value       = aws_subnet.public_subnet.id
}

output "ssh_to_api" {
  description = "SSH command to connect to API server"
  value       = "ssh -i your_key.pem ubuntu@${aws_eip.api_eip.public_ip}"
}

output "ssh_to_rabbitmq" {
  description = "SSH command to connect to RabbitMQ server"
  value       = "ssh -i your_key.pem ubuntu@${aws_eip.rabbitmq_eip.public_ip}"
}

output "ssh_to_postgresql" {
  description = "SSH command to connect to PostgreSQL server"
  value       = "ssh -i your_key.pem ubuntu@${aws_eip.postgresql_eip.public_ip}"
}

output "ssh_to_worker" {
  description = "SSH command to connect to Worker server"
  value       = "ssh -i your_key.pem ubuntu@${aws_eip.worker_eip.public_ip}"
}
