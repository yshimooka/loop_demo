# CLAUDE.md — Loop デモ用サンドボックス

## 概要
在庫ステータス判定の最小リポジトリ。依存ゼロ・ESM・Node 標準モジュールのみ。
ライブデモ「CI失敗 → 修正 → 検証 → PR」を回すための題材。

## 見るべきファイル
- `src/stock.js` … 実装（いまここにバグがある）
- `test/stock.test.js` … 単体テスト（CIゲート, `npm test`）
- `test/acceptance.test.js` … 受入基準（検査役ゲート, `npm run verify`）
- `goal.md` … 完了の定義・受入基準・停止条件・権限ゲート

## ルール
- 依存パッケージを追加しない（Node 標準のみ）。
- `var` を使わない / `console.log` を残さない（`npm run lint` で確認）。
- 直す前に必ず `npm test` を実行し、赤を確認してから着手する。
- 完了の判断は自分でせず、`goal.md` の受入基準に従う。

## やってはいけない
- `main` への直接 push / merge（PR まで。merge は人間）。
- 受入基準(AC)を緩める、テストを消して通す。

## 過去の罠
- 在庫は 0 だけでなく「マイナス（返品処理中）」も売り切れ扱い（AC3）。
  しきい値は `=== 0` ではなく `<= 0`。

## 作業の流れ（Loop）
- 修正は worktree（隔離された作業場）の中だけで行う。`main` では作業しない。
- 作る役は `fixer`（.claude/agents/fixer.md）、検査役は `verifier`（同 verifier.md）。
- 役割を分ける：作った本人は合格判定をしない。検査は verifier に任せる。
- `scripts/run-loop.sh` が「worktree作成 → fixer → verifier → PR」を1コマンドで回す。
