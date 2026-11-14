import { supabase } from "./supabase";

export type HybridCheckoutItem = {
  product_id: string;
  quantity: number;
};

export type HybridChildOrder = {
  order_id: string;
  supplier_business_id: string;
  total_amount: number;
};

export type HybridCheckoutResult = {
  checkout_session_id: string;
  status: "pending_payment" | "partially_paid" | "paid" | "expired" | "cancelled";
  total_amount: number;
  currency: "IQD";
  expires_at: string;
  retail_orders: HybridChildOrder[];
  wholesale_orders: HybridChildOrder[];
};

function validateItems(items: HybridCheckoutItem[], label: string) {
  if (items.length > 50) throw new Error(`عدد عناصر ${label} يتجاوز الحد المسموح.`);
  const seen = new Set<string>();
  for (const item of items) {
    if (!item.product_id || seen.has(item.product_id)) throw new Error(`تأكد من عدم تكرار المنتجات في ${label}.`);
    if (!Number.isSafeInteger(item.quantity) || item.quantity < 1) throw new Error(`كمية ${label} يجب أن تكون عدداً صحيحاً موجباً.`);
    seen.add(item.product_id);
  }
}

export async function createHybridCheckout(input: {
  buyerBusinessId?: string | null;
  retailItems: HybridCheckoutItem[];
  wholesaleItems: HybridCheckoutItem[];
  deliveryAddress: string;
}): Promise<HybridCheckoutResult> {
  if (!supabase) throw new Error("اتصال قاعدة البيانات غير مضبوط.");
  validateItems(input.retailItems, "المفرد");
  validateItems(input.wholesaleItems, "الجملة");
  if (!input.retailItems.length && !input.wholesaleItems.length) throw new Error("سلة الشراء فارغة.");
  if (input.wholesaleItems.length && !input.buyerBusinessId) throw new Error("اختر ملف شركة مشتري لطلب الجملة.");
  if (input.deliveryAddress.trim().length < 8) throw new Error("أدخل عنوان توصيل واضحاً.");

  const { data: auth, error: authError } = await supabase.auth.getUser();
  if (authError) throw authError;
  if (!auth.user) throw new Error("سجّل الدخول أولاً لإتمام عملية الشراء.");

  const { data, error } = await supabase.rpc("create_hybrid_checkout", {
    p_buyer_business_id: input.buyerBusinessId ?? null,
    p_retail_items: input.retailItems,
    p_wholesale_items: input.wholesaleItems,
    p_delivery_address: input.deliveryAddress.trim(),
  });
  if (error) throw error;
  if (!data || typeof data !== "object" || Array.isArray(data)) throw new Error("استجابة عملية الشراء الموحدة غير صالحة.");
  const result = data as unknown as HybridCheckoutResult;
  if (!result.checkout_session_id || !Array.isArray(result.retail_orders) || !Array.isArray(result.wholesale_orders)) {
    throw new Error("لم تُرجع قاعدة البيانات رقم عملية الشراء والطلبات الفرعية بصورة صحيحة.");
  }
  return result;
}
