import { useEffect, useState } from "react";
import { getCurrentSession, onSessionChange, signInWithEmail, signOut, signUpWithEmail } from "../lib/auth";
import { getActiveGovernorates, getMyBusinesses, type BusinessSummary, type BusinessType, type Governorate } from "../lib/businesses";
import { supabase } from "../lib/supabase";

export default function AccountCenter() {
  const [mode, setMode] = useState<"signin" | "signup">("signin");
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [fullName, setFullName] = useState("");
  const [phone, setPhone] = useState("");
  const [businessName, setBusinessName] = useState("");
  const [businessType, setBusinessType] = useState<BusinessType>("supplier");
  const [governorateId, setGovernorateId] = useState("");
  const [governorates, setGovernorates] = useState<Governorate[]>([]);
  const [businesses, setBusinesses] = useState<BusinessSummary[]>([]);
  const [userEmail, setUserEmail] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [loading, setLoading] = useState(false);
  const [message, setMessage] = useState("");
  const devSignup = import.meta.env.DEV;

  async function refresh() {
    setLoading(true);
    try { setBusinesses(await getMyBusinesses()); }
    catch (e) { setMessage(e instanceof Error ? e.message : "تعذر جلب الشركات."); }
    finally { setLoading(false); }
  }

  useEffect(() => {
    if (!supabase) return;
    let active = true;
    getCurrentSession().then(s => {
      if (active) { setUserEmail(s?.user.email ?? null); if (s) void refresh(); }
    }).catch(() => undefined);
    const { data } = onSessionChange(s => {
      if (!active) return;
      setUserEmail(s?.user.email ?? null);
      if (s) void refresh(); else setBusinesses([]);
    });
    return () => { active = false; data.subscription.unsubscribe(); };
  }, []);

  async function beginSignup() {
    setMode("signup");
    if (!governorates.length) {
      try { setGovernorates(await getActiveGovernorates()); }
      catch (e) { setMessage(e instanceof Error ? e.message : "تعذر تحميل المحافظات."); }
    }
  }

  async function submit() {
    setBusy(true); setMessage("");
    try {
      if (mode === "signin") {
        await signInWithEmail(email, password);
        await refresh();
        setMessage("تم تسجيل الدخول.");
      } else {
        if (!devSignup) throw new Error("التسجيل الجديد مغلق خارج بيئة التطوير.");
        if (password.length < 8 || !fullName.trim() || !businessName.trim() || !governorateId) {
          throw new Error("أكمل الحقول المطلوبة واستخدم كلمة مرور من 8 أحرف على الأقل.");
        }
        const result = await signUpWithEmail({ email, password, fullName, phone, businessType, businessName, governorateId });
        if (result.session) await refresh();
        setMessage(result.session
          ? "تم إنشاء الحساب والشركة. حالة الشركة: مسودة، ودورك: مالك."
          : "تم إنشاء الحساب. أكّد بريدك الإلكتروني؛ تُنشأ الشركة تلقائياً بحالة مسودة ودورك مالك.");
      }
    } catch (e) { setMessage(e instanceof Error ? e.message : "حدث خطأ غير متوقع."); }
    finally { setBusy(false); }
  }

  async function logout() {
    try { await signOut(); setUserEmail(null); setBusinesses([]); setMessage("تم تسجيل الخروج."); }
    catch (e) { setMessage(e instanceof Error ? e.message : "تعذر تسجيل الخروج."); }
  }

  return <section className="panel account-center">
    <div className="panel-head"><div><h3>{userEmail ? "حسابي وشركاتي" : "حساب تاجر"}</h3><span className="muted">إدارة الحسابات وملفات الشركات المرتبطة بك</span></div>{userEmail && <button className="outline" onClick={logout}>تسجيل الخروج</button>}</div>
    {!userEmail && <div className="account-form">
      <div className="mode-switch"><button className={mode === "signin" ? "selected" : ""} onClick={() => setMode("signin")}>تسجيل الدخول</button><button className={mode === "signup" ? "selected" : ""} onClick={beginSignup} disabled={!devSignup}>حساب جديد</button></div>
      {mode === "signup" && <>
        <label>الاسم الكامل<input value={fullName} onChange={e => setFullName(e.target.value)} autoComplete="name" /></label>
        <label>اسم الشركة أو المتجر<input value={businessName} onChange={e => setBusinessName(e.target.value)} /></label>
        <label>رقم الهاتف<input value={phone} onChange={e => setPhone(e.target.value)} inputMode="tel" /></label>
        <label>نوع الحساب<select value={businessType} onChange={e => setBusinessType(e.target.value as BusinessType)}><option value="supplier">مورد / تاجر جملة</option><option value="buyer">مشتري / صاحب متجر</option></select></label>
        <label>المحافظة<select value={governorateId} onChange={e => setGovernorateId(e.target.value)}><option value="">اختر المحافظة</option>{governorates.map(g => <option key={g.id} value={g.id}>{g.name_ar}</option>)}</select></label>
      </>}
      <label>البريد الإلكتروني<input type="email" value={email} onChange={e => setEmail(e.target.value)} autoComplete="email" /></label>
      <label>كلمة المرور<input type="password" value={password} onChange={e => setPassword(e.target.value)} autoComplete={mode === "signin" ? "current-password" : "new-password"} /></label>
      <button className="primary" disabled={busy || (mode === "signup" && !devSignup)} onClick={submit}>{busy ? "جارٍ التنفيذ..." : mode === "signin" ? "دخول" : "إنشاء الحساب والشركة"}</button>
      {!devSignup && <small>التسجيل الجديد غير متاح في نسخة الإنتاج. يمكن تفعيله في بيئة التطوير فقط.</small>}
    </div>}
    {userEmail && <><p className="account-email">مسجل الدخول: {userEmail}</p><div className="panel-head"><b>شركاتي</b><button className="outline" onClick={refresh}>تحديث</button></div>
      {loading ? <p>جارٍ تحميل الشركات...</p> : businesses.length === 0 ? <div className="empty">لا توجد شركات مرتبطة بهذا الحساب.</div> : businesses.map(b => <div className="business-row" key={b.id}><div><b>{b.name_ar}</b><small>{b.business_type === "supplier" ? "مورد / تاجر جملة" : "مشتري / صاحب متجر"}</small></div><span className="draft-pill">{b.verification_status === "draft" ? "مسودة" : b.verification_status}</span></div>)}
    </>}
    {message && <p className="notice account-message">{message}</p>}
  </section>;
}
