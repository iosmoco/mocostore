#!/bin/bash
set -euo pipefail

echo "Updating Sileo repo..."

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

REPO_DIR="repo"

(
  cd "$REPO_DIR"

  dpkg-scanpackages -m debs > Packages

  python3 <<'PY'
from pathlib import Path
import subprocess

packages_path = Path("Packages")
text = packages_path.read_text(encoding="utf-8")

entries = [e for e in text.strip().split("\n\n") if e.strip()]

def get_field(deb_path: str, field: str) -> str:
    result = subprocess.run(
        ["dpkg-deb", "-f", deb_path, field],
        capture_output=True,
        text=True
    )
    if result.returncode != 0:
        return ""
    return result.stdout.strip()

sileo_map = {}
for deb in sorted(Path("debs").glob("*.deb")):
    pkg = get_field(str(deb), "Package")
    sdep = get_field(str(deb), "SileoDepiction")
    if pkg and sdep:
        sileo_map[pkg] = sdep

new_entries = []

for entry in entries:
    lines = entry.splitlines()
    package_name = None

    for line in lines:
        if line.startswith("Package: "):
            package_name = line.split(": ", 1)[1]
            break

    lines = [
        line for line in lines
        if not line.startswith("Sileodepiction:")
        and not line.startswith("SileoDepiction:")
    ]

    if package_name and package_name in sileo_map:
        insert_index = len(lines)
        for i, line in enumerate(lines):
            if line.startswith("Name: "):
                insert_index = i + 1
                break
        lines.insert(insert_index, f"SileoDepiction: {sileo_map[package_name]}")

    new_entries.append("\n".join(lines))

packages_path.write_text("\n\n".join(new_entries) + "\n", encoding="utf-8")
PY

  gzip -kf Packages

  PKG_SIZE=$(wc -c < Packages | tr -d ' ')
  PKG_GZ_SIZE=$(wc -c < Packages.gz | tr -d ' ')
  PKG_MD5=$(md5 -q Packages)
  PKG_GZ_MD5=$(md5 -q Packages.gz)
  PKG_SHA256=$(shasum -a 256 Packages | awk '{print $1}')
  PKG_GZ_SHA256=$(shasum -a 256 Packages.gz | awk '{print $1}')

  cat > Release <<EOF
Origin: iosmoco
Label: iosmoco
Suite: stable
Version: 1.0
Codename: iosmoco
Architecture: iphoneos-arm64
Components: main
Description: iosmoco repository
MD5Sum:
 $PKG_MD5 $PKG_SIZE Packages
 $PKG_GZ_MD5 $PKG_GZ_SIZE Packages.gz
SHA256:
 $PKG_SHA256 $PKG_SIZE Packages
 $PKG_GZ_SHA256 $PKG_GZ_SIZE Packages.gz
EOF
)

git add .

if git diff --cached --quiet; then
  echo "No changes to commit."
else
  git commit -m "repo update"
  git push
fi

echo "Repo updated!"