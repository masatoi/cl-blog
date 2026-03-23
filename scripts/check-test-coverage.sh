#!/bin/bash
# Check that all test files are registered in cl-blog.asd
# This script should be run in CI to detect orphaned test files.

set -e

cd "$(dirname "$0")/.."

echo "Checking test file coverage in cl-blog.asd..."

# Find all .lisp files in tests/ and convert to system names
# e.g., tests/db/users.lisp -> cl-blog/tests/db/users
ACTUAL_FILES=$(find tests -name "*.lisp" -type f | \
    sed 's|^tests/|cl-blog/tests/|; s|\.lisp$||' | \
    sort)

# Extract system names from cl-blog.asd depends-on
# Look for strings matching "cl-blog/tests/..."
REGISTERED=$(grep -oE '"cl-blog/tests/[^"]*"' cl-blog.asd | \
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
    filepath=$(echo "$reg" | sed 's|^cl-blog/||').lisp
    if [ ! -f "$filepath" ]; then
        STALE="$STALE$reg\n"
    fi
done

EXIT_CODE=0

if [ -n "$MISSING" ]; then
    echo ""
    echo "ERROR: Test files not registered in cl-blog.asd:"
    echo -e "$MISSING" | grep -v '^$' | while read -r f; do
        echo "  - $f"
    done
    echo ""
    echo "Add these to the :depends-on list in cl-blog.asd"
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
