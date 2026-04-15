# AWS Deployment Guide - Karate Combats System

This document provides a comprehensive overview of the AWS cloud migration for the Karate Combats system.

## Quick Summary

The Karate Combats system has been prepared for AWS deployment with:

- **Code Refactoring**: Environment variables for database and RabbitMQ connectivity
- **Infrastructure as Code (IaC)**: Complete Terraform configuration for AWS deployment
- **Automated Initialization**: User data scripts for each service component
- **Production-Ready Security**: Least-privilege security groups and network isolation

## What's New

### 1. Application Code Changes

**Files Modified:**
- `api/app.py` - Now reads DB/RabbitMQ settings from environment variables
- `worker/worker.py` - Now reads DB/RabbitMQ settings from environment variables
- `.env.example` - Reference file showing all configurable environment variables

**Key Changes:**
- Removed hardcoded hostnames (`"db"`, `"rabbitmq"`)
- Imported `os` module to read environment variables
- Defaults to Docker Compose hostnames for backward compatibility

### 2. Terraform Infrastructure

**New Directory:** `terraform/`

**Core Files:**
- `main.tf` (500+ lines) - Complete AWS infrastructure definition
  - VPC with public subnet
  - 4 Security Groups with least-privilege rules
  - 4 Elastic IPs for stable public access
  - 4 EC2 instances (API, RabbitMQ, PostgreSQL, Worker)
  - Network configuration with proper routing

- `variables.tf` - All variable definitions with descriptions
- `terraform.tfvars` - Pre-configured values (customizable)
- `outputs.tf` - Useful outputs after deployment
- `README.md` - Complete deployment guide (see below)

**Deployment Scripts:** `user_data/`
- `api-userdata.sh` (130+ lines) - Initializes Flask API with nginx proxy
- `rabbitmq-userdata.sh` (110+ lines) - Installs and configures RabbitMQ
- `postgresql-userdata.sh` (120+ lines) - Installs PostgreSQL and initializes schema
- `worker-userdata.sh` (110+ lines) - Configures RabbitMQ consumer service

## System Architecture (AWS)

```
┌─────────────────────────────────────────────────────────────┐
│                        AWS VPC (10.0.0.0/16)                │
│                   Public Subnet (10.0.1.0/24)               │
│  ┌────────────────┬──────────────────┬────────────────────┐ │
│  │   API Server   │  RabbitMQ Server │  PostgreSQL Server │ │
│  │   (t3.micro)   │   (t3.micro)     │    (t3.micro)      │ │
│  │  10.0.1.10     │   10.0.1.20      │   10.0.1.30        │ │
│  │  Port 80/5000  │   Port 5672/UI   │   Port 5432        │ │
│  │  Elastic IP    │   Elastic IP     │   Elastic IP       │ │
│  └────────┬────────┴────────┬─────────┴────────┬───────────┘ │
│           │                 │                  │              │
│  ┌────────┴─────────────────┴──────────────────┴──────────┐  │
│  │             Worker Server (t3.micro)                   │  │
│  │              10.0.1.40 (Elastic IP)                    │  │
│  │             RabbitMQ Consumer Service                  │  │
│  └──────────────────────────────────────────────────────┘  │
│                                                              │
│  ┌──────────────────────────────────────────────────────┐  │
│  │           Internet Gateway (IGW)                     │  │
│  │        Route: 0.0.0.0/0 → IGW                       │  │
│  └──────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
```

## Deployment Workflow

### Phase 1: Pre-Deployment (Local Setup)

```bash
# 1. Record your IP address
YOUR_IP=$(curl -s https://api.ipify.org)
echo "Your IP: $YOUR_IP"

# 2. Create AWS EC2 Key Pair
aws ec2 create-key-pair --key-name karate-combats --region us-east-1 \
  --query 'KeyMaterial' --output text > karate-combats.pem
chmod 600 karate-combats.pem

# 3. Configure Terraform
cd terraform
# Edit terraform.tfvars:
#   - admin_cidr_blocks = ["$YOUR_IP/32"]  # Restrict SSH to your IP
#   - db_password = "STRONG_PASSWORD"       # Change from default
#   - any other customizations
```

### Phase 2: Deploy Infrastructure

```bash
cd terraform

# Initialize Terraform
terraform init

# Validate configuration
terraform validate

# Plan deployment
terraform plan -out=tfplan

# Apply configuration (creates AWS resources)
terraform apply tfplan

# Note: Wait 5-10 minutes for full initialization
```

### Phase 3: Post-Deployment Verification

```bash
# Get deployment information
terraform output

# SSH into API server (test connectivity)
ssh -i ../karate-combats.pem ubuntu@<API_PUBLIC_IP>
sudo systemctl status karate-api
exit

# Test API endpoint
curl http://<API_PUBLIC_IP>:5000/

# Access RabbitMQ dashboard
# Open: http://<RABBITMQ_PUBLIC_IP>:15672
# Credentials: guest / guest

# Test database (from API server)
ssh -i ../karate-combats.pem ubuntu@<API_PUBLIC_IP>
psql -U admin -d combats -h <POSTGRESQL_PRIVATE_IP> -c "SELECT COUNT(*) FROM combats;"
```

### Phase 4: Configure Application Code (if not in Git)

If you don't have a Git repository configured:

```bash
# On API server
ssh -i karate-combats.pem ubuntu@<API_PUBLIC_IP>
cd /opt/karate-api

# Upload application code (from local machine)
scp -i karate-combats.pem -r ../api/* ubuntu@<API_PUBLIC_IP>:/opt/karate-api/

# Restart service
sudo systemctl restart karate-api

# Similar steps for Worker server
```

## Environment Variables

Services use these environment variables. Defaults work for Docker Compose, but are overridden during AWS deployment:

```bash
# Database
DB_HOST=<postgresql-private-ip>    # Set by Terraform
DB_PORT=5432                       # PostgreSQL port
DB_USER=admin                      # Set by Terraform
DB_PASSWORD=<password>             # Set in terraform.tfvars
DB_NAME=combats                    # Database name

# RabbitMQ
RABBITMQ_HOST=<rabbitmq-private-ip>  # Set by Terraform
RABBITMQ_PORT=5672                   # AMQP port

# Flask (API only)
FLASK_ENV=production
FLASK_DEBUG=0
```

## Security Groups Configuration

### API Security Group
- **Inbound**:
  - Port 80 (HTTP): from anywhere
  - Port 443 (HTTPS): from anywhere
  - Port 5000 (Flask): from anywhere
  - Port 22 (SSH): from admin IP only
- **Outbound**: All traffic allowed

### RabbitMQ Security Group
- **Inbound**:
  - Port 5672 (AMQP): from API & Worker SGs
  - Port 15672 (Management): from API & Worker SGs
  - Port 22 (SSH): from admin IP only
- **Outbound**: All traffic allowed

### PostgreSQL Security Group
- **Inbound**:
  - Port 5432 (PostgreSQL): from API & Worker SGs only
  - Port 22 (SSH): from admin IP only
- **Outbound**: All traffic allowed

### Worker Security Group
- **Inbound**:
  - Port 22 (SSH): from admin IP only
- **Outbound**: All traffic allowed

## Monitoring & Management

### Check Service Status

```bash
# On each server
sudo systemctl status <service-name>
# Service names: karate-api, rabbitmq-server, postgresql, karate-worker

# View logs
sudo journalctl -u <service-name> -f
```

### Access Management Dashboards

- **API & Swagger Documentation**: `http://<API_IP>:5000` or `http://<API_IP>:5000/apidocs/`
- **RabbitMQ Management**: `http://<RABBITMQ_IP>:15672` (guest/guest)
- **PostgreSQL**: Connect via `psql` command-line tool

### Common Troubleshooting

```bash
# Test connectivity between services
ssh ubuntu@<API_IP>
nc -zv <RABBITMQ_IP> 5672      # Test RabbitMQ connection
nc -zv <POSTGRESQL_IP> 5432    # Test PostgreSQL connection

# Check service logs
sudo journalctl -u karate-worker -n 100 -f

# Manually restart a service
sudo systemctl restart karate-api
```

## Running End-to-End Tests

### Create a Combat Record

1. Open API in browser: `http://<API_PUBLIC_IP>:5000/`
2. Fill form with test data:
   - Time: `2026-04-14T10:00:00`
   - Red: `John Doe`
   - Blue: `Jane Smith`
   - Points Red: `5`
   - Points Blue: `3`
   - Fouls Red: `1`
   - Fouls Blue: `2`
   - Judges: `3`
3. Click "Create Combat"

### Verify Message in Queue

1. Open RabbitMQ: `http://<RABBITMQ_IP>:15672`
2. Navigate to **Queues** tab
3. Should see `combat_queue` with pending messages

### Verify Data in Database

1. SSH to PostgreSQL server
2. Connect to database:
   ```bash
   psql -U admin -d combats
   ```
3. Query combats:
   ```sql
   SELECT id, time, participant_red, participant_blue, status FROM combats ORDER BY id DESC LIMIT 5;
   ```
4. Should see the newly created combat with status "created"

## Cost Management

**Estimated Monthly Costs:**
- 4x t3.micro instances: $10
- 4x Elastic IPs: $14 (only charged if not in use)
- Network & Storage: Minimal
- **Total: ~$24/month** (varies by region)

**Cost Optimization:**
- Release unused Elastic IPs
- Use Savings Plans for longer commitments
- Monitor CloudWatch for unused resources
- Consider RDS for PostgreSQL (managed, included backups)

## Cleanup

To remove all AWS resources and avoid charges:

```bash
cd terraform
terraform destroy

# Confirm deletion when prompted
# WARNING: This deletes all infrastructure and data
```

## Next Steps

### For Development
- Push application code to Git repository for automated deployment
- Add CI/CD pipeline (GitHub Actions, GitLab CI, etc.)
- Implement application health checks

### For Production
- Use RDS (Relational Database Service) for PostgreSQL
- Add Application Load Balancer for API tier
- Implement Auto Scaling for Worker tier
- Enable CloudWatch monitoring and alarms
- Use AWS Secrets Manager for credentials
- Implement automated backups
- Add WAF (Web Application Firewall) for API security
- Enable VPC Flow Logs for network monitoring

### For High Availability
- Distribute across multiple Availability Zones
- Use RDS Multi-AZ for database redundancy
- Implement read replicas for PostgreSQL
- Add Route 53 for DNS failover

## Support Resources

- **Terraform Documentation**: https://www.terraform.io/docs
- **AWS Provider for Terraform**: https://registry.terraform.io/providers/hashicorp/aws/latest/docs
- **Karate Combats Repository**: [See project README.md](./README.md)
- **Terraform Deployment Guide**: [See terraform/README.md](./terraform/README.md)

---

**Created**: April 14, 2026
**Status**: Ready for AWS Deployment
**Last Verified**: Terraform 1.0+, AWS Provider 5.0+
