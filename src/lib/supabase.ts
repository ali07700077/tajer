import { createClient } from "@supabase/supabase-js";
import type { Database } from "../types/database";

// Publishable keys are designed for browser use; authorization is enforced by RLS.
const url = (import.meta.env.VITE_SUPABASE_URL as string | undefined)
  ?? "https://uxzdgcfijplqalgkgkgp.supabase.co";
const key = (import.meta.env.VITE_SUPABASE_PUBLISHABLE_KEY as string | undefined)
  ?? "sb_publishable_oXAAImz1Jv8qvUsigRehpA_EH_Qodgn";

export const isSupabaseConfigured = Boolean(url && key);
export const supabase = isSupabaseConfigured
  ? createClient<Database>(url, key, {
      auth: { persistSession: true, autoRefreshToken: true, detectSessionInUrl: true },
    })
  : null;

// Never put service_role or sb_secret keys in browser code.
