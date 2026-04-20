# Karate Combats System - AWS Terraform Deployment

This directory contains Terraform configurations to deploy the Karate Combats System on AWS with separate EC2 instances for each service component.

## Architecture Overview

- **API Server** (t3.micro): Flask REST API running on port 5000, fronted by nginx on port 80
- **RabbitMQ Server** (t3.micro): Message queue for asynchronous processing on port 5672, management UI on port 15672
- **PostgreSQL Server** (t3.micro): Relational database on port 5432
- **Worker Server** (t3.micro): RabbitMQ consumer service that processes messages and updates the database
- **VPC**: 10.0.0.0/16 with a public subnet 10.0.1.0/24
- **Security Groups**: Production-grade, least-privilege ingress rules

## Files Overview

- `main.tf` - Core infrastructure: VPC, subnets, security groups, EC2 instances, Elastic IPs
- `variables.tf` - Variable definitions with defaults
- `terraform.tfvars` - Terraform variable values (customize before deployment)
- `outputs.tf` - Output values displayed after deployment
- `user_data/` - Initialization scripts for each service:
  - `api-userdata.sh` - Installs Flask, nginx, and configures API server
  - `rabbitmq-userdata.sh` - Installs and configures RabbitMQ
  - `postgresql-userdata.sh` - Installs PostgreSQL and initializes database schema
  - `worker-userdata.sh` - Installs worker dependencies and configures consumer service

## Prerequisites

1. **Terraform installed** (v1.0 or later)
   ```bash
   terraform version
   ```

2. **AWS CLI configured** with valid credentials
   ```bash
   aws configure
   aws sts get-caller-identity
   ```

3. **EC2 Key Pair created** in your target region
   ```bash
   # Create a new key pair (do this in AWS console or CLI)
   aws ec2 create-key-pair --key-name karate-combats-key --region us-east-1 --query 'KeyMaterial' --output text > karate-combats-key.pem
   chmod 600 karate-combats-key.pem
   ```

4. **Application code ready** - Place `api/`, `worker/`, and `db/` directories in your Git repository or upload to S3

## Pre-Deployment Configuration

### 1. Update `terraform.tfvars`

```hcl
# Required changes:
aws_region           = "us-east-1"        # Your preferred region
instance_type        = "t3.micro"         # Instance type
admin_cidr_blocks    = ["YOUR_IP/32"]     # Your IP for SSH access (change from 0.0.0.0/0)
db_password          = "STRONG_PASSWORD"  # Change from default "admin"
```

### 2. (Optional) Set Git Repository URL

If you have a Git repository with your application code, update in `terraform.tfvars`:

```hcl
git_repo_url = "https://github.com/your-username/karate-combats.git"
```

Otherwise, you'll need to manually deploy the code after infrastructure creation.

## Deployment Steps

### Step 1: Initialize Terraform

```bash
cd terraform
terraform init
```

This downloads required Terraform providers and modules.

### Step 2: Validate Configuration

```bash
terraform validate
```

Checks for syntax errors and required variables.

### Step 3: Plan Deployment

```bash
terraform plan -out=tfplan
```

This shows what resources will be created. Review the output carefully.

Expected output includes:
- 1 VPC
- 1 subnet
- 1 Internet Gateway
- 1 Route Table
- 4 Security Groups (API, RabbitMQ, PostgreSQL, Worker)
- 4 Network Interfaces
- 4 Elastic IPs
- 4 EC2 Instances

### Step 4: Apply Configuration

```bash
terraform apply tfplan
```

This creates all AWS resources. Wait 5-10 minutes for infrastructure to be fully provisioned and services to initialize.

### Step 5: Retrieve Outputs

```bash
terraform output
```

This displays important information including:
- API Server public IP and URL
- RabbitMQ Management UI URL
- PostgreSQL connection details
- Worker server IP

## Post-Deployment Verification

### 1. Check EC2 Instances Status

```bash
terraform output ssh_to_api
terraform output ssh_to_rabbitmq
terraform output ssh_to_postgresql
terraform output ssh_to_worker
```

Use the provided SSH commands to verify each instance is running.

### 2. Access API Server

```bash
# Get API URL
terraform output api_url

# Test API (should return list of combats)
curl http://<API_PUBLIC_IP>:5000/

# Access Swagger documentation
curl http://<API_PUBLIC_IP>:5000/apidocs/
```

### 3. Access RabbitMQ Management UI

```bash
# Get RabbitMQ URL
terraform output rabbitmq_management_url

# Open in browser: http://<RABBITMQ_IP>:15672
# Default credentials: guest / guest
```

### 4. Test Database Connectivity

```bash
# SSH into PostgreSQL server
ssh -i karate-combats-key.pem ubuntu@<POSTGRESQL_IP>

# Connect to database
psql -U admin -d combats

# List tables (should see: combats, orders)
\dt

# Exit
\q
```

### 5. Test RabbitMQ Consumer

```bash
# SSH into Worker server
ssh -i karate-combats-key.pem ubuntu@<WORKER_IP>

# Check worker service status
sudo systemctl status karate-worker

# View logs
sudo journalctl -u karate-worker -f
```

### 6. End-to-End Test

1. Create a combat via the web UI: `http://<API_PUBLIC_IP>:5000/`
2. Verify the message appears in RabbitMQ:
   - Go to http://<RABBITMQ_IP>:15672
   - Navigate to Queues
   - Should see `combat_queue` with messages
3. Verify worker processes the message:
   - Check worker logs: `sudo journalctl -u karate-worker -f`
4. Verify data in database:
   - SSH to PostgreSQL and query: `SELECT * FROM combats ORDER BY id DESC LIMIT 1;`

## Troubleshooting

### Services not starting after deployment

**Check logs on each instance:**

```bash
# API Server
ssh -i karate-combats-key.pem ubuntu@<API_IP>
sudo systemctl status karate-api
sudo journalctl -u karate-api -n 50 -f

# Worker
ssh -i karate-combats-key.pem ubuntu@<WORKER_IP>
sudo systemctl status karate-worker
sudo journalctl -u karate-worker -n 50 -f

# Check connectivity between services
nc -zv <POSTGRESQL_IP> 5432
nc -zv <RABBITMQ_IP> 5672
```

### Database connection failed

1. Verify PostgreSQL is running: `sudo systemctl status postgresql`
2. Check security group allows port 5432 from other servers
3. Verify environment variables are set: `cat /opt/karate-worker/.env`

### RabbitMQ connection failed

1. Verify RabbitMQ is running: `sudo systemctl status rabbitmq-server`
2. Check management plugin enabled: `sudo rabbitmq-plugins list`
3. Verify erlang is installed: `erl -eval 'erlang:halt().'`

### Application code not deployed

If using Git repository, verify:
1. Repository is accessible from EC2 instances
2. Git credentials are configured (if private repo)
3. Application code is in the correct directory

Alternatively, manually deploy:
```bash
ssh -i karate-combats-key.pem ubuntu@<API_IP>
cd /opt/karate-api
# Manually upload and extract code
```

## Managing the Infrastructure

### View Current State

```bash
terraform show
```

### Update Configuration

Modify `terraform.tfvars` or `main.tf`, then:

```bash
terraform plan -out=tfplan
terraform apply tfplan
```

### Destroy Infrastructure

```bash
# WARNING: This will delete all resources
terraform destroy
```

## Security Considerations

1. **Change Database Password**: Update `db_password` in `terraform.tfvars` before deployment
2. **Restrict SSH Access**: Update `admin_cidr_blocks` with your specific IP instead of `0.0.0.0/0`
3. **Use Secrets Manager**: Consider using AWS Secrets Manager for credentials instead of tfvars
4. **Enable RabbitMQ Authentication**: Change default guest account password
5. **SSL/TLS Certificates**: Add SSL certificates to nginx for HTTPS
6. **Regular Backups**: Implement automated PostgreSQL backups using EBS snapshots

## Costs

**Estimated Monthly Cost (t3.micro instances):**
- 4x t3.micro EC2 instances: ~$10/month
- 4x Elastic IPs: ~$14/month (only charged when not in use)
- VPC & Network: Minimal to no charge
- **Total: ~$24/month (approximate)**

Note: Prices vary by region. t3.micro is free-tier eligible if within 12 months of AWS account creation.

## Next Steps

### For Production Deployment

1. Use RDS for PostgreSQL instead of self-managed EC2
2. Implement Application Load Balancer for API redundancy
3. Use Auto Scaling Groups for Worker instances
4. Enable CloudWatch alarms and monitoring
5. Configure automated backups and disaster recovery
6. Use AWS Systems Manager for application updates
7. Implement VPN or bastion host for SSH access

### For Development/Testing

1. Delete unused Elastic IPs to reduce costs
2. Use Elastic Compute Cloud (EC2) Savings Plans
3. Set up automatic shutdown of non-production instances

## Support & Resources

- [AWS Terraform Provider Documentation](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
- [Terraform Official Documentation](https://www.terraform.io/docs)
- [Karate Combats Repository](../README.md)

---

**Last Updated**: April 2026
**Terraform Version**: ~> 5.0
**AWS Provider Version**: ~> 5.0
