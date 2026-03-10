#!/bin/bash
set -euo pipefail

echo "Updating Sileo repo..."

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

REPO_DIR="repo"

(
  cd "$REPO_DIR"
  dpkg-scanpackages -m debs > Packages
  gzip -kf Packages
  sed -i '' 's/^Sileodepiction:/SileoDepiction:/g' Packages
  gzip -kf Packages
)

git add .

if git diff --cached --quiet; then
  echo "No changes to commit."
else
  git commit -m "repo update"
  git push
fi

echo "Repo updated!"