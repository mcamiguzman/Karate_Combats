# AWS Deployment Guide - Karate Combats System

This document provides a comprehensive overview of the AWS cloud migration for the Karate Combats system.

## Quick Summary

The Karate Combats system has been prepared for AWS deployment with:

- **Code Refactoring**: Environment variables for database and RabbitMQ connectivity
- **Infrastructure as Code (IaC)**: Complete Terraform configuration for AWS deployment
- **Automated Initialization**: User data scripts for each service component
- **Production-Ready Security**: Least-privilege security groups and network isolation

## What's New

### Phase 1: Foundation & Environment Variables

**Files Modified:**
- `api/app.py` - Now reads DB/RabbitMQ settings from environment variables
- `worker/worker.py` - Now reads DB/RabbitMQ settings from environment variables  
- `.env.example` - Reference file showing all configurable environment variables

**Key Changes:**
- Removed hardcoded hostnames (`"db"`, `"rabbitmq"`)
- Imported `os` module to read environment variables
- Defaults to Docker Compose hostnames for backward compatibility

### Phase 2: Production-Ready Features (NEW)

**Application Enhancements:**
- Application Load Balancer for automatic traffic distribution
- Auto Scaling Group (1-3 instances) for high availability
- Complete CRUD operations (Create, Read, Update, Delete)
- Orders table for transaction tracking and audit trail
- Health check endpoint (`GET /health`) for ALB monitoring
- New endpoints: `PUT /combats/<id>`, `DELETE /combats/<id>`, `GET /orders`

**Infrastructure Upgrades:**
- ALB replaces direct IP access - better for production
- Automatic instance replacement on failure
- 30-second health checks with 2-minute grace period
- Natural scaling: min=1, max=3, desired=1 (customizable)

**AWS Academy Learner Lab Support:**
- Session token credentials support
- Credential setup guide: `setup-aws-lab-credentials.sh`
- Credentials template: `AWS_LAB_CREDENTIALS.template`
- Region locked to us-east-1 (Learner Lab requirement)

**GitHub Integration:**
- Automatic code deployment from GitHub repository
- Repository URL: `https://github.com/mcamiguzman/Karate_Combats`
- New instances automatically clone latest code on startup

### 2. Terraform Infrastructure

**Core Files:**
- `main.tf` (700+ lines) - Complete AWS infrastructure including ALB/ASG:
  - VPC with public subnet
  - 5 Security Groups (4 services + 1 for ALB)
  - Launch Template for ASG instances
  - Application Load Balancer with health checks
  - Auto Scaling Group managing API tier
  - IAM roles for API instances
  - 3 Elastic IPs (RabbitMQ, PostgreSQL, Worker)
  - 3 EC2 instances (RabbitMQ, PostgreSQL, Worker)

- `variables.tf` - Variable definitions including ASG sizing
- `terraform.tfvars` - Pre-configured values with ASG settings
- `outputs.tf` - ALB DNS name instead of individual IPs
- `README.md` - Comprehensive deployment guide

**AWS Academy Lab Support:**
- `setup-aws-lab-credentials.sh` - Credential setup script
- `AWS_LAB_CREDENTIALS.template` - Credentials reference

**Deployment Scripts:** `user_data/`
- `api-userdata.sh` - Initializes Flask API with GitHub cloning
- `rabbitmq-userdata.sh` - Installs and configures RabbitMQ
- `postgresql-userdata.sh` - Installs PostgreSQL and Orders table
- `worker-userdata.sh` - Configures RabbitMQ consumer

## System Architecture (AWS)

```
┌─────────────────────────────────────────────────────────────┐
│                        AWS VPC (10.0.0.0/16)                │
│                   Public Subnet (10.0.1.0/24)               │
│  ┌──────────────────────────────────────────────────────┐   │
│  │              Application Load Balancer                │   │
│  │    DNS: karate-combats-alb-123.us-east-1.elb...     │   │
│  │           Port 80 → Health Check: /health            │   │
│  └──────────────────┬───────────────────────────────────┘   │
│                     │                                        │
│  ┌──────────────────┴───────────────────────────────────┐   │
│  │       Auto Scaling Group (Min:1, Max:3, Desired:1)  │   │
│  │  ┌────────────────┬────────────────┬───────────────┐ │   │
│  │  │   API Server   │   API Server   │  API Server   │ │   │
│  │  │   (instance 1) │  (instance 2)  │ (instance 3)  │ │   │
│  │  │  t3.micro      │   t3.micro     │   t3.micro    │ │   │
│  │  │  Port 5000     │   Port 5000    │   Port 5000   │ │   │
│  │  │  (Flask)       │   (Flask)      │   (Flask)     │ │   │
│  │  └────────────────┴────────────────┴───────────────┘ │   │
│  └──────────────────┬───────────────────────────────────┘   │
│                     │                                        │
│  ┌──────────────────┴─────────────────────────────────────┐ │
│  │           Backend Services (Static)                    │ │
│  │  ┌─────────────────┐  ┌──────────────┐  ┌──────────┐  │ │
│  │  │  RabbitMQ       │  │  PostgreSQL  │  │  Worker  │  │ │
│  │  │  (t3.micro)     │  │ (t3.micro)   │  │ (t3.micro)  │ │
│  │  │  10.0.1.20      │  │ 10.0.1.30    │  │ 10.0.1.40   │ │
│  │  │  Port 5672/UI   │  │ Port 5432    │  │            │ │
│  │  └─────────────────┘  └──────────────┘  └──────────┘  │ │
│  └──────────────────────────────────────────────────────┘  │
│                                                              │
│  ┌──────────────────────────────────────────────────────┐  │
│  │           Internet Gateway (IGW)                     │  │
│  │        Route: 0.0.0.0/0 → IGW                       │  │
│  └──────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
```

**Key Architecture Features:**
- **Load Balancing**: ALB distributes traffic across healthy instances
- **Auto Scaling**: ASG launches/terminates instances based on demand
- **High Availability**: Failed instances automatically replaced
- **Health Checks**: /health endpoint checked every 30 seconds
- **GitHub Integration**: Each new instance clones latest code
- **AWS Academy Lab**: Session tokens for temporary lab credentials

## Deployment Workflow

### Phase 1: Pre-Deployment (AWS Academy Learner Lab Setup)

#### Step 1: Get AWS Credentials

```bash
# 1. Log into https://awsacademy.instructure.com
# 2. Click your course → "Learner Lab - Sandbox"
# 3. Click orange "Start Lab" button
# 4. Wait for the light to turn green
# 5. Click "AWS Details"
# 6. Click "Show" next to "AWS CLI"
# 7. Copy the displayed credentials
```

#### Step 2: Export Credentials to Terminal

```bash
# Paste credentials from AWS Academy Dashboard:
export AWS_ACCESS_KEY_ID="your-access-key-id"
export AWS_SECRET_ACCESS_KEY="your-secret-access-key"
export AWS_SESSION_TOKEN="your-session-token"
export AWS_DEFAULT_REGION="us-east-1"

# Verify credentials are working:
aws sts get-caller-identity
# Should return your account info and assumed role
```

#### Step 3: Create EC2 Key Pair

```bash
# Create key pair for SSH access to instances:
aws ec2 create-key-pair --key-name karate-combats --region us-east-1 \
  --query 'KeyMaterial' --output text > karate-combats.pem
chmod 600 karate-combats.pem
```

#### Step 4: Configure Terraform

```bash
cd terraform

# Edit terraform.tfvars:
#   - admin_cidr_blocks = ["0.0.0.0/0"]  # For lab (restrict in prod)
#   - db_password = "lab-password"        # Change if desired
#   - git_repo_url = "https://github.com/mcamiguzman/Karate_Combats"
#   - asg_desired_capacity = 1            # Start with 1 instance
```

### Phase 2: Deploy Infrastructure

```bash
cd terraform

# Initialize Terraform
terraform init

# Validate configuration
terraform validate

# Plan deployment (review changes)
terraform plan -out=tfplan

# Apply configuration (creates AWS resources)
terraform apply tfplan

# Important: Wait 5-10 minutes for:
# - EC2 instances to start and initialize
# - ASG instances to join target group
# - Health checks to pass
# - API instances to clone code and start Flask
```

### Phase 3: Post-Deployment Verification

```bash
# Get deployment information
terraform output

# Get ALB DNS name
ALB_DNS=$(terraform output api_alb_dns_name)
echo "API URL: http://$ALB_DNS"

# Test API health check (should return {"status": "healthy"})
curl http://$ALB_DNS/health

# Test API root endpoint (should return HTML)
curl http://$ALB_DNS/

# Access RabbitMQ dashboard
RABBITMQ_IP=$(terraform output rabbitmq_public_ip)
echo "RabbitMQ: http://$RABBITMQ_IP:15672"
# Credentials: guest / guest

# Check ASG status
ASG_NAME=$(terraform output asg_name)
aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names $ASG_NAME --region us-east-1
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
## API Endpoints Reference

The application supports full CRUD operations. All requests go through the Application Load Balancer (ALB):

```bash
ALB_DNS=$(terraform output api_alb_dns_name)
echo "API Base URL: http://$ALB_DNS"
```

### Endpoints

| Method | Endpoint | Purpose | Access |
|--------|----------|---------|--------|
| GET | `/` | Web UI | Browser/ALB |
| GET | `/health` | Health check | ALB (30s interval) |
| POST | `/combats` | Create combat | Form/ALB |
| GET | `/combats` | List all combats | Web UI |
| PUT | `/combats/<id>` | Update combat | Form/ALB |
| DELETE | `/combats/<id>` | Delete combat | Form/ALB |
| GET | `/orders` | List all orders (audit trail) | Web UI |
| GET | `/apidocs` | Swagger documentation | Browser |

### Example Requests (via ALB DNS)

```bash
# Get health status
curl http://$ALB_DNS/health
# Returns: {"status": "healthy", "database": "connected"}

# Create combat
curl -X POST http://$ALB_DNS/combats \
  -d "time=2024-01-15&participants_red=Alice&participants_blue=Bob&judges=John&status=pending"

# Update combat (change points)
curl -X PUT http://$ALB_DNS/combats/1 \
  -d "points_red=5&points_blue=3&status=running"

# Delete combat
curl -X DELETE http://$ALB_DNS/combats/1

# Get order audit trail (transactions)
curl http://$ALB_DNS/orders | jq .
```

### Orders Table (Transaction Audit)

Every action (create/update/delete) creates an audit record:

```json
{
  "id": 42,
  "combat_id": 1,
  "action": "update",
  "action_details": {"points_red": "5", "points_blue": "3"},
  "status": "completed",
  "created_at": "2024-01-15T10:30:00Z",
  "updated_at": "2024-01-15T10:30:00Z",
  "completed_at": "2024-01-15T10:30:00Z"
}
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

### ALB Security Group
- **Inbound**:
  - Port 80 (HTTP): from anywhere
  - Port 443 (HTTPS): from anywhere (reserved for future use)
- **Outbound**: All traffic to API SG

### API Security Group (ASG)
- **Inbound**:
  - Port 5000 (Flask): from ALB SG only
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

### Application Load Balancer (ALB) Monitoring

```bash
# Get ALB details
aws elbv2 describe-load-balancers --region us-east-1 | jq '.LoadBalancers[] | .LoadBalancerName, .DNSName'

# Get target group health
ASG_NAME=$(terraform output asg_name)
TARGET_GROUP_ARN=$(terraform output target_group_arn 2>/dev/null || echo "Not available")

aws elbv2 describe-target-health --target-group-arn $TARGET_GROUP_ARN --region us-east-1
# Should show instances as "healthy"

# Get ALB access logs (if health check fails)
curl http://<ALB_DNS>/health -v
# Should return: {"status": "healthy", "database": "connected"}
```

### Auto Scaling Group (ASG) Monitoring

```bash
# Get ASG details
ASG_NAME=$(terraform output asg_name)
aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names $ASG_NAME \
  --region us-east-1

# Describe instances in ASG
aws autoscaling describe-auto-scaling-instances \
  --region us-east-1 | jq '.AutoScalingInstances[] | select(.AutoScalingGroupName == "'$ASG_NAME'")'

# Monitor scaling activities
aws autoscaling describe-scaling-activities \
  --auto-scaling-group-name $ASG_NAME \
  --max-records 10 \
  --region us-east-1
```

### Check Service Status

```bash
# On each server
ssh -i karate-combats.pem ubuntu@<INSTANCE_IP>
sudo systemctl status <service-name>
# Service names: karate-api, rabbitmq-server, postgresql, karate-worker

# View logs
sudo journalctl -u <service-name> -f

# Exit SSH
exit
```

### Access Management Dashboards

- **API Web UI & Swagger Documentation**: `http://<ALB_DNS>` or `http://<ALB_DNS>/apidocs/`
- **RabbitMQ Management**: `http://<RABBITMQ_PUBLIC_IP>:15672` (guest/guest)
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

## AWS Academy Learner Lab Session Management

### Important Notes

1. **Session Expiration**: AWS Academy Learner Lab sessions expire after 4 hours
2. **Credentials Validity**: Session tokens become invalid when session expires
3. **Budget Limit**: Lab has a $100 limit; using all budget shuts down infrastructure
4. **Region Lock**: Must use `us-east-1` region only

### Session Workflow

```bash
# 1. Start new lab session
# Open: https://awsacademy.instructure.com
# Click your course → "Learner Lab - Sandbox"
# Click orange "Start Lab" button
# Wait for green light

# 2. Get fresh credentials for new session
# Click "AWS Details" → "Show" next to "AWS CLI"
# Copy credentials and export them

export AWS_ACCESS_KEY_ID="new-access-key"
export AWS_SECRET_ACCESS_KEY="new-secret-key"
export AWS_SESSION_TOKEN="new-session-token"
export AWS_DEFAULT_REGION="us-east-1"

# 3. Verify new credentials work
aws sts get-caller-identity

# 4. Deploy infrastructure (Terraform will use new credentials)
cd terraform
terraform apply tfplan
```

### Before Session Expires

```bash
# 1. Check remaining time
# Look at Learner Lab dashboard - shows time remaining

# 2. Save important data (optional before logout)
ALB_DNS=$(terraform output api_alb_dns_name)
echo "API URL for next session: http://$ALB_DNS"

# 3. Document any important findings
# Take screenshots of RabbitMQ/PostgreSQL/ASG status

# 4. Note: Don't need to destroy infrastructure
# Session will automatically start fresh next time
```

### Troubleshooting Session Issues

```bash
# Error: "ExpiredToken" or credentials invalid
# → Session expired. Get new credentials and export them again

# Error: "UnauthorizedOperation"
# → Session ended. Start new lab session and export new credentials

# Terraform apply stalled
# → Session credentials likely expired. Get new credentials and retry

# Check current session validity
aws sts get-caller-identity
# If fails, session is expired
```

## Cost Management

**AWS Academy Learner Lab:**
- **Budget**: $100 per session (separate from regular AWS)
- **Duration**: 4-hour session
- **Costs**: t3.micro instances, Elastic IPs, data transfer
- **After Budget**: Infrastructure stops automatically

**Estimated Resource Usage:**
- 4x t3.micro instances: ~$4 for 10-hour usage
- 3x Elastic IPs: ~$3 total (if not released)
- Network & Storage: Minimal
- **Current Lab Run**: ~$10-15 for 4-hour session

**Cost Optimization:**
- Release unused Elastic IPs when no longer needed
- Use 1-instance ASG for testing (min=1, max=1)
- Delete infrastructure after testing
- Keep data in PostgreSQL if instances deleted (backups available)

## Cleanup

### For AWS Academy Learner Lab

```bash
# Option 1: End session normally
# Just close the Learner Lab or click "End Lab" button
# Infrastructure will be destroyed automatically
# All data will be lost
# Credentials will become invalid

# Option 2: Save data before session ends
# Use PHASE_2_UPDATES.md for exact schema
# Export PostgreSQL data if needed (before session ends)

# Next session:
# All infrastructure must be redeployed
# Use: terraform apply
```

### For Regular AWS Accounts

To remove all infrastructure and avoid charges:

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
