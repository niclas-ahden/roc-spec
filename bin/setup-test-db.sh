#!/usr/bin/env bash
set -euo pipefail

if [ -z "${DATABASE_URL:-}" ]; then
    echo "Error: DATABASE_URL must be set"
    echo "Example: DATABASE_URL=postgresql://user:pass@localhost:5432/roc_spec_test ./bin/setup-test-db.sh"
    exit 1
fi

# Parse DATABASE_URL to extract components
# Format: postgresql://user[:pass]@host:port/dbname
db_name="${DATABASE_URL##*/}"
base_url="${DATABASE_URL%/*}"

echo "Creating database '$db_name' if it doesn't exist..."
if psql "$base_url/postgres" -tc "SELECT 1 FROM pg_database WHERE datname = '$db_name'" | grep -q 1; then
    echo "Database '$db_name' already exists."
else
    psql "$base_url/postgres" -c "CREATE DATABASE \"$db_name\""
    echo "Database '$db_name' created."
fi
