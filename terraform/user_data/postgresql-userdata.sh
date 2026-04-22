#!/bin/bash
set -e

# PostgreSQL Server User Data Script
echo "Starting PostgreSQL Server initialization..."

# Update system packages
apt-get update
apt-get upgrade -y

# Install PostgreSQL
apt-get install -y \
    postgresql \
    postgresql-contrib \
    postgresql-client \
    postgresql-client-common \
    build-essential \
    libpq-dev

echo "Installed PostgreSQL"

# Make sure PostgreSQL service is running
systemctl start postgresql
systemctl enable postgresql

# Create database and user
sudo -u postgres psql << SQL
-- Create database
CREATE DATABASE ${DB_NAME};

-- Create user with password
CREATE USER ${DB_USER} WITH PASSWORD '${DB_PASSWORD}';

-- Grant privileges
ALTER ROLE ${DB_USER} SET client_encoding TO 'utf8';
ALTER ROLE ${DB_USER} SET default_transaction_isolation TO 'read committed';
ALTER ROLE ${DB_USER} SET default_transaction_deferrable TO on;
ALTER ROLE ${DB_USER} SET default_transaction_read_only TO off;

-- Grant all privileges on the database
GRANT ALL PRIVILEGES ON DATABASE ${DB_NAME} TO ${DB_USER};

-- Connect to the database and grant schema privileges
\connect ${DB_NAME}
GRANT ALL PRIVILEGES ON SCHEMA public TO ${DB_USER};

-- Set DEFAULT PRIVILEGES - CRITICAL FIX for permission denied errors
-- These ensure that tables created by postgres user get automatic permissions for app user
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO ${DB_USER};
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO ${DB_USER};
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON FUNCTIONS TO ${DB_USER};
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT USAGE ON TYPES TO ${DB_USER};

-- Grant CREATE privilege on schema to allow future objects
GRANT CREATE ON SCHEMA public TO ${DB_USER};
SQL

echo "Created database and user"
echo "Set default privileges for future object creation"

# Configure PostgreSQL to accept connections from other servers
# Backup and update pg_hba.conf for all PostgreSQL versions
for PG_HBA in /etc/postgresql/*/main/pg_hba.conf; do
    if [ -f "$PG_HBA" ]; then
        # Backup original file
        cp "$PG_HBA" "$PG_HBA.backup"
        
        # Remove any existing VPC allow rules to avoid duplicates
        sed -i "/10.0.0.0\/16/d" "$PG_HBA"
        
        # Add new connection rules for the VPC
        cat >> "$PG_HBA" << RULES_EOF

# Allow connections from API and Worker servers in the VPC
host    ${DB_NAME}    ${DB_USER}    10.0.0.0/16    md5
host    all           all           10.0.0.0/16    md5
RULES_EOF
        echo "Updated: $PG_HBA"
    fi
done

# Configure PostgreSQL to accept password-based authentication on LOCAL (socket) connections
# This allows users to connect via psql on the same machine using password authentication
for PG_HBA in /etc/postgresql/*/main/pg_hba.conf; do
    if [ -f "$PG_HBA" ]; then
        # Remove any existing LOCAL rules for the application user to avoid duplicates
        sed -i "/^local.*${DB_USER}/d" "$PG_HBA"
        
        # Add LOCAL authentication rules for password-based (md5) authentication on socket connections
        # These must come before the "local all all" rule for proper matching
        cat >> "$PG_HBA" << LOCAL_RULES_EOF

# Allow password-based authentication on LOCAL socket connections for application user
local   ${DB_NAME}    ${DB_USER}    md5
local   all           all          md5
LOCAL_RULES_EOF
        echo "Updated LOCAL rules in: $PG_HBA"
    fi
done

# Update postgresql.conf to listen on all network interfaces
# Find all postgresql.conf files and update them
for POSTGRES_CONF in /etc/postgresql/*/main/postgresql.conf; do
    if [ -f "$POSTGRES_CONF" ]; then
        # Handle both commented and uncommented listen_addresses lines
        if grep -q "^#listen_addresses" "$POSTGRES_CONF"; then
            # If commented out, uncomment and update
            sed -i "s/^#listen_addresses = .*/listen_addresses = '*'/g" "$POSTGRES_CONF"
        elif grep -q "^listen_addresses" "$POSTGRES_CONF"; then
            # If already uncommented, just update the value
            sed -i "s/^listen_addresses = .*/listen_addresses = '*'/g" "$POSTGRES_CONF"
        else
            # If not found, add it
            echo "listen_addresses = '*'" >> "$POSTGRES_CONF"
        fi
        echo "Updated: $POSTGRES_CONF"
    fi
done

echo "Configured PostgreSQL for network access"

# Restart PostgreSQL to apply configuration
systemctl restart postgresql

# Wait for PostgreSQL to be ready
echo "Waiting for PostgreSQL to be ready..."
for i in {1..30}; do
    if sudo -u postgres psql -c "SELECT 1" > /dev/null 2>&1; then
        echo "✓ PostgreSQL is ready"
        break
    fi
    echo "  Attempting... ($i/30)"
    sleep 2
done

# Initialize database schema
# This script will download and run the init.sql from the repository
SCHEMA_DIR="/tmp"
DB_INIT_SQL="/tmp/init.sql"

# Create the init.sql with the schema
cat > $DB_INIT_SQL << 'SCHEMA_EOF'
CREATE TABLE IF NOT EXISTS combats (
    id SERIAL PRIMARY KEY,
    time VARCHAR(50),
    participant_red VARCHAR(100),
    participant_blue VARCHAR(100),
    points_red INT,
    points_blue INT,
    fouls_red INT,
    fouls_blue INT,
    judges TEXT,
    status VARCHAR(20),
    date TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_combats_status ON combats(status);
CREATE INDEX IF NOT EXISTS idx_combats_date ON combats(date);

-- Optionally create the Orders table if mentioned in requirements
CREATE TABLE IF NOT EXISTS orders (
    id SERIAL PRIMARY KEY,
    combat_id INT REFERENCES combats(id),
    consumer_id VARCHAR(100),
    action VARCHAR(50),
    status VARCHAR(20),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_orders_combat_id ON orders(combat_id);
CREATE INDEX IF NOT EXISTS idx_orders_status ON orders(status);
SCHEMA_EOF

# Run the schema initialization
sudo -u postgres psql ${DB_NAME} < $DB_INIT_SQL

echo "Initialized database schema"

# CRITICAL FIX: Grant ALL privileges on all existing tables and sequences to application user
# This handles tables that may have been created before DEFAULT PRIVILEGES were set
sudo -u postgres psql ${DB_NAME} << GRANT_SQL
-- Grant all table and sequence permissions to the application user
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO ${DB_USER};
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO ${DB_USER};

-- Ensure user can execute functions
GRANT USAGE ON ALL TYPES IN SCHEMA public TO ${DB_USER};

-- Explicitly handle combats and orders tables (in case they exist from previous runs)
GRANT SELECT, INSERT, UPDATE, DELETE ON combats TO ${DB_USER};
GRANT SELECT, INSERT, UPDATE, DELETE ON orders TO ${DB_USER};
GRANT USAGE, SELECT ON SEQUENCE combats_id_seq TO ${DB_USER};
GRANT USAGE, SELECT ON SEQUENCE orders_id_seq TO ${DB_USER};

-- Verify that permissions are set correctly
SELECT 'Permissions set for table combats' AS status, has_table_privilege('${DB_USER}', 'combats', 'SELECT') AS can_select, has_table_privilege('${DB_USER}', 'combats', 'INSERT') AS can_insert;
SELECT 'Permissions set for table orders' AS status, has_table_privilege('${DB_USER}', 'orders', 'SELECT') AS can_select, has_table_privilege('${DB_USER}', 'orders', 'INSERT') AS can_insert;
GRANT_SQL

echo "Fixed permissions on all tables and sequences"

# Verify the schema was created
sudo -u postgres psql ${DB_NAME} -c "\dt"

echo "Running permission verification tests..."

# Test 1: Verify application user can SELECT from combats
echo "Test 1: SELECT permission on combats..."
PSQL_SELECT_RESULT=$(sudo -u postgres psql ${DB_NAME} -U ${DB_USER} -c "SELECT COUNT(*) FROM combats;" 2>&1)
if [[ $PSQL_SELECT_RESULT == *"(1 row)"* ]] || [[ $PSQL_SELECT_RESULT == *"0"* ]]; then
    echo "✓ SELECT permission PASSED - Application user can read combats table"
else
    echo "✗ SELECT permission FAILED - Error: $PSQL_SELECT_RESULT"
fi

# Test 2: Verify application user can INSERT into combats
echo "Test 2: INSERT permission on combats..."
PSQL_INSERT_RESULT=$(sudo -u postgres psql ${DB_NAME} -U ${DB_USER} -c "INSERT INTO combats (time, participant_red, participant_blue, judges) VALUES ('test-time', 'test-red', 'test-blue', 'test-judge') RETURNING id;" 2>&1)
if [[ $PSQL_INSERT_RESULT == *"1 row"* ]] || [[ $PSQL_INSERT_RESULT == *" 1"* ]]; then
    echo "✓ INSERT permission PASSED - Application user can write to combats table"
    # Clean up test data
    sudo -u postgres psql ${DB_NAME} -U ${DB_USER} -c "DELETE FROM combats WHERE time = 'test-time';" 2>&1 > /dev/null
else
    echo "✗ INSERT permission FAILED - Error: $PSQL_INSERT_RESULT"
fi

# Test 3: Verify application user can SELECT from orders
echo "Test 3: SELECT permission on orders..."
PSQL_ORDERS=$(sudo -u postgres psql ${DB_NAME} -U ${DB_USER} -c "SELECT COUNT(*) FROM orders;" 2>&1)
if [[ $PSQL_ORDERS == *"(1 row)"* ]] || [[ $PSQL_ORDERS == *"0"* ]]; then
    echo "✓ SELECT permission PASSED - Application user can read orders table"
else
    echo "✗ SELECT permission FAILED - Error: $PSQL_ORDERS"
fi

echo "Permission verification complete!"
echo ""
mkdir -p /var/backups/postgresql
chown postgres:postgres /var/backups/postgresql
chmod 700 /var/backups/postgresql

echo "Created backup directory"

# Check PostgreSQL status
sudo -u postgres psql --version

echo "PostgreSQL Server initialization complete!"
echo "Database: ${DB_NAME}"
echo "User: ${DB_USER}"
echo "Wait 30-60 seconds for full initialization before connecting."
