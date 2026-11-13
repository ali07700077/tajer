import { supabase } from "./supabase";

export type WholesaleCartItem = { product_id: string; quantity: number };
export type WholesaleOrderResult = {
  order_id: string;
  supplier_business_id: string;
  total_amount: number;
};

function client() {
  if (!supabase) throw new Error("اتصال قاعدة البيانات غير مضبوط.");
  return supabase;
}

function validateCart(items: WholesaleCartItem[]) {
  if (!items.length || items.length > 50) throw new Error("سلة الجملة غير صالحة.");
  const seen = new Set<string>();
  for (const item of items) {
    if (!item.product_id || seen.has(item.product_id)) throw new Error("لا تكرر المنتج نفسه في السلة.");
    if (!Number.isSafeInteger(item.quantity) || item.quantity < 1) throw new Error("كل كمية يجب أن تكون عدداً صحيحاً موجباً.");
    seen.add(item.product_id);
  }
}

export async function createWholesaleOrders(
  buyerBusinessId: string,
  items: WholesaleCartItem[],
  deliveryAddress: string,
): Promise<WholesaleOrderResult[]> {
  validateCart(items);
  if (deliveryAddress.trim().length < 8) throw new Error("أدخل عنوان توصيل واضحاً.");
  const db = client();
  const { data: auth, error: authError } = await db.auth.getUser();
  if (authError) throw authError;
  if (!auth.user) throw new Error("سجّل الدخول أولاً لإتمام طلب الجملة.");
  const { data, error } = await db.rpc("create_wholesale_orders", {
    p_buyer_business_id: buyerBusinessId,
    p_items: items,
    p_delivery_address: deliveryAddress.trim(),
  });
  if (error) throw error;
  if (!Array.isArray(data)) throw new Error("استجابة إنشاء طلبات الجملة غير صالحة.");
  return data as unknown as WholesaleOrderResult[];
}

export async function requestProductSample(input: {
  buyerBusinessId: string;
  productId: string;
  quantity: number;
  deliveryAddress: string;
}): Promise<string> {
  if (!Number.isSafeInteger(input.quantity) || input.quantity < 1) throw new Error("كمية العينة غير صالحة.");
  if (input.deliveryAddress.trim().length < 8) throw new Error("أدخل عنوان توصيل واضحاً.");
  const { data, error } = await client().rpc("create_product_sample_request", {
    p_buyer_business_id: input.buyerBusinessId,
    p_product_id: input.productId,
    p_quantity: input.quantity,
    p_delivery_address: input.deliveryAddress.trim(),
  });
  if (error) throw error;
  if (!data) throw new Error("لم يتم إنشاء طلب العينة.");
  return data;
}

export async function createProformaInvoice(input: {
  orderId: string;
  validUntil?: string | null;
  terms?: string | null;
}): Promise<string> {
  const { data, error } = await client().rpc("create_proforma_invoice", {
    p_order_id: input.orderId,
    p_valid_until: input.validUntil ?? null,
    p_terms: input.terms?.trim() || null,
  });
  if (error) throw error;
  if (!data) throw new Error("لم يتم إصدار الفاتورة الأولية.");
  return data;
}
