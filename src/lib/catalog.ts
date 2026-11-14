import { supabase } from "./supabase";

export type CatalogProduct = {
  id: string;
  name: string;
  description: string | null;
  sku: string | null;
  price: number;
  retail_price: number | null;
  is_retail_available: boolean;
  min_order_quantity: number;
  stock_quantity: number;
  available_quantity: number;
  category: { name_ar: string } | null;
  supplier_name?: string;
  governorate_name?: string;
  price_usd?: number | null;
  retail_price_usd?: number | null;
  fx_rate_iqd_per_usd?: number;
  is_demo?: boolean;
};

export async function getPublicCatalog(): Promise<CatalogProduct[]> {
  if (!supabase) throw new Error("اتصال قاعدة البيانات غير مضبوط.");
  const { data, error } = await supabase
    .from("products")
    .select("id,name,description,sku,price,retail_price,is_retail_available,min_order_quantity,stock_quantity,available_quantity,category:categories(name_ar)")
    .eq("is_active", true)
    .order("created_at", { ascending: false });
  if (error) throw error;
  const live = (data ?? []) as unknown as CatalogProduct[];
  if (live.length) return live;

  // Read-only fallback catalog: explicitly demo data, never passed to checkout RPCs.
  const { data: demo, error: demoError } = await (supabase as any)
    .from("catalog_demo_products")
    .select("id,sku,name,description,price_iqd,retail_price_iqd,price_usd,retail_price_usd,fx_rate_iqd_per_usd,min_order_quantity,stock_quantity,category_name,supplier_name,governorate_name,is_retail_available,demo_only")
    .eq("demo_only", true)
    .order("governorate_name", { ascending: true })
    .limit(60);
  if (demoError) throw demoError;
  return (demo ?? []).map((p: any) => ({
    id: p.id,
    name: p.name,
    description: p.description,
    sku: p.sku,
    price: Number(p.price_iqd),
    retail_price: Number(p.retail_price_iqd),
    price_usd: Number(p.price_usd),
    retail_price_usd: Number(p.retail_price_usd),
    fx_rate_iqd_per_usd: Number(p.fx_rate_iqd_per_usd),
    is_retail_available: Boolean(p.is_retail_available),
    min_order_quantity: Number(p.min_order_quantity),
    stock_quantity: Number(p.stock_quantity),
    available_quantity: Number(p.stock_quantity),
    category: { name_ar: p.category_name },
    supplier_name: p.supplier_name,
    governorate_name: p.governorate_name,
    is_demo: true,
  }));
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
