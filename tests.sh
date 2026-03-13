#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"

# Parse arguments
FAIL_FAST=false
for arg in "$@"; do
    case $arg in
        --fail-fast)
            FAIL_FAST=true
            export ROC_SPEC_FAIL_FAST=1
            ;;
    esac
done

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
echo "=== Building server fixtures ==="
for server_file in tests/server_fixtures/*.roc; do
    binary="${server_file%.roc}"
    echo "Building $server_file..."
    roc build --linker legacy "$server_file" --output "$binary" 2>&1 | indent
    if [ "${PIPESTATUS[0]}" -ne 0 ]; then
        echo "FAILED to build: $server_file"
        exit 1
    fi
done

FAILED_TESTS=()

echo ""
echo "=== Integration tests ==="
for test_file in tests/test_*.roc; do
    echo "Running $test_file..."

    if ! run_with_cleanup roc dev --linker legacy "$test_file" 2>&1 | indent; then
        echo "FAILED: $test_file"
        FAILED_TESTS+=("$test_file")
        if $FAIL_FAST; then
            echo "Stopping due to --fail-fast"
            exit 1
        fi
    fi
done

echo ""
if [ ${#FAILED_TESTS[@]} -eq 0 ]; then
    echo "All tests passed."
else
    echo "Failed tests:"
    for t in "${FAILED_TESTS[@]}"; do
        echo "  - $t"
    done
    exit 1
fi
