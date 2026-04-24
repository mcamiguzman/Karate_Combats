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
    from_port       = 5000
    to_port         = 5000
    protocol        = "tcp"
    security_groups = [aws_security_group.alb_sg.id]
    description     = "Allow Flask API port from ALB only"
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
    from_port   = 15672
    to_port     = 15672
    protocol    = "tcp"
    cidr_blocks = var.admin_cidr_blocks
    description = "Allow RabbitMQ Management UI from admin"
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

# ===========================
# Network Interfaces
# ===========================

resource "aws_network_interface" "rabbitmq_eni" {
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
