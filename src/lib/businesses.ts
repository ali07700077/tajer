import { supabase } from "./supabase";

export type BusinessType = "buyer" | "supplier";
export type Governorate = { id: string; name_ar: string };
export type City = { id: string; governorate_id: string; name_ar: string };
export type BusinessSummary = {
  id: string;
  business_type: BusinessType;
  name_ar: string;
  verification_status: string;
  governorate_id: string;
  city_id: string | null;
};

function client() {
  if (!supabase) throw new Error("اتصال قاعدة البيانات غير مضبوط.");
  return supabase;
}

export async function getActiveGovernorates(): Promise<Governorate[]> {
  const { data, error } = await client()
    .from("governorates")
    .select("id,name_ar")
    .eq("is_active", true)
    .order("sort_order", { ascending: true });
  if (error) throw error;
  return data ?? [];
}

export async function getCities(governorateId: string): Promise<City[]> {
  const { data, error } = await client()
    .from("cities")
    .select("id,governorate_id,name_ar")
    .eq("governorate_id", governorateId)
    .eq("is_active", true)
    .order("sort_order", { ascending: true });
  if (error) throw error;
  return data ?? [];
}

/**
 * Creates a business and its owner membership atomically through the
 * database's guarded create_business RPC. New businesses start as draft.
 */
export async function createBusiness(input: {
  businessType: BusinessType;
  nameAr: string;
  governorateId: string;
  cityId?: string;
  phone?: string;
}): Promise<string> {
  const { data: sessionData, error: sessionError } = await client().auth.getSession();
  if (sessionError) throw sessionError;
  if (!sessionData.session) throw new Error("سجّل الدخول أولاً لإنشاء ملف الشركة.");

  const { data, error } = await client().rpc("create_business", {
    p_business_type: input.businessType,
    p_name_ar: input.nameAr.trim(),
    p_governorate_id: input.governorateId,
    p_city_id: input.cityId || undefined,
    p_phone: input.phone?.trim() || undefined,
  });
  if (error) throw error;
  return data;
}

export async function getMyBusinesses(): Promise<BusinessSummary[]> {
  const { data: sessionData, error: sessionError } = await client().auth.getSession();
  if (sessionError) throw sessionError;
  if (!sessionData.session) return [];

  const { data, error } = await client()
    .from("business_members")
    .select("business_id,member_role,businesses!inner(id,business_type,name_ar,verification_status,governorate_id,city_id)")
    .eq("user_id", sessionData.session.user.id);
  if (error) throw error;

  return (data ?? []).flatMap((membership: any) => {
    const business = membership.businesses;
    return business ? [{
      id: business.id,
      business_type: business.business_type,
      name_ar: business.name_ar,
      verification_status: business.verification_status,
      governorate_id: business.governorate_id,
      city_id: business.city_id,
    }] : [];
  });
}
