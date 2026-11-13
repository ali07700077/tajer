import { createClient } from "@supabase/supabase-js";
import type { Database } from "../types/database";

const url = import.meta.env.VITE_SUPABASE_URL as string | undefined;
const key = import.meta.env.VITE_SUPABASE_PUBLISHABLE_KEY as string | undefined;

export const isSupabaseConfigured = Boolean(url && key);
export const supabase = isSupabaseConfigured
  ? createClient<Database>(url!, key!, {
      auth: { persistSession: true, autoRefreshToken: true, detectSessionInUrl: true },
    })
  : null;

// Only the publishable key belongs in browser builds. Never add service_role or secret keys here.
