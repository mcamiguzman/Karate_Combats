# Karate Combats - AWS Deployment - Phase 2 Update

## Overview

This document summarizes the enhancements made in Phase 2 of the AWS migration:

1. **Application Load Balancer (ALB) + Auto Scaling Group (ASG)** for API tier
2. **PUT/DELETE endpoints** and **Orders table** for full CRUD operations
3. **AWS Academy Learner Lab** credentials support
4. **GitHub repository integration** for automated code deployment

---

## 1. Application Load Balancer & Auto Scaling

### Architecture Changes

**Before (Static):**
- 1 API Server instance (static EC2)
- 1 Elastic IP per instance
- No load distribution

**After (Scalable):**
- Application Load Balancer on port 80
- Auto Scaling Group managing 1-3 API instances
- Health checks every 30 seconds
- Automatic instance replacement on failure

### How It Works

```
Internet
   ↓
ALB (Load Balancer)
   ↓ (routes to healthy instances)
┌─────┬─────┬─────┐
│ API │ API │ API │
│ Inst│ Inst│ Inst│
├─────┼─────┼─────┤
│  1  │  2  │  3  │ ← ASG manages these
└─────┴─────┴─────┘
   ↓
RabbitMQ + PostgreSQL + Worker
```

### Key Features

- **Health Checks**: `GET /health` endpoint (new)
- **Min Size**: 1 instance
- **Max Size**: 3 instances (configurable)
- **Desired**: 1 instance (can be increased)
- **Rolling Updates**: Old instances replaced with new ones automatically

### Scaling Example

```hcl
# In terraform.tfvars
asg_min_size           = 1    # Always have at least 1
asg_max_size           = 3    # Never exceed 3
asg_desired_capacity   = 1    # Start with 1, can scale up to 3
```

### Access Methods

**Before:**
```bash
curl http://<API_IP>:5000/
```

**After (ALB):**
```bash
curl http://<ALB_DNS_NAME>/
# or
curl http://karate-combats-alb-123456.us-east-1.elb.amazonaws.com/
```

---

## 2. Complete CRUD Operations

### New Database Schema

#### Orders Table
```sql
CREATE TABLE orders (
    id SERIAL PRIMARY KEY,
    combat_id INT NOT NULL REFERENCES combats(id) ON DELETE CASCADE,
    consumer_id VARCHAR(100),
    action VARCHAR(50) NOT NULL,
    action_details JSONB,
    status VARCHAR(20) DEFAULT 'pending',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    completed_at TIMESTAMP
);
```

### New API Endpoints

#### 1. Create Combat (existing, enhanced)
```bash
POST /combats
Content-Type: application/x-www-form-urlencoded

time=2026-04-20T10:00:00&red=John Doe&blue=Jane Smith&points_red=5&points_blue=3&fouls_red=1&fouls_blue=2&judges=3
```
**Response**: 201 Created + list of combats

#### 2. Update Combat (NEW)
```bash
PUT /combats/<combat_id>
Content-Type: application/x-www-form-urlencoded

points_red=6&points_blue=3&fouls_red=1&fouls_blue=2&status=completed&judges=3
```
**Response**: 200 OK + updated list of combats

#### 3. Delete Combat (NEW)
```bash
DELETE /combats/<combat_id>
```
**Response**: 200 OK + remaining combats list

#### 4. Get Orders (NEW)
```bash
GET /orders
```
**Response**:
```json
{
    "orders": [
        {
            "id": 1,
            "combat_id": 5,
            "consumer_id": "user123",
            "action": "create",
            "status": "completed",
            "created_at": "2026-04-20T10:05:00"
        }
    ]
}
```

#### 5. Health Check (NEW)
```bash
GET /health
```
**Response**:
```json
{
    "status": "healthy",
    "service": "karate-api"
}
```

### Worker Processing

Worker now handles all three actions:

```python
# CREATE: Insert new combat + order record
# UPDATE: Modify combat fields + create order record  
# DELETE: Remove combat (cascade deletes orders) + create order record
```

All actions are logged in the `orders` table for audit trail.

---

## 3. AWS Academy Learner Lab Support

### What's New

- Credentials template file: `AWS_LAB_CREDENTIALS.template`
- Setup script: `setup-aws-lab-credentials.sh`
- Session token support in Terraform provider

### Setup Instructions

#### Step 1: Get Lab Credentials
1. Go to [AWS Academy Learner Lab](https://awsacademy.instructure.com)
2. Click your course
3. Click "Learner Lab - Sandbox"
4. Click orange "Start Lab" button
5. Wait for green light
6. Click "AWS Details"
7. Click "Show" next to "AWS CLI"

#### Step 2: Export Credentials (Terminal)

```bash
# Copy credentials from AWS Details, then in terminal:
export AWS_ACCESS_KEY_ID="your-key-id"
export AWS_SECRET_ACCESS_KEY="your-secret-key"
export AWS_SESSION_TOKEN="your-session-token"
export AWS_DEFAULT_REGION="us-east-1"

# Verify credentials work:
aws sts get-caller-identity
```

#### Step 3: Deploy with Terraform

```bash
cd terraform
terraform init
terraform plan
terraform apply
```

### Session Management

**Important Notes:**
- Lab sessions typically expire in **4 hours**
- You need **new credentials** for each session
- Always verify credentials with `aws sts get-caller-identity` before deploying
- Terraform will fail if credentials expire mid-deployment

### Credential Reference

See `AWS_LAB_CREDENTIALS.template` for exactly where to paste credentials.

### Region Lock

This lab is configured for **us-east-1 only**. Do not change the region!

```hcl
# terraform/terraform.tfvars
aws_region = "us-east-1"  # LOCKED - Do not change
```

---

## 4. GitHub Repository Integration

### How It Works

When ASG launches new API instances, they automatically:
1. Clone from: `https://github.com/mcamiguzman/Karate_Combats`
2. Install dependencies from `api/requirements.txt`
3. Start Flask application
4. Join the ALB target group

### Configuration

```hcl
# terraform/terraform.tfvars
git_repo_url = "https://github.com/mcamiguzman/Karate_Combats"
```

### What Gets Deployed

```
repository root
├── api/
│   ├── app.py              (Flask API with PUT/DELETE endpoints)
│   ├── requirements.txt     (dependencies)
│   └── templates/
│       └── index.html
├── db/
│   ├── init.sql            (includes Orders table)
└── worker/
    └── worker.py           (processes create/update/delete)
```

### Private Repository Support

If using a private repository, configure Git credentials:

```bash
# In user_data template, add credentials:
git clone https://username:token@github.com/user/repo.git

# Or use SSH keys:
git clone git@github.com:user/repo.git
```

---

## 5. Deployment Checklist

### Pre-Deployment
- [ ] AWS Academy Lab session started (green light)
- [ ] Credentials exported to terminal
- [ ] Verified credentials: `aws sts get-caller-identity`
- [ ] Updated `terraform.tfvars` if needed
- [ ] Terraform initialized: `terraform init`

### During Deployment
- [ ] Run: `terraform plan` (review changes)
- [ ] Run: `terraform apply` (create resources)
- [ ] Wait 5-10 minutes for initialization

### Post-Deployment
- [ ] Check ALB status: `terraform output api_url`
- [ ] Test API: `curl $(terraform output api_url)/`
- [ ] Check ASG: `terraform output asg_name`
- [ ] Monitor worker: `ssh ubuntu@<worker-ip>` → `sudo journalctl -u karate-worker -f`

---

## 6. New Terraform Files

### Updated Files
- `main.tf` - Added ALB, ASG, Launch Template, IAM resources
- `variables.tf` - Added ASG configuration variables
- `terraform.tfvars` - Git repo URL, ASG sizing
- `outputs.tf` - ALB DNS instead of individual IPs
- `user_data/api-userdata.sh` - GitHub cloning support

### New Files
- `setup-aws-lab-credentials.sh` - Lab credential setup guide
- `AWS_LAB_CREDENTIALS.template` - Credential template

---

## 7. Testing the New Features

### Test CRUD Operations

```bash
# Get ALB URL
ALB_URL=$(terraform output api_alb_dns_name)

# Create combat
curl -X POST http://$ALB_URL/combats \
  -d "time=2026-04-20T10:00:00&red=Fighter1&blue=Fighter2&points_red=5&points_blue=3&fouls_red=1&fouls_blue=2&judges=3"

# Get combat ID (assume 1)
COMBAT_ID=1

# Update combat
curl -X PUT http://$ALB_URL/combats/$COMBAT_ID \
  -d "points_red=7&status=completed"

# Get orders
curl http://$ALB_URL/orders

# Delete combat
curl -X DELETE http://$ALB_URL/combats/$COMBAT_ID

# Health check
curl http://$ALB_URL/health
```

### Monitor ASG

```bash
# Watch instance launches
aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names karate-combats-api-asg \
  --region us-east-1

# Watch ALB traffic
aws elbv2 describe-target-health \
  --target-group-arn $(terraform output alb_arn | jq -r '.') \
  --region us-east-1
```

---

## 8. Troubleshooting

### ALB Returns 502 Bad Gateway
**Cause**: ASG instances not healthy yet
**Fix**: Wait 2-3 minutes for initialization to complete
```bash
# Check target health
aws elbv2 describe-target-health --target-group-arn <tg-arn>
```

### Git Clone Fails
**Cause**: Private repo without credentials
**Fix**: 
1. Use public repo, OR
2. Add git credentials to user_data

### Session Token Expired
**Cause**: Lab session expired (>4 hours old)
**Fix**: 
1. Get new credentials from "AWS Details"
2. Export new credentials
3. Run terraform again

### ASG Won't Scale
**Cause**: Max instances reached
**Fix**: Increase `asg_max_size` in terraform.tfvars and reapply

---

## 9. Cost Implications

### Resources Added
- Application Load Balancer: ~$16/month
- Additional ENI (for ALB): ~$0.32/month
- ASG optimizations: No additional cost

### Cost Reduction Opportunities
- Set `asg_desired_capacity = 0` when not in use
- Use Savings Plans for committed usage
- Enable ALB access logs only when needed

---

## 10. Next Steps

### Immediate
- [ ] Deploy to AWS Academy Lab
- [ ] Test all CRUD operations
- [ ] Verify health checks working

### Short-term
- [ ] Add HTTPS/TLS to ALB
- [ ] Setup CloudWatch alarms
- [ ] Configure WAF rules

### Long-term
- [ ] Multi-AZ deployment
- [ ] RDS instead of EC2 PostgreSQL
- [ ] Lambda for microservices
- [ ] CI/CD pipeline integration

---

## Resources

- [Terraform ALB Documentation](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb)
- [Terraform ASG Documentation](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/autoscaling_group)
- [AWS Academy Documentation](https://docs.aws.amazon.com/academy/latest/user-guide/)
- [Flask PUT/DELETE Methods](https://flask.palletsprojects.com/decorators/#routing)

---

**Last Updated**: April 20, 2026  
**Terraform Version**: ~> 5.0  
**AWS Provider**: ~> 5.0  
**Lab Environment**: AWS Academy Learner Lab - us-east-1
