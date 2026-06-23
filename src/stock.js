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
