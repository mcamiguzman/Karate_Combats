terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# ===========================
# VPC & Networking
# ===========================

resource "aws_vpc" "karate_vpc" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "${var.project_name}-vpc"
  }
}

resource "aws_subnet" "public_subnet" {
  vpc_id                  = aws_vpc.karate_vpc.id
  cidr_block              = var.public_subnet_cidr
  availability_zone       = var.availability_zone
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.project_name}-public-subnet"
  }
}

resource "aws_internet_gateway" "karate_igw" {
  vpc_id = aws_vpc.karate_vpc.id

  tags = {
    Name = "${var.project_name}-igw"
  }
}

resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.karate_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.karate_igw.id
  }

  tags = {
    Name = "${var.project_name}-public-rt"
  }
}

resource "aws_route_table_association" "public_rt_assoc" {
  subnet_id      = aws_subnet.public_subnet.id
  route_table_id = aws_route_table.public_rt.id
}

# ===========================
# Security Groups
# ===========================

resource "aws_security_group" "api_sg" {
  name        = "${var.project_name}-api-sg"
  description = "Security group for API server"
  vpc_id      = aws_vpc.karate_vpc.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow HTTP from anywhere"
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow HTTPS from anywhere"
  }

  ingress {
    from_port   = 5000
    to_port     = 5000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow Flask API port from anywhere"
  }

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.admin_cidr_blocks
    description = "Allow SSH from admin IP"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound traffic"
  }

  tags = {
    Name = "${var.project_name}-api-sg"
  }
}

resource "aws_security_group" "rabbitmq_sg" {
  name        = "${var.project_name}-rabbitmq-sg"
  description = "Security group for RabbitMQ server"
  vpc_id      = aws_vpc.karate_vpc.id

  ingress {
    from_port       = 5672
    to_port         = 5672
    protocol        = "tcp"
    security_groups = [aws_security_group.api_sg.id, aws_security_group.worker_sg.id]
    description     = "Allow AMQP from API and Worker"
  }

  ingress {
    from_port       = 15672
    to_port         = 15672
    protocol        = "tcp"
    security_groups = [aws_security_group.api_sg.id, aws_security_group.worker_sg.id]
    description     = "Allow RabbitMQ Management UI from API and Worker"
  }

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.admin_cidr_blocks
    description = "Allow SSH from admin IP"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound traffic"
  }

  tags = {
    Name = "${var.project_name}-rabbitmq-sg"
  }
}

resource "aws_security_group" "postgresql_sg" {
  name        = "${var.project_name}-postgresql-sg"
  description = "Security group for PostgreSQL server"
  vpc_id      = aws_vpc.karate_vpc.id

  ingress {
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.api_sg.id, aws_security_group.worker_sg.id]
    description     = "Allow PostgreSQL from API and Worker"
  }

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.admin_cidr_blocks
    description = "Allow SSH from admin IP"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound traffic"
  }

  tags = {
    Name = "${var.project_name}-postgresql-sg"
  }
}

resource "aws_security_group" "worker_sg" {
  name        = "${var.project_name}-worker-sg"
  description = "Security group for Worker server"
  vpc_id      = aws_vpc.karate_vpc.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.admin_cidr_blocks
    description = "Allow SSH from admin IP"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound traffic"
  }

  tags = {
    Name = "${var.project_name}-worker-sg"
  }
}

resource "aws_security_group" "rabbitmq_sg" {
  subnet_id           = aws_subnet.public_subnet.id
  security_groups     = [aws_security_group.rabbitmq_sg.id]
  private_ips         = [var.rabbitmq_private_ip]

  tags = {
    Name = "${var.project_name}-rabbitmq-eni"
  }
}

resource "aws_network_interface" "postgresql_eni" {
  subnet_id           = aws_subnet.public_subnet.id
  security_groups     = [aws_security_group.postgresql_sg.id]
  private_ips         = [var.postgresql_private_ip]

  tags = {
    Name = "${var.project_name}-postgresql-eni"
  }
}

resource "aws_network_interface" "worker_eni" {
  subnet_id           = aws_subnet.public_subnet.id
  security_groups     = [aws_security_group.worker_sg.id]
  private_ips         = [var.worker_private_ip]

  tags = {
    Name = "${var.project_name}-worker-eni"
  }
}

# ===========================
# Elastic IPs
# ===========================

resource "aws_eip" "rabbitmq_eip" {
  domain              = "vpc"
  network_interface   = aws_network_interface.rabbitmq_eni.id
  depends_on          = [aws_internet_gateway.karate_igw]

  tags = {
    Name = "${var.project_name}-rabbitmq-eip"
  }
}

resource "aws_eip" "postgresql_eip" {
  domain              = "vpc"
  network_interface   = aws_network_interface.postgresql_eni.id
  depends_on          = [aws_internet_gateway.karate_igw]

  tags = {
    Name = "${var.project_name}-postgresql-eip"
  }
}

resource "aws_eip" "worker_eip" {
  domain              = "vpc"
  network_interface   = aws_network_interface.worker_eni.id
  depends_on          = [aws_internet_gateway.karate_igw]

  tags = {
    Name = "${var.project_name}-worker-eip"
  }
}

# ===========================
# EC2 Instances
# ===========================

# Data source to get the latest Ubuntu 22.04 LTS AMI
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# RabbitMQ Server
resource "aws_instance" "rabbitmq_server" {
  ami           = data.aws_ami.ubuntu.id
  instance_type = var.instance_type

  network_interface {
    network_interface_id = aws_network_interface.rabbitmq_eni.id
    device_index         = 0
  }

  user_data = base64encode(file("${path.module}/user_data/rabbitmq-userdata.sh"))

  root_block_device {
    volume_type           = "gp2"
    volume_size           = 20
    delete_on_termination = true
  }

  tags = {
    Name = "${var.project_name}-rabbitmq-server"
  }

  depends_on = [
    aws_eip.rabbitmq_eip
  ]
}

# PostgreSQL Server
resource "aws_instance" "postgresql_server" {
  ami           = data.aws_ami.ubuntu.id
  instance_type = var.instance_type

  network_interface {
    network_interface_id = aws_network_interface.postgresql_eni.id
    device_index         = 0
  }

  user_data = base64encode(templatefile("${path.module}/user_data/postgresql-userdata.sh", {
    DB_USER     = var.db_user
    DB_PASSWORD = var.db_password
    DB_NAME     = var.db_name
  }))

  root_block_device {
    volume_type           = "gp2"
    volume_size           = 30
    delete_on_termination = true
  }

  tags = {
    Name = "${var.project_name}-postgresql-server"
  }

  depends_on = [
    aws_eip.postgresql_eip
  ]
}

# Worker Server
resource "aws_instance" "worker_server" {
  ami           = data.aws_ami.ubuntu.id
  instance_type = var.instance_type

  network_interface {
    network_interface_id = aws_network_interface.worker_eni.id
    device_index         = 0
  }

  user_data = base64encode(templatefile("${path.module}/user_data/worker-userdata.sh", {
    DB_HOST       = var.postgresql_private_ip
    RABBITMQ_HOST = var.rabbitmq_private_ip
    RABBITMQ_PORT = 5672
    DB_PORT       = 5432
    DB_USER       = var.db_user
    DB_PASSWORD   = var.db_password
    DB_NAME       = var.db_name
    GIT_REPO_URL  = var.git_repo_url
  }))

  root_block_device {
    volume_type           = "gp2"
    volume_size           = 20
    delete_on_termination = true
  }

  tags = {
    Name = "${var.project_name}-worker-server"
  }

  depends_on = [
    aws_eip.worker_eip,
    aws_instance.postgresql_server,
    aws_instance.rabbitmq_server
  ]
}

# ===========================
# Application Load Balancer (ALB)
# ===========================

resource "aws_lb" "api_alb" {
  name               = "${var.project_name}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id]
  subnets            = [aws_subnet.public_subnet.id]

  enable_deletion_protection = false

  tags = {
    Name = "${var.project_name}-alb"
  }
}

resource "aws_lb_target_group" "api_tg" {
  name        = "${var.project_name}-api-tg"
  port        = 5000
  protocol    = "HTTP"
  vpc_id      = aws_vpc.karate_vpc.id
  target_type = "instance"

  health_check {
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 3
    interval            = 30
    path                = "/health"
    matcher             = "200"
  }

  tags = {
    Name = "${var.project_name}-api-tg"
  }
}

resource "aws_lb_listener" "api_listener" {
  load_balancer_arn = aws_lb.api_alb.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.api_tg.arn
  }
}

# ===========================
# Security Group for ALB
# ===========================

resource "aws_security_group" "alb_sg" {
  name        = "${var.project_name}-alb-sg"
  description = "Security group for Application Load Balancer"
  vpc_id      = aws_vpc.karate_vpc.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow HTTP from anywhere"
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow HTTPS from anywhere"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound traffic"
  }

  tags = {
    Name = "${var.project_name}-alb-sg"
  }
}

# ===========================
# Launch Template for API ASG
# ===========================

resource "aws_launch_template" "api_lt" {
  name_prefix   = "karate-api-"
  image_id      = data.aws_ami.ubuntu.id
  instance_type = var.instance_type

  iam_instance_profile {
    arn = aws_iam_instance_profile.api_profile.arn
  }

  security_groups = [aws_security_group.api_sg.id]

  user_data = base64encode(templatefile("${path.module}/user_data/api-userdata.sh", {
    DB_HOST       = var.postgresql_private_ip
    RABBITMQ_HOST = var.rabbitmq_private_ip
    RABBITMQ_PORT = 5672
    DB_PORT       = 5432
    DB_USER       = var.db_user
    DB_PASSWORD   = var.db_password
    DB_NAME       = var.db_name
    GIT_REPO_URL  = var.git_repo_url
  }))

  block_device_mappings {
    device_name = "/dev/sda1"

    ebs {
      volume_size           = 20
      volume_type           = "gp2"
      delete_on_termination = true
    }
  }

  tag_specifications {
    resource_type = "instance"

    tags = {
      Name = "${var.project_name}-api-asg-instance"
    }
  }

  lifecycle {
    create_before_destroy = true
  }
}

# ===========================
# IAM Role for API Instances
# ===========================

resource "aws_iam_role" "api_role" {
  name_prefix = "karate-api-"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy" "api_policy" {
  name_prefix = "karate-api-"
  role        = aws_iam_role.api_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:*:*"
      }
    ]
  })
}

resource "aws_iam_instance_profile" "api_profile" {
  name_prefix = "karate-api-"
  role        = aws_iam_role.api_role.name
}

# ===========================
# Auto Scaling Group for API
# ===========================

resource "aws_autoscaling_group" "api_asg" {
  name_prefix         = "karate-api-asg-"
  vpc_zone_identifier = [aws_subnet.public_subnet.id]
  target_group_arns   = [aws_lb_target_group.api_tg.arn]
  health_check_type   = "ELB"
  health_check_grace_period = 300

  min_size         = var.asg_min_size
  max_size         = var.asg_max_size
  desired_capacity = var.asg_desired_capacity

  launch_template {
    id      = aws_launch_template.api_lt.id
    version = "$Latest"
  }

  tag {
    key                 = "Name"
    value               = "${var.project_name}-api-asg"
    propagate_at_launch = true
  }

  lifecycle {
    create_before_destroy = true
  }

  depends_on = [
    aws_instance.postgresql_server,
    aws_instance.rabbitmq_server
  ]
}
