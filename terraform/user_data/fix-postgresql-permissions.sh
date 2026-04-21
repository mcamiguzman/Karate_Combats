#!/bin/bash
# Emergency Permission Fix Script for PostgreSQL
# Use this if deployment already has permission denied errors
# Run on PostgreSQL instance via SSH: bash fix-postgresql-permissions.sh

set -e

# Read environment variables or use defaults
DB_NAME=${DB_NAME:-"combats"}
DB_USER=${DB_USER:-"admin"}

echo "========================================"
echo "PostgreSQL Permission Recovery Script"
echo "========================================"
echo "Database: $DB_NAME"
echo "User: $DB_USER"
echo ""

# Function to run SQL as postgres user
run_as_postgres() {
    sudo -u postgres psql -d "$DB_NAME" -c "$1"
}

echo "Step 1: Setting DEFAULT PRIVILEGES..."
run_as_postgres "
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO $DB_USER;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO $DB_USER;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON FUNCTIONS TO $DB_USER;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT USAGE ON TYPES TO $DB_USER;
"
echo "✓ Default privileges set"

echo ""
echo "Step 2: Granting permissions on all existing tables..."
run_as_postgres "
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO $DB_USER;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO $DB_USER;
GRANT USAGE ON ALL TYPES IN SCHEMA public TO $DB_USER;
"
echo "✓ All tables granted"

echo ""
echo "Step 3: Explicitly fixing known tables..."
run_as_postgres "
GRANT SELECT, INSERT, UPDATE, DELETE ON combats TO $DB_USER;
GRANT SELECT, INSERT, UPDATE, DELETE ON orders TO $DB_USER;
GRANT USAGE, SELECT ON SEQUENCE combats_id_seq TO $DB_USER;
GRANT USAGE, SELECT ON SEQUENCE orders_id_seq TO $DB_USER;
"
echo "✓ Known tables fixed"

echo ""
echo "Step 4: Verifying permissions..."

SELECT_TEST=$(sudo -u postgres psql -d "$DB_NAME" -U "$DB_USER" -c "SELECT COUNT(*) FROM combats;" 2>&1)
if [[ $SELECT_TEST == *"COUNT"* ]] || [[ $SELECT_TEST == *"0"* ]]; then
    echo "✓ SELECT permissions verified"
else
    echo "✗ SELECT permissions FAILED"
    echo "  Error: $SELECT_TEST"
fi

INSERT_TEST=$(sudo -u postgres psql -d "$DB_NAME" -U "$DB_USER" -c "INSERT INTO combats (time, participant_red, participant_blue, judges) VALUES ('verify', 'test', 'test', 'test') RETURNING id;" 2>&1)
if [[ $INSERT_TEST == *"1 row"* ]] || [[ $INSERT_TEST == *" 1"* ]]; then
    echo "✓ INSERT permissions verified"
    # Cleanup
    sudo -u postgres psql -d "$DB_NAME" -U "$DB_USER" -c "DELETE FROM combats WHERE time = 'verify';" 2>&1 > /dev/null
else
    echo "✗ INSERT permissions FAILED"
    echo "  Error: $INSERT_TEST"
fi

echo ""
echo "==============================================="
echo "Permission recovery complete!"
echo "You may need to restart the API service."
echo "  sudo systemctl restart karate-api"
echo "==============================================="
