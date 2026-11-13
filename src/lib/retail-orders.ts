import { supabase } from "./supabase";

export type RetailCartItem = { product_id: string; quantity: number };
export type RetailOrderResult = {
  order_id: string;
  supplier_business_id: string;
  total_amount: number;
};

export async function createRetailOrders(items: RetailCartItem[], deliveryAddress: string): Promise<RetailOrderResult[]> {
  if (!supabase) throw new Error("اتصال قاعدة البيانات غير مضبوط.");
  if (!items.length || items.length > 50) throw new Error("سلة المفرد غير صالحة.");
  if (items.some(item => !Number.isInteger(item.quantity) || item.quantity < 1)) {
    throw new Error("كل كمية يجب أن تكون عدداً صحيحاً موجباً.");
  }
  if (deliveryAddress.trim().length < 8) throw new Error("أدخل عنوان توصيل واضحاً.");
  const { data: auth, error: authError } = await supabase.auth.getUser();
  if (authError) throw authError;
  if (!auth.user) throw new Error("سجّل الدخول أولاً لإتمام طلب المفرد.");
  const { data, error } = await (supabase as any).rpc("create_retail_orders", {
    p_items: items,
    p_delivery_address: deliveryAddress.trim(),
  });
  if (error) throw error;
  return (data ?? []) as RetailOrderResult[];
}
