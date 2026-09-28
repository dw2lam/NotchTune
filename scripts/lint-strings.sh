#!/bin/zsh
# Validates all .strings files with plutil to catch syntax errors
# (unescaped quotes, bad Unicode, missing semicolons, etc.) early.

set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
failed=0

while IFS= read -r file; do
    if ! plutil -lint "$file" >/dev/null 2>&1; then
        echo "FAIL: $file"
        plutil -lint "$file" 2>&1 | sed 's/^/  /'
        failed=1
    fi
done < <(find "$repo_root/Sources" -name '*.strings' -type f)

if (( failed )); then
    echo ""
    echo "Localizable.strings validation failed. Common causes:"
    echo "  - Unescaped double quotes inside values (use \\\" instead)"
    echo "  - Missing semicolons at end of lines"
    echo "  - Unescaped backslashes or special characters"
    exit 1
fi

echo "All .strings files passed validation."
