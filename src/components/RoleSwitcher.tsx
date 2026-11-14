import { useEffect, useMemo, useState } from "react";
import { getCurrentSession, onSessionChange } from "../lib/auth";
import { getMyBusinesses, type BusinessSummary } from "../lib/businesses";
import type { Session } from "@supabase/supabase-js";

export type AppRole = "retail_buyer" | "wholesale_buyer" | "supplier" | "warehouse_manager";
type Props = { onRoleChange: (role: AppRole, businessId: string | null) => void };

const labels: Record<AppRole, string> = {
  retail_buyer: "مشتري مفرد",
  wholesale_buyer: "تاجر جملة",
  supplier: "مورد",
  warehouse_manager: "أمين مخزن",
};

export default function RoleSwitcher({ onRoleChange }: Props) {
  const [session, setSession] = useState<Session | null>(null);
  const [businesses, setBusinesses] = useState<BusinessSummary[]>([]);
  const [activeRole, setActiveRole] = useState<AppRole>("retail_buyer");
  const [loading, setLoading] = useState(true);
  const [message, setMessage] = useState("");

  async function refresh() {
    try {
      const current = await getCurrentSession();
      setSession(current);
      setBusinesses(current ? await getMyBusinesses() : []);
    } catch (error) {
      setMessage(error instanceof Error ? error.message : "تعذر تحميل صلاحيات الحساب.");
      setBusinesses([]);
    } finally {
      setLoading(false);
    }
  }

  useEffect(() => {
    let alive = true;
    void refresh();
    let subscription: { unsubscribe: () => void } | undefined;
    try {
      const listener = onSessionChange(() => { if (alive) void refresh(); });
      subscription = listener.data.subscription;
    } catch { /* Supabase is optional in local preview mode. */ }
    return () => { alive = false; subscription?.unsubscribe(); };
  }, []);

  const available = useMemo(() => ({
    retail_buyer: Boolean(session),
    wholesale_buyer: businesses.some(b => b.business_type === "buyer"),
    supplier: businesses.some(b => b.business_type === "supplier"),
    // Warehouse writes are intentionally unavailable until a dedicated
    // warehouse permission is provisioned and enforced by database policies.
    warehouse_manager: false,
  }), [session, businesses]);

  function choose(role: AppRole) {
    if (!available[role]) return;
    setActiveRole(role);
    const business = role === "wholesale_buyer"
      ? businesses.find(b => b.business_type === "buyer")
      : role === "supplier" ? businesses.find(b => b.business_type === "supplier") : undefined;
    onRoleChange(role, business?.id ?? null);
    setMessage("");
  }

  return <section className="role-switcher" aria-label="مبدّل الأدوار" data-testid="role-switcher">
    <div className="role-switcher-heading">
      <span className="role-live-dot" />
      <span>مساحة العمل</span>
      <small>{loading ? "جارٍ التحقق..." : session ? "الأدوار حسب عضوياتك" : "تصفح كزائر"}</small>
    </div>
    <div className="role-options" role="group" aria-label="اختيار الدور">
      {(Object.keys(labels) as AppRole[]).map(role => {
        const enabled = available[role];
        return <button
          key={role}
          type="button"
          data-testid={`role-${role}`}
          aria-pressed={activeRole === role}
          aria-disabled={!enabled}
          disabled={!enabled || loading}
          className={`role-option ${activeRole === role ? "selected" : ""} ${!enabled ? "locked" : ""}`}
          title={!enabled ? (role === "warehouse_manager" ? "يتطلب صلاحية مخازن مخصصة من قاعدة البيانات" : "سجّل الدخول أو اربط شركة بهذا الدور") : labels[role]}
          onClick={() => choose(role)}
        >
          <span className="role-option-icon">{role === "retail_buyer" ? "◈" : role === "wholesale_buyer" ? "▦" : role === "supplier" ? "◇" : "▣"}</span>
          <span>{labels[role]}</span>
          {!enabled && <span className="role-lock" aria-hidden="true">⌑</span>}
        </button>;
      })}
    </div>
    {message && <span className="role-message" role="status">{message}</span>}
  </section>;
}
