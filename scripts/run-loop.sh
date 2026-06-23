#!/usr/bin/env bash
# =====================================================================
# Loop オーケストレータ（可視化＝このスクリプトのターミナル出力のみ）
#   ① worktree 作成（防護壁）→ ② fixer が修正 → ③ verifier が検証 → ④ push & PR
#
# MODE=agent : Claude Code（claude -p）の fixer / verifier に委任
#              claude は stream-json で動かし、各ステップを下のフォーマッタで実況表示
# MODE=sim   : claude 無し/オフライン用。決定論的に流れを通す
# 既定 auto（claude があれば agent、無ければ sim）
#
# STEP_DELAY=1 で各ステップに間を入れる（会場で読ませる用）。既定0。
# NO_PUSH=1 で push/PR をスキップ（ローカルのコミットだけにとどめる）。
# =====================================================================
set -uo pipefail
cd "$(dirname "$0")/.."

MODE="${MODE:-auto}"
if [ "$MODE" = "auto" ]; then
  if command -v claude >/dev/null 2>&1; then MODE="agent"; else MODE="sim"; fi
fi

c_orch=$'\033[36m'; c_fix=$'\033[33m'; c_ver=$'\033[32m'; c_dim=$'\033[2m'; c_off=$'\033[0m'

emit(){ # actor label [detail]
  local actor="$1" label="$2" detail="${3:-}" ts; ts="$(date +%H:%M:%S)"
  local col="$c_orch" who="ORCH  "
  case "$actor" in fixer) col="$c_fix"; who="FIX   ";; verifier) col="$c_ver"; who="VERIFY";; esac
  printf "${col}%s${c_off} ${c_dim}%s${c_off} %s\n" "$who" "$ts" "$label"
  if [ -n "$detail" ]; then printf "             ${c_dim}%s${c_off}\n" "$detail"; fi
  if [ "${STEP_DELAY:-0}" != "0" ]; then sleep "${STEP_DELAY}"; fi
  return 0
}

# claude の stream-json を、人が読める1行ずつに整形する（agentモード用）
FMT_NODE="$(cat <<'NODE'
const rl = require("readline").createInterface({ input: process.stdin });
const A = (process.argv[1] || "").padEnd(6);
const c = process.argv[2] || "";
const off = "\x1b[0m", dim = "\x1b[2m";
const clip = (s, n) => { n = n || 100; s = String(s == null ? "" : s).replace(/\s+/g, " ").trim(); return s.length > n ? s.slice(0, n) + "…" : s; };
const out = (m) => process.stdout.write(c + A + off + "   " + m + "\n");
const tool = (n, i) => {
  i = i || {};
  if (n === "Edit" || n === "Write") return n + " " + (i.file_path || "");
  if (n === "Read") return "Read " + (i.file_path || "");
  if (n === "Bash") return "Bash: " + clip(i.command, 80);
  if (n === "Task" || n === "Agent") return "delegate -> " + (i.subagent_type || "subagent") + ": " + clip(i.description || i.prompt, 60);
  if (n === "TodoWrite") return "Todo 更新";
  return n + " " + clip(JSON.stringify(i), 60);
};
rl.on("line", (raw) => {
  if (!raw.trim()) return;
  let o; try { o = JSON.parse(raw); } catch (e) { return; }
  const t = o.type || (o.event && o.event.type);
  const blocks = (o.message && o.message.content) || o.content || [];
  if (t === "assistant" || t === "message") {
    for (const b of blocks) {
      if (b.type === "text" && b.text && b.text.trim()) out("💬 " + clip(b.text));
      if (b.type === "tool_use") out("🔧 " + tool(b.name, b.input));
    }
  } else if (t === "user" || t === "tool_result") {
    for (const b of blocks) if (b.type === "tool_result") {
      const x = Array.isArray(b.content) ? b.content.map((y) => y.text || "").join(" ") : b.content;
      out((b.is_error ? "❌ " : "↩  ") + clip(x));
    }
  } else if (t === "result") {
    out("✓ " + clip(o.result || o.subtype || "done") + (o.total_cost_usd ? "  ($" + o.total_cost_usd + ")" : ""));
  }
});
NODE
)"
fmt(){ node -e "$FMT_NODE" "$1" "$2"; }

if ! git rev-parse --git-dir >/dev/null 2>&1; then
  echo "git 未初期化。setup-git.sh を実行します。"; bash scripts/setup-git.sh
fi
ROOT="$(git rev-parse --show-toplevel)"
TS="$(date +%Y%m%d-%H%M%S)"
BRANCH="fix/stock-status-${TS}"
WT="${ROOT}/../$(basename "$ROOT")-wt-${TS}"

echo "============================================== MODE=${MODE}"
emit orchestrator "① worktree を作成（防護壁）" "branch=${BRANCH}"
git worktree add -q "$WT" -b "$BRANCH"
emit orchestrator "main を汚さない隔離作業場を用意" "$WT"

escalate(){
  emit orchestrator "停止条件：ロールバック / エスカレーション" "$1"
  git worktree remove --force "$WT" >/dev/null 2>&1 || true
  git branch -D "$BRANCH" >/dev/null 2>&1 || true
  emit orchestrator "worktree を破棄しブランチを巻き戻した（mainは無傷）" ""
  exit 1
}

emit fixer "② fixer 起動（別コンテキスト / worktree内 / model: sonnet）" "作る役。思考は親に渡らない"
if [ "$MODE" = "agent" ]; then
  ( cd "$WT" && claude -p \
      "CLAUDE.md と goal.md を読んで。CIが赤。fixer サブエージェントで受入基準を全部満たすよう直して。npm run check が緑になったらコミットだけ。push も merge もしない。" \
      --permission-mode acceptEdits \
      --allowedTools "Bash(npm run *)" "Bash(npm test *)" "Bash(node *)" "Bash(git add *)" "Bash(git commit *)" \
      --model sonnet --max-turns 20 --max-budget-usd 2 \
      --output-format stream-json --verbose ) | fmt "FIX" "$c_fix"
  [ "${PIPESTATUS[0]}" -ne 0 ] && escalate "fixer が完了できなかった"
else
  emit fixer "Read CLAUDE.md / goal.md" "受入基準 AC1-3 と禁止事項を把握"
  emit fixer "Bash: npm test" "赤を確認（在庫0 → sold_out が fail）"
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
  emit fixer "Edit src/stock.js" "しきい値を <= 0 に（AC2/AC3 を満たす）"
  if ( cd "$WT" && npm run --silent check >/tmp/fix_check 2>&1 ); then
    emit fixer "Bash: npm run check → 緑" "lint / test / verify すべて pass"
  else
    escalate "fixer の修正後も check が緑にならない"
  fi
  emit fixer "コミットのみ作成（push/merge はしない）" "done を宣言"
fi

emit orchestrator "fixer の結果だけ受け取る（思考は破棄）" "→ 検査役へ"
emit verifier "③ verifier 起動（別コンテキスト / 読み取り専用）" "検査役。コードは編集できない"
if [ "$MODE" = "agent" ]; then
  ( cd "$WT" && claude -p \
      "verifier サブエージェントで goal.md の AC を採点して。各ACの根拠を述べ、最後に 'VERDICT: pass' か 'VERDICT: fail' を1行で。" \
      --allowedTools "Read" "Grep" "Glob" "Bash(npm run *)" "Bash(npm test *)" "Bash(node *)" \
      --max-turns 15 --max-budget-usd 1 \
      --output-format stream-json --verbose ) | fmt "VERIFY" "$c_ver" | tee /tmp/loop_vout
  [ "${PIPESTATUS[0]}" -ne 0 ] && escalate "verifier が完了できなかった"
  grep -q "VERDICT: pass" /tmp/loop_vout || escalate "検査役が不合格と判定（AC未達 or テスト不足）"
else
  emit verifier "Read goal.md（受入基準を取得）" ""
  ( cd "$WT" && npm run --silent verify >/tmp/verify_out 2>&1 ) || true
  emit verifier "Bash: npm run verify" "AC1 pass / AC2 pass / AC3 pass"
  emit verifier "テスト網羅性チェック" "AC3（在庫マイナス）の観点あり → ok"
  emit verifier "VERDICT: pass" "lint / test / verify すべて緑"
fi

emit orchestrator "④ 検証合格 → コミット → push → PR（merge は人間）" ""
( cd "$WT" && git add -A && git commit -q -m "fix: 在庫0・マイナスを売り切れ判定に修正（AC2/AC3）" ) || echo "（fixer が既にコミット済み）"
git worktree remove "$WT"
emit orchestrator "worktree 撤収（ブランチ ${BRANCH} は保持）" ""

# push と PR 作成（オーケストレータが実行。エージェントには push/merge を拒否したまま）
if [ "${NO_PUSH:-0}" = "1" ]; then
  emit orchestrator "push/PR はスキップ（NO_PUSH=1）" "手動: git push -u origin ${BRANCH} && gh pr create --fill --base main"
elif ! git remote get-url origin >/dev/null 2>&1; then
  emit orchestrator "origin 未設定のため push/PR をスキップ" "git remote add origin <URL> 後に再実行、または手動で実行"
elif git push -q -u origin "$BRANCH"; then
  emit orchestrator "git push 完了（origin/${BRANCH}）" ""
  if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
    if PRURL="$(gh pr create --fill --base main --head "$BRANCH" 2>/dev/null)"; then
      emit orchestrator "PR を作成（merge は人間が判断）" "$PRURL"
    else
      emit orchestrator "PR 作成に失敗。手動で作成を" "gh pr create --fill --base main --head ${BRANCH}"
    fi
  else
    emit orchestrator "gh 未認証のため PR は手動で" "gh auth login 後: gh pr create --fill --base main --head ${BRANCH}"
  fi
else
  emit orchestrator "push 失敗。リモート設定を確認" "git push -u origin ${BRANCH}"
fi

echo "=============================================="
