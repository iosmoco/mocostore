#!/bin/bash
set -euo pipefail

echo "Updating Sileo repo..."

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

REPO_DIR="repo"

# --------------------------------------------------
# 1. Validate packages and update depiction version
# --------------------------------------------------

python3 <<'PY'
from pathlib import Path
import json
import subprocess

repo = Path("repo")
debs = sorted((repo / "debs").glob("*.deb"))

if not debs:
    raise SystemExit("ERROR: No deb packages found")

def deb_field(path, field):
    result = subprocess.run(
        ["dpkg-deb", "-f", str(path), field],
        capture_output=True,
        text=True,
        check=True
    )
    return result.stdout.strip()

packages = {}

for deb in debs:
    package = deb_field(deb, "Package")
    version = deb_field(deb, "Version")
    depiction = deb_field(deb, "SileoDepiction")

    if not package or not version:
        raise SystemExit(f"ERROR: Invalid deb: {deb}")

    packages.setdefault(package, []).append(
        (version, depiction)
    )

# SiriScape: determine newest version using dpkg
siriscape = packages.get("com.moco.siriscape", [])

if siriscape:
    newest = siriscape[0][0]

    for version, _ in siriscape[1:]:
        result = subprocess.run(
            ["dpkg", "--compare-versions", version, "gt", newest]
        )
        if result.returncode == 0:
            newest = version

    path = repo / "depiction" / "siriscape.json"
    data = json.loads(path.read_text(encoding="utf-8"))

    updated = False

    for tab in data.get("tabs", []):
        if tab.get("tabname") != "詳細":
            continue

        for view in tab.get("views", []):
            if view.get("title") == "バージョン":
                if view.get("text") != newest:
                    view["text"] = newest
                    updated = True

    if updated:
        import re

        original = path.read_text(encoding="utf-8")

        pattern = (
            r'("title"\s*:\s*"バージョン"\s*,\s*'
            r'"text"\s*:\s*")[^"]*(")'
        )

        replacement_count = len(re.findall(pattern, original))

        if replacement_count != 1:
            raise SystemExit(
                "ERROR: Cannot safely locate SiriScape version field"
            )

        updated_text = re.sub(
            pattern,
            lambda match: match.group(1) + newest + match.group(2),
            original,
            count=1
        )

        path.write_text(updated_text, encoding="utf-8")
        print(f"Updated SiriScape depiction version: {newest}")
    else:
        print(f"SiriScape depiction version OK: {newest}")

print(f"Validated {len(debs)} deb packages")
PY

# --------------------------------------------------
# 2. Generate Packages
# --------------------------------------------------

(
  cd "$REPO_DIR"

  dpkg-scanpackages -m debs > Packages

  python3 <<'PY'
from pathlib import Path
import subprocess

packages_path = Path("Packages")
text = packages_path.read_text(encoding="utf-8")

entries = [e for e in text.strip().split("\n\n") if e.strip()]

def get_field(deb_path, field):
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
    ver = get_field(str(deb), "Version")
    sdep = get_field(str(deb), "SileoDepiction")

    if pkg and ver and sdep:
        sileo_map[(pkg, ver)] = sdep

new_entries = []

for entry in entries:
    lines = entry.splitlines()

    package_name = None
    version = None

    for line in lines:
        if line.startswith("Package: "):
            package_name = line.split(": ", 1)[1]
        elif line.startswith("Version: "):
            version = line.split(": ", 1)[1]

    lines = [
        line for line in lines
        if not line.lower().startswith("sileodepiction:")
    ]

    sdep = sileo_map.get((package_name, version))

    if sdep:
        insert_index = len(lines)

        for i, line in enumerate(lines):
            if line.startswith("Name: "):
                insert_index = i + 1
                break

        lines.insert(
            insert_index,
            f"SileoDepiction: {sdep}"
        )

    new_entries.append("\n".join(lines))

packages_path.write_text(
    "\n\n".join(new_entries) + "\n",
    encoding="utf-8"
)
PY

  # ------------------------------------------------
  # 3. Generate Packages.gz
  # ------------------------------------------------

  gzip -nkf Packages

  # ------------------------------------------------
  # 4. Generate Release
  # ------------------------------------------------

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

# --------------------------------------------------
# 5. Validate generated metadata
# --------------------------------------------------

python3 <<'PY'
from pathlib import Path
import gzip
import hashlib

repo = Path("repo")

packages = (repo / "Packages").read_bytes()
compressed = (repo / "Packages.gz").read_bytes()

if gzip.decompress(compressed) != packages:
    raise SystemExit("ERROR: Packages.gz mismatch")

release = (repo / "Release").read_text(encoding="utf-8")

sha = hashlib.sha256(packages).hexdigest()
sha_gz = hashlib.sha256(compressed).hexdigest()

if sha not in release or sha_gz not in release:
    raise SystemExit("ERROR: Release SHA256 mismatch")

print("Packages.gz verification: OK")
print("Release SHA256 verification: OK")
PY

# --------------------------------------------------
# 6. Stage public repository files only
# --------------------------------------------------

PUBLIC_PATHS=(
  repo/Packages
  repo/Packages.gz
  repo/Release
  repo/debs
  repo/depiction
  repo/images
  repo/CydiaIcon.png
  repo/README.md
  update_repo.sh
)

git add -- "${PUBLIC_PATHS[@]}"

# --------------------------------------------------
# 7. Commit and push
# --------------------------------------------------

if git diff --cached --quiet -- "${PUBLIC_PATHS[@]}"; then
  echo "No public file changes to commit."
else
  git commit -m "repo update" -- "${PUBLIC_PATHS[@]}"
fi

# Push only after the commit operation succeeds.
git push

echo "Repo updated!"
