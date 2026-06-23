import { test } from 'node:test';
import assert from 'node:assert/strict';
import { getStockStatus } from '../src/stock.js';

// これが「検査役ゲート」。npm run verify で実行する。
// goal.md の受入基準(AC)に1対1で対応している。
// 別エージェント（検査役）が毎ターンこれで採点する想定。

test('AC1: 在庫が1以上 → in_stock', () => {
  assert.equal(getStockStatus(3), 'in_stock');
});

test('AC2: 在庫0 → sold_out（売り切れ）', () => {
  assert.equal(getStockStatus(0), 'sold_out');
});

test('AC3: 在庫マイナス（返品処理中）→ sold_out', () => {
  // ★ 落とし穴。0 だけ直して `=== 0` で済ませると、ここで落ちる。
  assert.equal(getStockStatus(-1), 'sold_out');
});
