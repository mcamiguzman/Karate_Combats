#!/bin/bash
set -e
trap 'echo "ERROR at line $LINENO" | tee -a /var/log/rabbitmq-init.log; exit 1' ERR

RABBITMQ_USER="${RABBITMQ_USER}"
RABBITMQ_PASSWORD="${RABBITMQ_PASSWORD}"

exec 1> >(tee -a /var/log/rabbitmq-init.log)
exec 2>&1

echo "=== RabbitMQ init: $(date) ==="

apt-get update && apt-get upgrade -y || exit 1
apt-get install -y curl gnupg apt-transport-https lsb-release netcat-traditional || exit 1

curl -1sLf https://keys.openpgp.org/vks/v1/by-fingerprint/0A9AF2115F4687BD29803A206B73A36E6026DFCA 2>/dev/null | gpg --dearmor | tee /usr/share/keyrings/com.rabbitmq.team.gpg > /dev/null || exit 1

cat > /etc/apt/sources.list.d/rabbitmq.list << 'EOF'
## Modern Erlang/OTP releases
deb [arch=amd64 signed-by=/usr/share/keyrings/com.rabbitmq.team.gpg] https://deb1.rabbitmq.com/rabbitmq-erlang/ubuntu/jammy jammy main
deb [arch=amd64 signed-by=/usr/share/keyrings/com.rabbitmq.team.gpg] https://deb2.rabbitmq.com/rabbitmq-erlang/ubuntu/jammy jammy main

## Latest RabbitMQ releases
deb [arch=amd64 signed-by=/usr/share/keyrings/com.rabbitmq.team.gpg] https://deb1.rabbitmq.com/rabbitmq-server/ubuntu/jammy jammy main
deb [arch=amd64 signed-by=/usr/share/keyrings/com.rabbitmq.team.gpg] https://deb2.rabbitmq.com/rabbitmq-server/ubuntu/jammy jammy main
EOF

apt-get update || exit 1
apt-get install -y erlang-base \
  erlang-asn1 erlang-crypto erlang-eldap erlang-ftp erlang-inets \
  erlang-mnesia erlang-os-mon erlang-parsetools erlang-public-key \
  erlang-runtime-tools erlang-snmp erlang-ssl \
  erlang-syntax-tools erlang-tftp erlang-tools erlang-xmerl || exit 1
apt-get install -y rabbitmq-server --fix-missing || exit 1

# Write configuration file BEFORE starting RabbitMQ to prevent boot failures
cat > /etc/rabbitmq/rabbitmq.conf << 'EOF'
vm_memory_high_watermark.relative = 0.7
disk_free_limit.absolute = 50MB
listeners.tcp.default = 5672
management.tcp.port = 15672
management.tcp.ip = 0.0.0.0
channel_max = 2048
queue_master_locator = min-masters
log.file.level = info
EOF

systemctl start rabbitmq-server || exit 1
systemctl enable rabbitmq-server || exit 1

mkdir -p /etc/systemd/system/rabbitmq-server.service.d
cat > /etc/systemd/system/rabbitmq-server.service.d/override.conf << 'EOF'
[Service]
LimitNOFILE=65536
LimitNPROC=65536
EOF

systemctl daemon-reload || exit 1
systemctl restart rabbitmq-server || exit 1
sleep 3

rabbitmq-plugins enable rabbitmq_management || exit 1
sleep 5
rabbitmq-plugins list | grep -q "rabbitmq_management" || exit 1

set +e
rabbitmqctl add_user "$RABBITMQ_USER" "$RABBITMQ_PASSWORD" 2>&1
ADD_RESULT=$?
set -e

if [ $ADD_RESULT -ne 0 ] && [ $ADD_RESULT -ne 70 ]; then
  echo "ERROR: Failed to add user"
  exit 1
fi

rabbitmqctl set_permissions -p / "$RABBITMQ_USER" ".*" ".*" ".*" || exit 1

# Tag karate user as management user so it can access the management plugin UI
rabbitmqctl set_user_tags "$RABBITMQ_USER" management administrator || exit 1

set +e
rabbitmqctl delete_user guest 2>&1
set -e

systemctl restart rabbitmq-server || exit 1
sleep 2

timeout 2 bash -c 'cat < /dev/null > /dev/tcp/127.0.0.1/5672' 2>/dev/null || exit 1
timeout 2 bash -c 'cat < /dev/null > /dev/tcp/127.0.0.1/15672' 2>/dev/null || exit 1

ATTEMPTS=0
while [ $ATTEMPTS -lt 60 ]; do
  ATTEMPTS=$((ATTEMPTS + 1))
  if rabbitmqctl status > /dev/null 2>&1 && rabbitmqctl list_queues > /dev/null 2>&1; then
    echo "✓ RabbitMQ ready (AMQP:5672, UI:15672, user:$RABBITMQ_USER)"
    echo "=== Initialization complete: $(date) ==="
    exit 0
  fi
  sleep 2
done

echo "ERROR: RabbitMQ health check timeout"
exit 1
