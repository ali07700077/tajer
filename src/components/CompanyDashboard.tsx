import { useEffect, useState } from "react";
import { getCurrentSession, onSessionChange } from "../lib/auth";
import { getMyBusinesses, type BusinessSummary } from "../lib/businesses";
import { createCompanyProduct, deleteCompanyProduct, getCompanyProducts, updateCompanyProduct, type CompanyProduct } from "../lib/company-products";
import { supabase } from "../lib/supabase";

const money = (value: number) => new Intl.NumberFormat("en-US").format(value) + " د.ع";

export default function CompanyDashboard() {
  const [userId, setUserId] = useState<string | null>(null);
  const [businesses, setBusinesses] = useState<BusinessSummary[]>([]);
  const [selectedId, setSelectedId] = useState("");
  const [products, setProducts] = useState<CompanyProduct[]>([]);
  const [loading, setLoading] = useState(true);
  const [busy, setBusy] = useState(false);
  const [showForm, setShowForm] = useState(false);
  const [editing, setEditing] = useState<CompanyProduct | null>(null);
  const [name, setName] = useState("");
  const [description, setDescription] = useState("");
  const [price, setPrice] = useState("");
  const [moq, setMoq] = useState("1");
  const [image, setImage] = useState<File | null>(null);
  const [message, setMessage] = useState("");

  const selected = businesses.find(b => b.id === selectedId) ?? null;

  async function loadBusinesses() {
    const rows = await getMyBusinesses();
    setBusinesses(rows);
    setSelectedId(current => rows.some(row => row.id === current) ? current : rows[0]?.id ?? "");
  }

  async function loadProducts(businessId: string) {
    setLoading(true);
    try { setProducts(await getCompanyProducts(businessId)); }
    catch (e) { setProducts([]); setMessage(e instanceof Error ? e.message : "تعذر تحميل المنتجات."); }
    finally { setLoading(false); }
  }

  useEffect(() => {
    if (!supabase) { setLoading(false); return; }
    let alive = true;
    getCurrentSession().then(async session => {
      if (!alive) return;
      setUserId(session?.user.id ?? null);
      if (session) await loadBusinesses();
      else { setBusinesses([]); setProducts([]); setLoading(false); }
    }).catch(e => { if (alive) { setMessage(e instanceof Error ? e.message : "تعذر قراءة الجلسة."); setLoading(false); } });
    const { data } = onSessionChange(async session => {
      if (!alive) return;
      setUserId(session?.user.id ?? null);
      if (session) await loadBusinesses();
      else { setBusinesses([]); setProducts([]); setSelectedId(""); }
    });
    return () => { alive = false; data.subscription.unsubscribe(); };
  }, []);

  useEffect(() => { if (selectedId) void loadProducts(selectedId); else setProducts([]); }, [selectedId]);

  function resetForm() {
    setName(""); setDescription(""); setPrice(""); setMoq("1"); setImage(null); setEditing(null); setShowForm(false);
  }

  function startEdit(product: CompanyProduct) {
    setEditing(product); setName(product.name); setDescription(product.description ?? "");
    setPrice(String(product.price)); setMoq(String(product.min_order_quantity));
    setImage(null); setShowForm(true);
  }

  async function submitProduct() {
    if (!selected) return;
    const numericPrice = Number(price), numericMoq = Number(moq);
    if (!name.trim() || !Number.isFinite(numericPrice) || numericPrice <= 0 || !Number.isInteger(numericMoq) || numericMoq < 1) {
      setMessage("أدخل اسم المنتج وسعراً صحيحاً وكمية دنيا صحيحة (1 أو أكثر)."); return;
    }
    setBusy(true); setMessage("");
    try {
      if (editing) {
        await updateCompanyProduct(editing.id, { name, description, price: numericPrice, minOrderQuantity: numericMoq });
        setMessage("تم تحديث المنتج.");
      } else {
        await createCompanyProduct({ business: selected, name, description, price: numericPrice, minOrderQuantity: numericMoq, image });
        setMessage("تمت إضافة المنتج وربطه بشركتك. المنتج غير منشور للعامة حتى اعتماد الشركة وتفعيل النشر.");
      }
      resetForm();
      await loadProducts(selected.id);
    } catch (e) { setMessage(e instanceof Error ? e.message : "تعذرت عملية حفظ المنتج."); }
    finally { setBusy(false); }
  }

  async function removeProduct(product: CompanyProduct) {
    if (!window.confirm("هل تريد حذف هذا المنتج نهائياً؟")) return;
    setBusy(true);
    try { await deleteCompanyProduct(product); await loadProducts(product.business_id); setMessage("تم حذف المنتج."); }
    catch (e) { setMessage(e instanceof Error ? e.message : "تعذر حذف المنتج."); }
    finally { setBusy(false); }
  }

  if (!userId) return <section className="panel company-dashboard"><h3>لوحة الشركة</h3><p>سجّل الدخول أولاً لعرض لوحة شركتك ومنتجاتها.</p></section>;

  return <section className="panel company-dashboard">
    <div className="panel-head"><div><h3>لوحة تحكم الشركة</h3><span className="muted">إدارة بيانات الشركة وكتالوج الجملة الخاص بها</span></div>
      {selected?.business_type === "supplier" && <button className="primary" onClick={() => { setEditing(null); setShowForm(true); }}>＋ إضافة منتج</button>}
    </div>
    {businesses.length === 0 ? <div className="empty">لا توجد شركة مرتبطة بحسابك. أنشئ ملف الشركة من صفحة «شركاتي والحساب» أولاً.</div> : <>
      <div className="company-selector">
        <label>الشركة<select value={selectedId} onChange={e => setSelectedId(e.target.value)}>{businesses.map(b => <option key={b.id} value={b.id}>{b.name_ar}</option>)}</select></label>
        {selected && <div className="company-status"><b>{selected.name_ar}</b><span className={selected.verification_status === "approved" ? "status-active" : "draft-pill"}>{selected.verification_status === "approved" ? "معتمدة" : selected.verification_status === "suspended" ? "موقوفة" : selected.verification_status === "active" ? "نشطة" : "مسودة"}</span></div>}
      </div>
      {selected && <div className="company-metrics"><div><small>نوع الحساب</small><b>{selected.business_type === "supplier" ? "مورد / تاجر جملة" : "مشتري / صاحب متجر"}</b></div><div><small>عدد المنتجات</small><b>{products.length}</b></div><div><small>حالة الشركة</small><b>{selected.verification_status}</b></div></div>}
      {selected?.business_type === "buyer" && <div className="empty">هذه شركة مشتري. إدارة كتالوج المنتجات متاحة لشركات الموردين.</div>}
      {showForm && selected?.business_type === "supplier" && <div className="product-form">
        <div className="panel-head"><b>{editing ? "تعديل المنتج" : "إضافة منتج جديد"}</b><button className="outline" onClick={resetForm}>إلغاء</button></div>
        <label>اسم المنتج<input value={name} onChange={e => setName(e.target.value)} maxLength={160} placeholder="مثال: كابل شحن سريع" /></label>
        <label>وصف المنتج<textarea value={description} onChange={e => setDescription(e.target.value)} rows={3} placeholder="المواصفات والتفاصيل..." /></label>
        <div className="form-pair"><label>سعر الجملة (د.ع)<input type="number" min="1" step="1" value={price} onChange={e => setPrice(e.target.value)} /></label><label>الحد الأدنى للطلب (MOQ)<input type="number" min="1" step="1" value={moq} onChange={e => setMoq(e.target.value)} /></label></div>
        {!editing && <label>صورة المنتج (اختيارية، JPG/PNG/WEBP حتى 5MB)<input type="file" accept="image/jpeg,image/png,image/webp" onChange={e => setImage(e.target.files?.[0] ?? null)} /></label>}
        <button className="primary" disabled={busy} onClick={submitProduct}>{busy ? "جارٍ الحفظ..." : editing ? "حفظ التعديلات" : "إضافة المنتج"}</button>
      </div>}
      <div className="company-products-head"><h4>منتجات الشركة</h4><button className="outline" onClick={() => selected && loadProducts(selected.id)}>تحديث القائمة</button></div>
      {loading ? <p>جارٍ تحميل المنتجات...</p> : products.length === 0 ? <div className="empty">لا توجد منتجات لهذه الشركة بعد. أضف أول منتج إلى كتالوج الجملة.</div> : <div className="company-product-list">{products.map(p => <article className="company-product-row" key={p.id}><div className="product-thumb">{p.image_path ? "▧" : "▦"}</div><div className="company-product-main"><b>{p.name}</b><small>{p.description || "لا يوجد وصف"} · MOQ: {p.min_order_quantity}</small><strong>{money(Number(p.price))}</strong></div><span className="draft-pill">{p.is_active ? "مفعّل" : "مسودة"}</span><button className="outline" disabled={busy} onClick={() => startEdit(p)}>تعديل</button><button className="outline danger-outline" disabled={busy} onClick={() => removeProduct(p)}>حذف</button></article>)}</div>}
    </>}
    {message && <p className="notice account-message">{message}</p>}
  </section>;
}
