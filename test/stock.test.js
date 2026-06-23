import { test } from 'node:test';
import assert from 'node:assert/strict';
import { getStockStatus } from '../src/stock.js';

// これが「CIゲート」。npm test で実行される。

test('在庫あり（5個）→ in_stock', () => {
  assert.equal(getStockStatus(5), 'in_stock');
});

test('在庫0 → sold_out（売り切れ）', () => {
  // ★ いまここが赤。CIが落ちている原因。
  assert.equal(getStockStatus(0), 'sold_out');
});
