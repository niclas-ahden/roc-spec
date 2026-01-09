#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"

if [ -z "${DATABASE_URL:-}" ]; then
    echo "Error: DATABASE_URL must be set"
    echo "Example: DATABASE_URL=postgresql://user:pass@localhost:5432/roc_spec_test ./tests.sh"
    exit 1
fi

indent() {
    sed 's/^/    /'
}

# Use systemd scope when available (ensures all descendant processes are killed)
# Fall back to direct execution in CI where systemd user session isn't available
run_with_cleanup() {
    if systemctl --user show-environment &>/dev/null; then
        systemd-run --scope --user "$@"
    else
        "$@"
    fi
}

echo "=== Unit tests ==="
for unit_file in package/Assert.roc package/Format.roc; do
    roc test "$unit_file" 2>&1 | indent
    if [ "${PIPESTATUS[0]}" -ne 0 ]; then
        echo "FAILED: $unit_file"
        exit 1
    fi
done

echo ""
echo "=== Integration tests ==="
for test_file in tests/test_*.roc; do
    echo "Running $test_file..."

    run_with_cleanup roc dev --linker legacy "$test_file" 2>&1 | indent

    if [ "${PIPESTATUS[0]}" -ne 0 ]; then
        echo "FAILED: $test_file"
        exit 1
    fi
done

echo ""
echo "All tests passed."
