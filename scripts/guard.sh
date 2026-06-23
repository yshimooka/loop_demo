#!/usr/bin/env bash
# PreToolUse フック：不可逆・禁止操作を決定論的にブロックする（exit 2 = deny）。
# モデルの判断に頼らず、プロンプトが何を言おうとここで止まる ＝ 権限ゲートの本体。
# 標準入力に tool 呼び出しの JSON が渡る。ここでは雑に文字列マッチで判定する（デモ用の出発点）。
input="$(cat)"
cmd="$(printf '%s' "$input" | tr -d '\n')"

deny() { echo "BLOCKED by guard.sh: $1" >&2; exit 2; }

case "$cmd" in
  *"git push"*)                                   deny "push 禁止（PRまで。mergeは人間）" ;;
  *"git merge"*)                                  deny "merge 禁止（人間が行う）" ;;
  *"npm install"*|*"npm add"*|*"pnpm add"*|*"yarn add"*) deny "依存追加 禁止（Node標準のみ）" ;;
  *"rm -rf"*|*"git clean"*)                       deny "削除系 禁止" ;;
esac
exit 0
