# AWS Configuration
aws_region           = "us-east-1"
project_name         = "karate-combats"
availability_zone    = "us-east-1a"
instance_type        = "t3.micro"

# VPC Configuration
vpc_cidr             = "10.0.0.0/16"
public_subnet_cidr   = "10.0.1.0/24"

# Private IP Addresses
api_private_ip         = "10.0.1.10"
rabbitmq_private_ip    = "10.0.1.20"
postgresql_private_ip  = "10.0.1.30"
worker_private_ip      = "10.0.1.40"

# SSH Access
# IMPORTANT: Change this to your IP address in production
# Example: admin_cidr_blocks = ["203.0.113.42/32"]
admin_cidr_blocks    = ["0.0.0.0/0"]

# Database Configuration
db_user              = "admin"
db_password          = "admin"  # CHANGE THIS IN PRODUCTION
db_name              = "combats"

# Git Repository (optional)
git_repo_url         = ""
