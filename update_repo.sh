#!/bin/bash
set -euo pipefail

echo "Updating Sileo repo..."

# このスクリプト自身があるフォルダへ移動
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

REPO_DIR="repo"
DEBS_DIR="$REPO_DIR/debs"
DEPICTION_DIR="$REPO_DIR/depiction"
PACKAGES_FILE="$REPO_DIR/Packages"
JSON_OUT="$DEPICTION_DIR/moco.json"

# 自分のGitHub Pages URLに合わせる
BASE_URL="https://iosmoco.github.io/mocostore/repo"
ICON_URL="$BASE_URL/images/icon.png"

mkdir -p "$DEPICTION_DIR"

# deb があるか確認
shopt -s nullglob
DEB_FILES=("$DEBS_DIR"/*.deb)
shopt -u nullglob

if [ ${#DEB_FILES[@]} -eq 0 ]; then
  echo "Error: no .deb files found in $DEBS_DIR"
  exit 1
fi

# いちばん新しい deb を取得
LATEST_DEB="$(ls -t "$DEBS_DIR"/*.deb | head -n 1)"
echo "Using latest deb: $LATEST_DEB"

# control 情報を deb から取得
PACKAGE="$(dpkg-deb -f "$LATEST_DEB" Package 2>/dev/null || true)"
NAME="$(dpkg-deb -f "$LATEST_DEB" Name 2>/dev/null || true)"
VERSION="$(dpkg-deb -f "$LATEST_DEB" Version 2>/dev/null || true)"
DESCRIPTION="$(dpkg-deb -f "$LATEST_DEB" Description 2>/dev/null || true)"
AUTHOR="$(dpkg-deb -f "$LATEST_DEB" Author 2>/dev/null || true)"
SECTION="$(dpkg-deb -f "$LATEST_DEB" Section 2>/dev/null || true)"

# 空なら最低限のデフォルト
PACKAGE="${PACKAGE:-unknown-package}"
NAME="${NAME:-$PACKAGE}"
VERSION="${VERSION:-0.0.0}"
DESCRIPTION="${DESCRIPTION:-No description}"
AUTHOR="${AUTHOR:-moco}"
SECTION="${SECTION:-Tweaks}"

# SileoDepiction 用 JSON を自動生成
PACKAGE="$PACKAGE" \
NAME="$NAME" \
VERSION="$VERSION" \
DESCRIPTION="$DESCRIPTION" \
AUTHOR="$AUTHOR" \
SECTION="$SECTION" \
ICON_URL="$ICON_URL" \
JSON_OUT="$JSON_OUT" \
python3 <<'PY'
import os, json

package = os.environ["PACKAGE"]
name = os.environ["NAME"]
version = os.environ["VERSION"]
description = os.environ["DESCRIPTION"]
author = os.environ["AUTHOR"]
section = os.environ["SECTION"]
icon_url = os.environ["ICON_URL"]
json_out = os.environ["JSON_OUT"]

data = {
    "minVersion": "0.4",
    "class": "DepictionTabView",
    "headerImage": icon_url,
    "tintColor": "#6ec6d9",
    "tabs": [
        {
            "tabname": "詳細",
            "class": "DepictionStackView",
            "views": [
                {
                    "class": "DepictionHeaderView",
                    "title": name,
                    "useBoldText": True
                },
                {
                    "class": "DepictionMarkdownView",
                    "markdown": description
                },
                {
                    "class": "DepictionSpacerView",
                    "spacing": 16
                },
                {
                    "class": "DepictionImageView",
                    "URL": icon_url,
                    "width": 128,
                    "height": 128,
                    "cornerRadius": 24,
                    "alignment": 1
                },
                {
                    "class": "DepictionSpacerView",
                    "spacing": 16
                },
                {
                    "class": "DepictionMarkdownView",
                    "markdown": f"### パッケージ情報\\n- **Package**: {package}\\n- **Version**: {version}\\n- **Author**: {author}\\n- **Section**: {section}"
                }
            ]
        }
    ]
}

with open(json_out, "w", encoding="utf-8") as f:
    json.dump(data, f, ensure_ascii=False, indent=2)
    f.write("\n")
PY

echo "Generated: $JSON_OUT"

# Packages / Packages.gz 更新
dpkg-scanpackages -m "$DEBS_DIR" > "$PACKAGES_FILE"
gzip -kf "$PACKAGES_FILE"

# Git 反映
git add .

if git diff --cached --quiet; then
  echo "No changes to commit."
else
  git commit -m "repo update: $PACKAGE $VERSION"
  git push
fi

echo "Repo updated!"