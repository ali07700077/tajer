import { supabase } from "./supabase";

export type CatalogProduct = {
  id: string;
  name: string;
  description: string | null;
  sku: string | null;
  price: number;
  min_order_quantity: number;
  stock_quantity: number;
  category: { name_ar: string } | null;
  business: { name_ar: string; verification_status: string; is_active: boolean } | null;
};

export async function getPublicCatalog(): Promise<CatalogProduct[]> {
  if (!supabase) throw new Error("اتصال قاعدة البيانات غير مضبوط.");
  const { data, error } = await supabase
    .from("products")
    .select("id,name,description,sku,price,min_order_quantity,stock_quantity,category:categories(name_ar),business:businesses!inner(name_ar,verification_status,is_active)")
    .eq("is_active", true)
    .eq("business.is_active", true)
    .eq("business.verification_status", "approved")
    .order("created_at", { ascending: false });
  if (error) throw error;
  return (data ?? []) as unknown as CatalogProduct[];
}

export async function getActiveCategories() {
  if (!supabase) throw new Error("اتصال قاعدة البيانات غير مضبوط.");
  const { data, error } = await supabase
    .from("categories")
    .select("id,slug,name_ar")
    .eq("is_active", true)
    .order("sort_order", { ascending: true });
  if (error) throw error;
  return data ?? [];
}
