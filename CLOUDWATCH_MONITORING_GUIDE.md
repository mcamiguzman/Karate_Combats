# CloudWatch Monitoring Guide for Karate Combats Infrastructure

## Overview

This guide provides CloudWatch monitoring recommendations for detecting and responding to infrastructure failures, particularly focusing on service initialization failures in RabbitMQ, PostgreSQL, Worker, and API instances.

## Problem Statement

When an EC2 instance is deployed via Terraform with cloud-init user data scripts, failures during initialization can be difficult to detect without proper monitoring. Specifically:

- **cloud-final.service** states indicate overall user_data script completion
- `FAILED` state means the script exited with non-zero status
- Without CloudWatch alarms, these failures go unnoticed until users report issues

This guide enables proactive detection of initialization failures through CloudWatch Logs and Events.

---

## Part 1: CloudWatch Agent Setup on EC2 Instances

### 1.1 Install CloudWatch Agent on RabbitMQ Instance

The RabbitMQ user data script at `/var/log/rabbitmq-init.log` should be monitored. To set up CloudWatch monitoring:

#### Option A: Via Terraform (Recommended for Full Automation)

Add this to your `api-userdata.sh`, `postgresql-userdata.sh`, `worker-userdata.sh`, and `rabbitmq-userdata.sh`:

```bash
# Install CloudWatch Agent
wget https://s3.amazonaws.com/amazoncloudwatch-agent/ubuntu/amd64/latest/amazon-cloudwatch-agent.deb
dpkg -i -E ./amazon-cloudwatch-agent.deb

# Configure CloudWatch Agent to stream logs
cat > /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json << 'EOF'
{
  "logs": {
    "logs_collected": {
      "files": {
        "collect_list": [
          {
            "file_path": "/var/log/rabbitmq-init.log",
            "log_group_name": "/aws/ec2/karate-combats/rabbitmq-init",
            "log_stream_name": "{instance_id}-{hostname}",
            "timestamp_format": "%Y-%m-%d %H:%M:%S"
          },
          {
            "file_path": "/var/log/rabbitmq/rabbit@*.log",
            "log_group_name": "/aws/ec2/karate-combats/rabbitmq-service",
            "log_stream_name": "{instance_id}-{hostname}",
            "timestamp_format": "%Y-%m-%d %H:%M:%S"
          },
          {
            "file_path": "/var/log/cloud-init.log",
            "log_group_name": "/aws/ec2/karate-combats/cloud-init",
            "log_stream_name": "{instance_id}-{hostname}",
            "timestamp_format": "%Y-%m-%d %H:%M:%S"
          },
          {
            "file_path": "/var/log/cloud-init-output.log",
            "log_group_name": "/aws/ec2/karate-combats/cloud-init-output",
            "log_stream_name": "{instance_id}-{hostname}",
            "timestamp_format": "%Y-%m-%d %H:%M:%S"
          }
        ]
      }
    }
  }
}
EOF

# Start the CloudWatch Agent
/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
  -a query -m ec2 -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json \
  -a fetch-config -m ec2 -s

/opt/aws/amazon-cloudwatch-agent-ctl -a start -m ec2 -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json -s
```

#### Option B: Manual Setup (For Immediate Troubleshooting)

1. SSH into the RabbitMQ instance
2. Download and install the agent:
   ```bash
   wget https://s3.amazonaws.com/amazoncloudwatch-agent/ubuntu/amd64/latest/amazon-cloudwatch-agent.deb
   sudo dpkg -i amazon-cloudwatch-agent.deb
   ```
3. Configure and start the agent (see config above)
4. Verify status:
   ```bash
   sudo /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
     -a query -m ec2
   ```

### 1.2 IAM Role Permissions

The EC2 instances require an IAM instance profile with `CloudWatchAgentServerPolicy`:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "cloudwatch:PutMetricData",
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents",
        "logs:DescribeLogStreams"
      ],
      "Resource": "*"
    }
  ]
}
```

Add this to [terraform/main.tf](terraform/main.tf) as an IAM role and instance profile for each service's security group.

---

## Part 2: CloudWatch Log Groups and Streams

### 2.1 Create Log Groups

Create CloudWatch Log Groups for each service:

```
/aws/ec2/karate-combats/rabbitmq-init
/aws/ec2/karate-combats/rabbitmq-service
/aws/ec2/karate-combats/postgresql-init
/aws/ec2/karate-combats/postgresql-service
/aws/ec2/karate-combats/worker-init
/aws/ec2/karate-combats/api-init
/aws/ec2/karate-combats/cloud-init
/aws/ec2/karate-combats/cloud-init-output
```

### 2.2 Log Retention Policy

Set retention to **30 days** for cost management:

**Via AWS CLI:**
```bash
aws logs put-retention-policy \
  --log-group-name /aws/ec2/karate-combats/rabbitmq-init \
  --retention-in-days 30 \
  --region us-east-1
```

**Via Terraform:**
```hcl
resource "aws_cloudwatch_log_group" "rabbitmq_init" {
  name              = "/aws/ec2/karate-combats/rabbitmq-init"
  retention_in_days = 30

  tags = {
    Name = "karate-combats-rabbitmq-init-logs"
  }
}
```

---

## Part 3: CloudWatch Alarms

### 3.1 RabbitMQ Service Failure Alarm

Trigger alarm when ERROR keywords appear in RabbitMQ initialization logs:

```hcl
resource "aws_cloudwatch_log_group" "rabbitmq_init" {
  name              = "/aws/ec2/karate-combats/rabbitmq-init"
  retention_in_days = 30
}

resource "aws_cloudwatch_log_stream" "rabbitmq_init_stream" {
  name           = "rabbitmq-init-stream"
  log_group_name = aws_cloudwatch_log_group.rabbitmq_init.name
}

resource "aws_cloudwatch_metric_alarm" "rabbitmq_init_errors" {
  alarm_name          = "karate-combats-rabbitmq-init-errors"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "ErrorCount"
  namespace           = "KarateCombats/RabbitMQ"
  period              = 60
  statistic           = "Sum"
  threshold           = 1
  alarm_description   = "Alert when RabbitMQ initialization logs contain errors"
  treat_missing_data  = "notBreaching"

  alarm_actions = [aws_sns_topic.karate_alerts.arn]

  depends_on = [
    aws_cloudwatch_log_group.rabbitmq_init
  ]
}

# Metric filter to count ERROR lines
resource "aws_cloudwatch_log_metric_filter" "rabbitmq_errors" {
  name           = "rabbitmq-init-errors"
  log_group_name = aws_cloudwatch_log_group.rabbitmq_init.name
  filter_pattern = "[time, level = ERROR*]"

  metric_transformation {
    name      = "ErrorCount"
    namespace = "KarateCombats/RabbitMQ"
    value     = "1"
  }
}
```

### 3.2 Cloud-Init Failure Detection

Detect `cloud-final.service` failures by monitoring `/var/log/cloud-init-output.log`:

```hcl
resource "aws_cloudwatch_metric_alarm" "cloud_final_failure" {
  alarm_name          = "karate-combats-cloud-final-service-failure"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "CloudFinalFailures"
  namespace           = "KarateCombats/CloudInit"
  period              = 300  # 5 minutes
  statistic           = "Sum"
  threshold           = 1
  alarm_description   = "Alert when cloud-final.service reports a failure status"
  treat_missing_data  = "notBreaching"

  alarm_actions = [aws_sns_topic.karate_alerts.arn]
}

# Metric filter for cloud-final failures
resource "aws_cloudwatch_log_metric_filter" "cloud_final_failures" {
  name           = "cloud-final-service-failures"
  log_group_name = "/aws/ec2/karate-combats/cloud-init-output"
  filter_pattern = "[*, status = *Failed*] || [*, status = *failed*]"

  metric_transformation {
    name      = "CloudFinalFailures"
    namespace = "KarateCombats/CloudInit"
    value     = "1"
  }
}
```

### 3.3 Health Check Failure Alarm

Monitor API `/health` endpoint failures indicating database or RabbitMQ connectivity issues:

```hcl
resource "aws_cloudwatch_metric_alarm" "health_check_failures" {
  alarm_name          = "karate-combats-api-health-failures"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 2
  metric_name         = "HealthCheckFailure"
  namespace           = "AWS/ApplicationELB"
  period              = 60
  statistic           = "Sum"
  threshold           = 2
  alarm_description   = "Alert when ALB detects API health check failures"
  treat_missing_data  = "notBreaching"

  dimensions = {
    TargetGroup  = aws_lb_target_group.api_tg.name
    LoadBalancer = aws_lb.api_alb.name
  }

  alarm_actions = [aws_sns_topic.karate_alerts.arn]
}
```

### 3.4 RabbitMQ Connection Attempt Failures

Monitor for repeated `AMQPConnectionError` in API logs:

```hcl
resource "aws_cloudwatch_metric_alarm" "api_rabbitmq_failures" {
  alarm_name          = "karate-combats-api-rabbitmq-failures"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "RabbitMQConnectionFailures"
  namespace           = "KarateCombats/API"
  period              = 60
  statistic           = "Sum"
  threshold           = 3
  alarm_description   = "Alert when API fails to connect to RabbitMQ 3+ times in 60 seconds"
  treat_missing_data  = "notBreaching"

  alarm_actions = [aws_sns_topic.karate_alerts.arn]
}

# Metric filter for API RabbitMQ failures
resource "aws_cloudwatch_log_metric_filter" "api_rabbitmq_errors" {
  name           = "api-rabbitmq-failures"
  log_group_name = "/aws/ec2/karate-combats/api-init"
  filter_pattern = "[*, level = *WARNING*, msg = *RabbitMQ*connection*failed*]"

  metric_transformation {
    name      = "RabbitMQConnectionFailures"
    namespace = "KarateCombats/API"
    value     = "1"
  }
}
```

---

## Part 4: SNS Notifications Setup

### 4.1 Create SNS Topic for Alerts

```hcl
resource "aws_sns_topic" "karate_alerts" {
  name = "karate-combats-infrastructure-alerts"

  tags = {
    Name = "karate-combats-alerts"
  }
}

resource "aws_sns_topic_subscription" "karate_alerts_email" {
  topic_arn = aws_sns_topic.karate_alerts.arn
  protocol  = "email"
  endpoint  = "your-email@example.com"  # Replace with your email
}
```

### 4.2 Verify Email Subscription

After creating the SNS topic subscription, check your email for AWS SNS confirmation and click the confirmation link.

---

## Part 5: CloudWatch Dashboard

Create a dashboard to visualize all metrics:

```hcl
resource "aws_cloudwatch_dashboard" "karate_infrastructure" {
  dashboard_name = "karate-combats-infrastructure"

  dashboard_body = jsonencode({
    widgets = [
      {
        type = "metric"
        properties = {
          metrics = [
            ["AWS/EC2", "StatusCheckFailed", { stat = "Sum" }],
            ["AWS/ApplicationELB", "HealthyHostCount"],
            ["AWS/ApplicationELB", "UnHealthyHostCount"],
            ["KarateCombats/RabbitMQ", "ErrorCount"],
            ["KarateCombats/API", "RabbitMQConnectionFailures"],
            ["KarateCombats/CloudInit", "CloudFinalFailures"]
          ]
          period = 300
          stat   = "Average"
          region = "us-east-1"
          title  = "Infrastructure Health Overview"
        }
      }
    ]
  })
}
```

---

## Part 6: Troubleshooting Guide

### 6.1 Check Logs Remotely Without SSH

**View RabbitMQ Initialization Logs:**
```bash
aws logs tail /aws/ec2/karate-combats/rabbitmq-init --follow
```

**View Error Pattern:**
```bash
aws logs filter-log-events \
  --log-group-name /aws/ec2/karate-combats/rabbitmq-init \
  --filter-pattern "ERROR"
```

**Get Last 100 Lines:**
```bash
aws logs tail /aws/ec2/karate-combats/rabbitmq-init --max-items 100
```

### 6.2 Common Issues and Detection

| Issue | Symptom | CloudWatch Pattern | Resolution |
|-------|---------|-------------------|-----------|
| RabbitMQ failed to install | "ERROR: Failed to install RabbitMQ" in logs | `ERROR` in `/rabbitmq-init` | Check repository key download, Erlang installation |
| Port binding failed | "ERROR: RabbitMQ AMQP port (5672) not listening" | `5672.*not listening` | Verify security groups, systemd limits |
| Guest user still active | API/Worker can't authenticate | Check `/var/log/rabbitmq-init.log` for "guest user removed" | Review script output, manually delete guest user |
| Cloud-init timeout | Instance never becomes healthy | `cloud-final.service` shows `failed` | Increase health_check_grace_period in ASG (currently 300s) |
| Plugin not loaded | Management UI times out at port 15672 | `rabbitmq_management plugin not loaded` | Check for plugin enable/restart race condition |

### 6.3 Manual Verification Steps

**SSH into RabbitMQ instance and verify:**

```bash
# Check service status
sudo systemctl status rabbitmq-server

# Check ports listening
sudo ss -tlnp | grep -E '5672|15672'

# Check users
sudo rabbitmqctl list_users

# View initialization log
tail -100 /var/log/rabbitmq-init.log

# View service logs
tail -100 /var/log/rabbitmq/rabbit@hostname.log

# Check cloud-init status
cloud-init status
systemctl list-units --type=service | grep cloud-final
```

---

## Part 7: Implementation Roadmap

### Phase 1: Basic Monitoring (Immediate)
- [ ] Deploy CloudWatch agent via updated user data scripts
- [ ] Create CloudWatch Log Groups
- [ ] Set retention policies to 30 days
- [ ] Create SNS topic for email notifications

### Phase 2: Metric Filters & Alarms (Week 1)
- [ ] Add metric filters for ERROR patterns in each service
- [ ] Create CloudWatch alarms for initialization failures
- [ ] Create alarms for RabbitMQ connection errors
- [ ] Create alarms for cloud-final.service failures

### Phase 3: Dashboard & Visualization (Week 2)
- [ ] Create unified CloudWatch Dashboard
- [ ] Add widgets for health check metrics
- [ ] Add widgets for service initialization status

### Phase 4: Automation & Recovery (Week 3)
- [ ] Consider Lambda function to auto-terminate and replace failed instances
- [ ] Create EventBridge rules for cloud-final failures
- [ ] Document runbook for manual intervention

---

## Part 8: Cost Estimation

Based on typical usage:

| Service | Monthly Cost |
|---------|-------------|
| CloudWatch Logs (5 instances × 100 MB/month) | ~$2.50 |
| Metric Filters (6 filters) | ~$5.00 |
| CloudWatch Alarms (8 alarms) | ~$0.80 |
| SNS Email Notifications (50/month) | ~$0.00 |
| Dashboard (1 dashboard) | ~$0.00 |
| **Total Estimated Monthly Cost** | **~$8.30** |

---

## Part 9: References

- [AWS CloudWatch Documentation](https://docs.aws.amazon.com/cloudwatch/)
- [CloudWatch Agent Configuration Reference](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/CloudWatch-Agent-Configuration-File-Details.html)
- [Metric Filters Documentation](https://docs.aws.amazon.com/AmazonCloudWatch/latest/logs/FilterAndPatternSyntax.html)
- [Log Group Tagging for Organization](https://docs.aws.amazon.com/waf/latest/developerguide/tag-resources.html)

---

## Notes

- **Sensitive Data**: Ensure password fields in logs are redacted before monitoring.
- **Log Retention**: Experiment with retention periods; current recommendation is 30 days for cost balance.
- **Regional Deployment**: All resources should be in `us-east-1` as defined in `variables.tf`.
- **IAM Permissions**: Ensure EC2 instance role has proper permissions before deploying.

