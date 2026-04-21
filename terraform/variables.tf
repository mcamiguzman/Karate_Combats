variable "aws_region" {
  description = "AWS region for resources"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Project name used for resource naming"
  type        = string
  default     = "karate-combats"
}

variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidr" {
  description = "CIDR block for public subnet"
  type        = string
  default     = "10.0.1.0/24"
}

variable "availability_zone" {
  description = "Availability zone for resources"
  type        = string
  default     = "us-east-1a"
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t3.micro"
}

variable "admin_cidr_blocks" {
  description = "CIDR blocks allowed for SSH admin access"
  type        = list(string)
  default     = ["0.0.0.0/0"]  # Change to your IP in production: ["YOUR_IP/32"]
}

# Private IP addresses for EC2 instances
variable "rabbitmq_private_ip" {
  description = "Private IP address for RabbitMQ server"
  type        = string
  default     = "10.0.1.20"
}

variable "postgresql_private_ip" {
  description = "Private IP address for PostgreSQL server"
  type        = string
  default     = "10.0.1.30"
}

variable "worker_private_ip" {
  description = "Private IP address for Worker server"
  type        = string
  default     = "10.0.1.40"
}

# Auto Scaling Group configuration for API tier
variable "asg_min_size" {
  description = "Minimum number of instances in API ASG"
  type        = number
  default     = 1
}

variable "asg_max_size" {
  description = "Maximum number of instances in API ASG"
  type        = number
  default     = 3
}

variable "asg_desired_capacity" {
  description = "Desired number of instances in API ASG"
  type        = number
  default     = 1
}

# Database configuration
variable "db_user" {
  description = "PostgreSQL database user"
  type        = string
  default     = "admin"
  sensitive   = true
}

variable "db_password" {
  description = "PostgreSQL database password"
  type        = string
  default     = "admin"
  sensitive   = true
}

variable "db_name" {
  description = "PostgreSQL database name"
  type        = string
  default     = "combats"
}

# RabbitMQ configuration
variable "rabbitmq_user" {
  description = "RabbitMQ username for application services"
  type        = string
  default     = "karate"
  sensitive   = true
}

variable "rabbitmq_password" {
  description = "RabbitMQ password for application services"
  type        = string
  default     = "karate_password"
  sensitive   = true
}

variable "git_repo_url" {
  description = "Git repository URL for application code"
  type        = string
  default     = "https://github.com/mcamiguzman/Karate_Combats"
}

# EC2 Key Pair for SSH access
variable "ec2_key_pair_name" {
  description = "EC2 key pair name for SSH access to instances"
  type        = string
  default     = "karate-combats"
}
