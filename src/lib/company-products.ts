import { supabase } from "./supabase";
import type { BusinessSummary } from "./businesses";

export type CompanyProduct = {
  id: string;
  business_id: string;
  name: string;
  description: string | null;
  price: number;
  min_order_quantity: number;
  image_path: string | null;
  is_active: boolean;
  created_at: string;
};

function client() {
  if (!supabase) throw new Error("اتصال قاعدة البيانات غير مضبوط.");
  return supabase;
}

export async function getCompanyProducts(businessId: string): Promise<CompanyProduct[]> {
  const { data, error } = await client().from("products")
    .select("id,business_id,name,description,price,min_order_quantity,image_path,is_active,created_at")
    .eq("business_id", businessId)
    .order("created_at", { ascending: false });
  if (error) throw error;
  return (data ?? []) as CompanyProduct[];
}

export async function createCompanyProduct(input: {
  business: BusinessSummary;
  name: string;
  description: string;
  price: number;
  minOrderQuantity: number;
  image?: File | null;
}): Promise<void> {
  const db = client();
  if (input.business.business_type !== "supplier") throw new Error("إضافة المنتجات متاحة لحسابات الموردين فقط.");
  const { data: auth, error: authError } = await db.auth.getUser();
  if (authError) throw authError;
  if (!auth.user) throw new Error("انتهت جلسة الدخول. سجّل الدخول مجدداً.");

  let imagePath: string | null = null;
  let uploaded = false;
  const productId = crypto.randomUUID();
  if (input.image) {
    if (!["image/jpeg", "image/png", "image/webp"].includes(input.image.type)) {
      throw new Error("صيغة الصورة يجب أن تكون JPG أو PNG أو WEBP.");
    }
    if (input.image.size > 5 * 1024 * 1024) throw new Error("حجم الصورة الأقصى 5 ميغابايت.");
    const extension = input.image.type === "image/png" ? "png" : input.image.type === "image/webp" ? "webp" : "jpg";
    imagePath = `${input.business.id}/${productId}/cover.${extension}`;
    const { error } = await db.storage.from("product-images").upload(imagePath, input.image, {
      contentType: input.image.type, upsert: false,
    });
    if (error) throw error;
    uploaded = true;
  }

  const { error } = await db.from("products").insert({
    id: productId,
    business_id: input.business.id,
    name: input.name.trim(),
    description: input.description.trim() || null,
    price: input.price,
    min_order_quantity: input.minOrderQuantity,
    image_path: imagePath,
    is_active: false,
  });
  if (error) {
    if (uploaded && imagePath) await db.storage.from("product-images").remove([imagePath]);
    throw error;
  }
}

export async function updateCompanyProduct(productId: string, input: {
  name: string; description: string; price: number; minOrderQuantity: number;
}): Promise<void> {
  const { error } = await client().from("products").update({
    name: input.name.trim(),
    description: input.description.trim() || null,
    price: input.price,
    min_order_quantity: input.minOrderQuantity,
  }).eq("id", productId);
  if (error) throw error;
}

export async function deleteCompanyProduct(product: CompanyProduct): Promise<void> {
  const db = client();
  const { error } = await db.from("products").delete().eq("id", product.id);
  if (error) throw error;
  if (product.image_path) {
    const { error: imageError } = await db.storage.from("product-images").remove([product.image_path]);
    if (imageError) throw imageError;
  }
}

export async function getCompanyProductImageUrl(path: string): Promise<string | null> {
  const { data, error } = await client().storage.from("product-images").createSignedUrl(path, 60 * 60);
  if (error) return null;
  return data.signedUrl;
}
