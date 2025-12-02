#!/bin/bash

# Git Pre-Commit Hook for swift-format
# Install with: ln -s ../../scripts/pre-commit-hook.sh .git/hooks/pre-commit

# Check if swift-format is installed
if ! command -v swift-format &> /dev/null; then
    echo "Error: swift-format not installed. Install with: brew install swift-format"
    exit 1
fi

# Get list of staged Swift files
STAGED_SWIFT_FILES=$(git diff --cached --name-only --diff-filter=ACM | grep "\.swift$")

if [ -z "$STAGED_SWIFT_FILES" ]; then
    # No Swift files staged, nothing to do
    exit 0
fi

echo "Formatting staged Swift files..."

# Format each staged file
for FILE in $STAGED_SWIFT_FILES; do
    if [ -f "$FILE" ]; then
        echo "  Formatting: $FILE"
        swift-format format --in-place "$FILE"
        git add "$FILE"
    fi
done

echo "✓ Swift files formatted successfully"
exit 0
