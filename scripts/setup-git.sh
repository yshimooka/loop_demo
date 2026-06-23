#!/usr/bin/env bash
# worktree を使うには git リポジトリが必要。最初の1回だけ実行する。
set -euo pipefail
cd "$(dirname "$0")/.."

if git rev-parse --git-dir >/dev/null 2>&1; then
  echo "既に git リポジトリです。"
  exit 0
fi

git init -b main >/dev/null
# コミット用の最小 identity（未設定の環境でも動くように）
git config user.email  >/dev/null 2>&1 || git config user.email "demo@example.com"
git config user.name   >/dev/null 2>&1 || git config user.name  "Loop Demo"
git add -A
git commit -q -m "chore: 初期状態（在庫判定にバグあり / CIが赤）"
echo "git リポジトリを初期化しました（初期コミット = バグ状態）。"
