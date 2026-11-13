import type { AuthError, Session } from "@supabase/supabase-js";
import { supabase } from "./supabase";

function requireClient() {
  if (!supabase) throw new Error("اتصال قاعدة البيانات غير مضبوط.");
  return supabase;
}

export async function signInWithEmail(email: string, password: string) {
  const { data, error } = await requireClient().auth.signInWithPassword({ email: email.trim(), password });
  if (error) throw error;
  return data;
}

export async function signUpWithEmail(input: { email: string; password: string; fullName: string; phone?: string }) {
  const { data, error } = await requireClient().auth.signUp({
    email: input.email.trim(),
    password: input.password,
    options: { data: { full_name: input.fullName.trim(), phone: input.phone?.trim() ?? null } },
  });
  if (error) throw error;
  return data;
}

export async function signOut() {
  const { error } = await requireClient().auth.signOut();
  if (error) throw error;
}

export async function getCurrentSession(): Promise<Session | null> {
  const { data, error } = await requireClient().auth.getSession();
  if (error) throw error;
  return data.session;
}

export function onSessionChange(callback: (session: Session | null) => void) {
  return requireClient().auth.onAuthStateChange((_event, session) => callback(session));
}

export type { AuthError };
