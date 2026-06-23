#!/usr/bin/env bash
# =====================================================================
# Loop オーケストレータ
#   ① worktree を作る（防護壁＝他作業と隔離）
#   ② その中で fixer サブエージェントが修正
#   ③ verifier サブエージェントが goal.md に照らして検証
#   ④ 合格なら PR / 不合格なら停止条件（ロールバック・エスカレーション）
#
# MODE=agent : Claude Code（claude -p）の fixer / verifier に任せる
# MODE=sim   : claude 無し/オフライン用。修正と検証を決定論的に回して流れを通す
# 既定は auto（claude があれば agent、無ければ sim）
# =====================================================================
set -euo pipefail
cd "$(dirname "$0")/.."

MODE="${MODE:-auto}"
if [ "$MODE" = "auto" ]; then
  if command -v claude >/dev/null 2>&1; then MODE="agent"; else MODE="sim"; fi
fi

# --- git 準備（worktree には git が要る） ---
if ! git rev-parse --git-dir >/dev/null 2>&1; then
  echo "git 未初期化。setup-git.sh を実行します。"
  bash scripts/setup-git.sh
fi

ROOT="$(git rev-parse --show-toplevel)"
TS="$(date +%Y%m%d-%H%M%S)"
BRANCH="fix/stock-status-${TS}"
WT="${ROOT}/../$(basename "$ROOT")-wt-${TS}"

echo "=============================================="
echo " MODE=${MODE}"
echo "① worktree を作成（防護壁）"
echo "    branch=${BRANCH}"
echo "    path=${WT}"
git worktree add -q "$WT" -b "$BRANCH"
echo "    → main を汚さず、隔離された作業場を用意した"

escalate() {
  echo "‼️  停止条件：エスカレーション / ロールバック"
  echo "    $1"
  git worktree remove --force "$WT" >/dev/null 2>&1 || true
  git branch -D "$BRANCH" >/dev/null 2>&1 || true
  echo "    → worktree を破棄し、ブランチも巻き戻した（mainは無傷）"
  exit 1
}

echo
echo "② fixer サブエージェントが修正（worktree 内）"
if [ "$MODE" = "agent" ]; then
  # 編集系を事前許可（サブエージェントは対話許可に答えられないため）。
  # 予算/ターン上限 = goal.md の停止条件。push/merge は guard.sh が拒否。
  ( cd "$WT" && claude -p \
      "CLAUDE.md と goal.md を読んで。CIが赤。fixer サブエージェントを使い、goal.md の受入基準を全部満たすように直して。npm run check が緑になったらコミットだけ作る。push も merge もしない。" \
      --permission-mode acceptEdits \
      --model sonnet \
      --max-turns 20 \
      --max-budget-usd 2 ) || escalate "fixer が完了できなかった"
else
  # SIM: 「エージェントが正しく直した」状態を決定論的に再現
  cat > "$WT/src/stock.js" <<'EOF'
// 在庫数から販売ステータスを返す。
// "in_stock"（販売可能） / "sold_out"（売り切れ）の2値。

const STATUS = {
  IN_STOCK: 'in_stock',
  SOLD_OUT: 'sold_out',
};

/**
 * @param {number} quantity 在庫数（マイナス = 返品処理中などで実在庫なし）
 * @returns {'in_stock' | 'sold_out'}
 */
export function getStockStatus(quantity) {
  if (quantity <= 0) {
    return STATUS.SOLD_OUT;
  }
  return STATUS.IN_STOCK;
}
EOF
  echo "    [sim] src/stock.js を修正（<= 0 で sold_out）"
fi

echo
echo "③ verifier サブエージェントが検証（goal.md に照らす / 読み取り専用）"
if [ "$MODE" = "agent" ]; then
  VOUT="$( cd "$WT" && claude -p \
      "verifier サブエージェントで、goal.md の AC を採点して。最後に 'VERDICT: pass' か 'VERDICT: fail' を必ず1行で出力。" \
      --allowedTools "Read" "Grep" "Glob" "Bash(npm run *)" "Bash(npm test *)" "Bash(node *)" \
      --max-turns 15 \
      --max-budget-usd 1 )" || escalate "verifier が完了できなかった"
  echo "$VOUT"
  echo "$VOUT" | grep -q "VERDICT: pass" || escalate "検査役が不合格と判定（AC未達 or テスト不足）"
else
  # SIM: 決定論ゲート（lint && test && verify）
  if ( cd "$WT" && npm run --silent check >/tmp/verify_out 2>&1 ); then
    echo "    [sim] VERDICT: pass（lint / test / verify すべて緑）"
  else
    echo "----- verify 出力 -----"; cat /tmp/verify_out | grep -E "not ok|# (pass|fail)" || true
    escalate "検査役が不合格（上の AC を満たしていない）"
  fi
fi

echo
echo "④ 合格 → コミットして PR（merge は人間）"
( cd "$WT" \
  && git add -A \
  && git commit -q -m "fix: 在庫0・マイナスを売り切れ判定に修正（AC2/AC3）" )
echo "    コミット作成: ${BRANCH}"

# worktree は使い捨て。ブランチは残るので、撤収してから PR を作る。
git worktree remove "$WT"
echo "    worktree を撤収（ブランチ ${BRANCH} は保持）"

if command -v gh >/dev/null 2>&1; then
  git push -q -u origin "$BRANCH" && gh pr create --fill --head "$BRANCH" \
    || echo "    （push/PR はリモート設定が必要。下記を手動で実行）"
fi
echo
echo "次の一手（merge は人間が判断）:"
echo "    git push -u origin ${BRANCH}"
echo "    gh pr create --fill"
echo "=============================================="
