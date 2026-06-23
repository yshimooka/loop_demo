# Loop デモ — worktree内でサブエージェントが直し、別エージェントが検証

講義「AIコーディングの考え方 2026」のライブデモ用、最小リポジトリです。
**依存パッケージはゼロ。Node と git だけで動きます**（`npm install` 不要）。

題材は在庫ステータス判定。`src/stock.js` にバグがあり CI が赤の状態から、
スライド通り「**worktree（防護壁）の中で fixer サブエージェントが修正 → 別の
verifier サブエージェントが検証 → 合格なら PR（merge は人間）**」を回します。

## 必要なもの
- Node.js 18 以上 / git
- 任意：Claude Code（`claude`）… 実際にエージェントに任せる場合
- push / PR 作成まで行う場合：`origin` リモートが設定済み＋GitHub CLI（`gh`）が認証済み
  （未設定なら push/PR は自動でスキップし、手動コマンドを表示します）

## ファイル構成
```
loop-demo/
├─ CLAUDE.md                  文脈（規約・見るべきファイル・過去の罠・作業の流れ）
├─ goal.md                    目標契約：受入基準(AC)・停止条件・権限ゲート
├─ src/stock.js               実装（バグあり = CIが赤）
├─ test/stock.test.js         単体テスト ＝ CIゲート（npm test）
├─ test/acceptance.test.js    受入基準 ＝ 検査役ゲート（npm run verify）
├─ scripts/
│  ├─ lint.mjs                依存ゼロの最小リンタ（npm run lint）
│  ├─ guard.sh                PreToolUseフック：push/merge/依存追加/削除を拒否
│  ├─ setup-git.sh            最初の1回：git init + 初期コミット（worktree用）
│  └─ run-loop.sh             ★ worktree作成→fixer→verifier→push→PR を1コマンドで
├─ .claude/
│  ├─ agents/fixer.md         作る役（worktree内で修正）
│  ├─ agents/verifier.md      検査役（読み取り専用で採点）
│  └─ settings.json           guard.sh を PreToolUse に登録
└─ .github/workflows/ci.yml   CI（lint + test）
```

---

## 使い方

```bash
# ① 最初の1回だけ：git を初期化（worktree には git リポジトリが必要）
bash scripts/setup-git.sh

# ② ループを回す
bash scripts/run-loop.sh
```

`run-loop.sh` は次を自動でやります（出力がスライドの①〜④に対応）:

1. **worktree を作成**（`git worktree add`）＝ 防護壁。`main` を汚さない隔離作業場。
2. **fixer サブエージェントが修正**（worktree 内）。`npm run check` が緑になるまで。
3. **verifier サブエージェントが検証**。`goal.md` の AC に照らして採点（読み取り専用）。
4. **合格 → コミット → push → PR 作成**。worktree は撤収、ブランチは保持。**merge は人間**。
   不合格 → 停止条件（ロールバック／エスカレーション）で worktree とブランチを巻き戻す。

> **push / PR について**
> push と `gh pr create` は **オーケストレータ（このスクリプト自身）** が実行します。
> エージェント（fixer/verifier）には `permissions` と `guard.sh` で push/merge を拒否したままなので、
> 「コードの作成・検証はエージェント、push と PR は仕組み、merge は人間」という分担になります。
> - 前提：`origin` 設定済み＋`gh` 認証済み（`gh auth status`）。無ければ push/PR は自動でスキップ。
> - `NO_PUSH=1 bash scripts/run-loop.sh` でローカルのコミットだけにとどめられます。
> - 実行ごとにタイムスタンプ付きの新しいブランチ＝新しい PR ができます。

### 2つのモード
- `MODE=agent`（`claude` があれば既定）… 実際に Claude Code のサブエージェントへ委任。
- `MODE=sim`（`claude` 無し・オフライン用）… 修正と検証を決定論的に実行して流れを通す。
  発表会場の回線が不安だったら `MODE=sim bash scripts/run-loop.sh` で確実に通せます。

```bash
MODE=sim   bash scripts/run-loop.sh   # 回線に依存せず流れだけ見せる
MODE=agent bash scripts/run-loop.sh   # 本番：サブエージェントに任せる
```

---

## なぜ worktree なのか（防護壁）
`git worktree` は同じリポジトリを別ディレクトリに別ブランチで展開する仕組み。
エージェントの編集は worktree の中だけで起き、`main` や他の並列作業と衝突しません。
複数 issue を同時に回すときは worktree を複数作れば、各エージェントが互いを壊しません。

## なぜ役割を分けるのか（作る役 ≠ 検査役）
- `fixer` と `verifier` は別サブエージェント＝**別コンテキスト**。fixer の思考や言い訳は
  verifier に渡らないので、「自分で書いて自分で合格」を構造的に防げます。
- `verifier` のツールは読み取り系に絞ってあり、**コードを編集できません**（直してOKにできない）。
- さらに独立性を上げたいときは、`verifier.md` の `model:` を fixer と別モデルにします
  （相関した見落としが減る）。

## 権限ゲート（不可逆操作を止める）
`.claude/settings.json` が `scripts/guard.sh` を PreToolUse フックに登録しています。
`git push` / `git merge` / 依存追加 / 削除系を**決定論的に拒否**（モデルの判断に頼らない）。
PR の作成まではエージェント、`main` への merge は人間が行います。

---

## エージェントに任せる場合のコマンド（参考）
`run-loop.sh` の中で実行している中身です。単体でも使えます。

```bash
# 修正（worktree 内で。編集を事前許可し、予算/ターン上限を停止条件に）
claude -p "CLAUDE.md と goal.md を読み、fixer で受入基準を全部満たすよう直して。\
npm run check が緑になったらコミットだけ。push も merge もしない。" \
  --permission-mode acceptEdits --model sonnet --max-turns 20 --max-budget-usd 2

# 検証（読み取り専用に絞る）
claude -p "verifier で goal.md の AC を採点して。最後に VERDICT を1行で。" \
  --allowedTools "Read" "Grep" "Glob" "Bash(npm run *)" "Bash(node *)" \
  --max-turns 15 --max-budget-usd 1
```

> メモ：現行の Claude Code ではサブエージェントは対話的な許可プロンプトに答えられません。
> そのため編集する fixer はヘッドレス（`-p`）で `--permission-mode acceptEdits` 等で
> 権限を事前付与して回します。verifier は `--allowedTools` を読み取り系に限定して、
> そもそも編集できないようにします。

本番の Loop では、この `run-loop.sh` を人が叩く代わりに Automation / cron / CI が
定期・イベントで起動します（例：毎朝9時、または CI 失敗を検知して）。

## 可視化（ターミナル出力）

可視化は `run-loop.sh` のターミナル出力だけです。行頭ラベルで「誰が」何をしたかが色分けで流れます
（`orch`=このスクリプト本体 / `main`=claude親 / `fixer` / `verifier`）。会場で読ませたいときは間を空けます：

```bash
STEP_DELAY=1 bash scripts/run-loop.sh
```

**agentモードでは claude の各ステップを「どのエージェントか」付きで細かく出します。**
`claude` を `--output-format stream-json --verbose` で動かし、`run-loop.sh` 内のフォーマッタが
`parent_tool_use_id` と `Agent`(旧`Task`)ツールの `subagent_type` から行ごとに発信元を判定して、
行頭ラベルで色分けします：

- `orch`（シアン）… このスクリプト本体（worktree作成・フェーズ宣言・ゲート・push/PR）。simの擬似ステップ以外の進行役
- `main`（紫）… その `claude -p` を直接動かす親エージェント（委任・最終確認を担当）
- `fixer`（黄）… 親が委任した修正サブエージェント（実際に Read/Edit/Bash する）
- `verifier`（緑）… 検証フェーズで委任されるサブエージェント

記号は `💬` 発話 / `🔧` ツール使用 / `↩` 結果 / `❌` エラー / `✓` 完了。
simモードでは claude を呼ばないので `main` は出ず、`orch` / `fixer` / `verifier` の擬似実況になります。

## リセット（バグ状態に戻す）
`src/stock.js` の `getStockStatus` を `<= 0` から元の二重 `IN_STOCK` に戻すだけ。
git 管理下なら `git checkout -- src/stock.js`。
