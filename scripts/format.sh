#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
python3 scripts/quality/format-swift.py --fix
ruff format scripts
ruff check --fix scripts
dotnet format server --no-restore
while IFS= read -r -d '' script; do
  shfmt -w -i 2 -ci "$script"
done < <(find scripts .githooks packaging -type f \( -name '*.sh' -o -name pre-commit -o -name journal-server \) -print0)
