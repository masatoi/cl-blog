#!/bin/bash
# Check that all test files are registered in recurya.asd
# This script should be run in CI to detect orphaned test files.

set -e

cd "$(dirname "$0")/.."

echo "Checking test file coverage in recurya.asd..."

# Find all .lisp files in tests/ and convert to system names
# e.g., tests/db/users.lisp -> recurya/tests/db/users
ACTUAL_FILES=$(find tests -name "*.lisp" -type f | \
    sed 's|^tests/|recurya/tests/|; s|\.lisp$||' | \
    sort)

# Extract system names from recurya.asd depends-on
# Look for strings matching "recurya/tests/..."
REGISTERED=$(grep -oE '"recurya/tests/[^"]*"' recurya.asd | \
    tr -d '"' | \
    sort)

# Find files not in registered list
MISSING=""
for file in $ACTUAL_FILES; do
    if ! echo "$REGISTERED" | grep -qx "$file"; then
        MISSING="$MISSING$file\n"
    fi
done

# Find registered entries that don't have corresponding files
STALE=""
for reg in $REGISTERED; do
    # Convert system name back to file path
    filepath=$(echo "$reg" | sed 's|^recurya/||').lisp
    if [ ! -f "$filepath" ]; then
        STALE="$STALE$reg\n"
    fi
done

EXIT_CODE=0

if [ -n "$MISSING" ]; then
    echo ""
    echo "ERROR: Test files not registered in recurya.asd:"
    echo -e "$MISSING" | grep -v '^$' | while read -r f; do
        echo "  - $f"
    done
    echo ""
    echo "Add these to the :depends-on list in recurya.asd"
    EXIT_CODE=1
fi

if [ -n "$STALE" ]; then
    echo ""
    echo "WARNING: Registered systems with no corresponding file:"
    echo -e "$STALE" | grep -v '^$' | while read -r f; do
        echo "  - $f"
    done
    EXIT_CODE=1
fi

if [ $EXIT_CODE -eq 0 ]; then
    echo "All $(echo "$ACTUAL_FILES" | wc -l) test files are registered."
fi

exit $EXIT_CODE
