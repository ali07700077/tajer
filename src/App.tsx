import { useEffect, useMemo, useState } from "react";
import { getPublicCatalog, type CatalogProduct } from "./lib/catalog";
import { signInWithEmail } from "./lib/auth";
import { isSupabaseConfigured, supabase } from "./lib/supabase";
import AccountCenter from "./components/AccountCenter";
import CompanyDashboard from "./components/CompanyDashboard";
import RfqWorkspace from "./components/RfqWorkspace";

type Section = "overview" | "products" | "rfqs" | "orders" | "suppliers" | "businesses" | "company";
type Product = { id: string; name: string; category: string; price: number; min: number; stock: string; color: string; initials: string; };
const nav: { id: Section; label: string; icon: string }[] = [
  { id: "overview", label: "الرئيسية", icon: "⌂" },
  { id: "products", label: "كتالوج الجملة", icon: "▦" },
  { id: "rfqs", label: "طلبات عروض الأسعار", icon: "▤" },
  { id: "orders", label: "الطلبات", icon: "▣" },
  { id: "suppliers", label: "الموردون", icon: "♧" },
  { id: "businesses", label: "شركاتي والحساب", icon: "◉" },
  { id: "company", label: "لوحة الشركة", icon: "▣" },
];
const money = (v: number) => new Intl.NumberFormat("en-US").format(v) + " د.ع";
type CartLine = { product: Product; quantity: number };

export default function App() {
  const [section, setSection] = useState<Section>("overview");
  const [products, setProducts] = useState<Product[]>([]);
  const [catalogLoading, setCatalogLoading] = useState(true);
  const [search, setSearch] = useState("");
  const [category, setCategory] = useState("الكل");
  const [cart, setCart] = useState<CartLine[]>([]);
  const [notice, setNotice] = useState("");
  const [showAuth, setShowAuth] = useState(false);
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [authBusy, setAuthBusy] = useState(false);
  const [rfqNote, setRfqNote] = useState("");
  const [rfqSent, setRfqSent] = useState(false);
  const [sending, setSending] = useState(false);

  useEffect(() => {
    let active = true;
    if (!supabase) { setCatalogLoading(false); return; }
    getPublicCatalog()
      .then(rows => { if (active) setProducts(rows.map((p: CatalogProduct) => ({
        id: p.id, name: p.name, category: p.category?.name_ar ?? "غير مصنف",
        price: Number(p.price), min: p.min_order_quantity,
        stock: p.stock_quantity > 0 ? "متوفر" : "غير متوفر",
        color: "mint", initials: p.name.slice(0, 5),
      }))); })
      .catch(error => { if (active) setNotice(error instanceof Error ? `تعذر تحميل الكتالوج: ${error.message}` : "تعذر تحميل الكتالوج."); })
      .finally(() => { if (active) setCatalogLoading(false); });
    return () => { active = false; };
  }, []);

  const filtered = useMemo(() => products.filter(p =>
    (p.name + p.category).toLowerCase().includes(search.trim().toLowerCase()) &&
    (category === "الكل" || p.category === category)
  ), [search, category]);
  const cartCount = cart.reduce((sum, line) => sum + line.quantity, 0);
  const cartTotal = cart.reduce((sum, line) => sum + line.quantity * line.product.price, 0);
  const title = nav.find(n => n.id === section)?.label ?? "الرئيسية";

  function addToCart(product: Product) {
    setCart(current => {
      const found = current.find(line => line.product.id === product.id);
      if (found) return current.map(line => line.product.id === product.id ? { ...line, quantity: line.quantity + product.min } : line);
      return [...current, { product, quantity: product.min }];
    });
    setNotice("أُضيف المنتج إلى طلب عرض السعر بالحد الأدنى للطلب.");
  }
  function changeQuantity(id: string, quantity: number) {
    setCart(current => current.map(line => line.product.id === id ? { ...line, quantity: Math.max(line.product.min, quantity || line.product.min) } : line));
  }
  async function signIn() {
    if (!supabase) { setNotice("إعداد الاتصال بقاعدة Supabase غير مكتمل بعد."); return; }
    setAuthBusy(true);
    try {
      await signInWithEmail(email, password);
      setNotice("تم تسجيل الدخول بنجاح.");
    } catch (error) {
      setNotice(error instanceof Error ? error.message : "تعذر تسجيل الدخول.");
    } finally { setAuthBusy(false); }
  }
  async function submitRfq() {
    if (!cart.length) return;
    if (!supabase) {
      setRfqSent(true);
      setNotice("تم تجهيز طلبك محلياً للمعاينة. لن يُحفظ في قاعدة البيانات قبل تفعيل الاتصال وتسجيل الدخول.");
      return;
    }
    setSending(true);
    // RFQ persistence will be enabled after mapping the live database schema and buyer business membership.
    setSending(false);
    setRfqSent(true);
    setNotice("تم تجهيز الطلب. يلزم ربط حساب المشتري بملف المنشأة قبل الإرسال النهائي.");
  }

  return <div className="app-shell" dir="rtl">
    <aside className="sidebar">
      <div className="brand"><div className="brand-mark">ت</div><div><b>تاجر</b><small>سوق الجملة العراقي</small></div></div>
      <div className="workspace-label">مساحة العمل</div>
      <nav>{nav.map(item => <button key={item.id} className={section === item.id ? "nav-item active" : "nav-item"} onClick={() => setSection(item.id)}><span className="nav-icon">{item.icon}</span>{item.label}{item.id === "rfqs" && cartCount > 0 && <i className="nav-count">{cartCount}</i>}</button>)}</nav>
      <div className="sidebar-bottom"><div className="help-card"><span>هل تحتاج إلى مساعدة؟</span><small>منصة تربط التجار بالموردين</small><button onClick={() => setNotice("سيتم تفعيل مركز المساعدة في مرحلة لاحقة.")}>مركز المساعدة ←</button></div><div className="profile"><div className="avatar">ت</div><div><b>زائر المنصة</b><small>تصفح الكتالوج</small></div><span className="dots">•••</span></div></div>
    </aside>
    <main className="main">
      <header className="topbar"><div className="crumb">تاجر <span>/</span> {title}</div><div className="top-actions"><span className={isSupabaseConfigured ? "connection on" : "connection"}><i/> {isSupabaseConfigured ? "إعداد الاتصال متوفر" : "وضع العرض الأولي"}</span><button className="icon-btn" onClick={() => setSection("rfqs")}>السلة {cartCount ? `(${cartCount})` : ""}</button><button className="user-chip" onClick={() => setShowAuth(v => !v)}>تسجيل الدخول</button></div></header>
      <div className="content">
        <div className="welcome-row"><div><div className="eyebrow">منصة التجارة بين الشركات B2B · العراق</div><h1>{section === "overview" ? "سوق الجملة، أقرب إليك" : title}</h1><p>اكتشف الموردين، قارن أسعار الجملة، وأرسل طلبات الشراء من مكان واحد.</p></div><button className="primary" onClick={() => setSection("products")}>تصفح المنتجات ←</button></div>
        {notice && <div className="notice"><span>ⓘ</span><p>{notice}</p><button onClick={() => setNotice("")}>×</button></div>}
        {showAuth && <section className="auth-panel"><div><b>الدخول إلى حسابك</b><p>تسجيل الدخول الآمن عبر Supabase.</p></div><input type="email" placeholder="البريد الإلكتروني" value={email} onChange={e => setEmail(e.target.value)} /><input type="password" placeholder="كلمة المرور" value={password} onChange={e => setPassword(e.target.value)} /><button className="primary" disabled={authBusy} onClick={signIn}>{authBusy ? "جارٍ الدخول..." : "دخول"}</button></section>}
        {section === "overview" && <>
          {catalogLoading && <div className="notice">جارٍ تحميل المنتجات الحقيقية من قاعدة البيانات...</div>}
          {!catalogLoading && products.length === 0 && <div className="notice">لا توجد منتجات منشورة من موردين معتمدين حالياً. أضف أول مورد ومنتجاته لعرضها هنا.</div>}
          <div className="stat-grid">
            <Stat label="منتجات في الكتالوج" value={String(products.length).padStart(2, "0")} delta="بيانات حقيقية من قاعدة البيانات" icon="▦" />
            <Stat label="منتجات في طلبك" value={String(cart.length)} delta={`${cartCount} قطعة إجمالاً`} icon="▤" />
            <Stat label="قيمة الطلب التقديرية" value={money(cartTotal)} delta="قبل تأكيد سعر المورد" icon="▣" />
            <Stat label="طريقة الشراء" value="جملة" delta="الحد الأدنى يختلف حسب المنتج" icon="♧" />
          </div>
          <div className="section-heading"><div><h2>منتجات مختارة</h2><p>ابدأ باختيار المنتجات التي تريد شراءها بالجملة</p></div><button className="text-btn" onClick={() => setSection("products")}>عرض الكتالوج ←</button></div>
          <ProductGrid items={products.slice(0, 3)} onAdd={addToCart} />
          <div className="lower-grid"><div className="panel"><div className="panel-head"><h3>كيف يعمل تاجر؟</h3><span className="muted">3 خطوات</span></div><Activity title="1. اكتشف المنتجات" sub="ابحث في كتالوج الموردين وقارن الخيارات." time="01" /><Activity title="2. أرسل طلب عرض سعر" sub="حدد الكميات وأضف ملاحظاتك للمورد." time="02" /><Activity title="3. تفاوض وأكمل الطلب" sub="راجع عروض الموردين واتفق على التفاصيل." time="03" /></div><div className="panel callout"><div className="callout-icon">✦</div><h3>هل أنت مورّد؟</h3><p>جهّز ملف شركتك وأضف منتجاتك للوصول إلى تجار الجملة في العراق.</p><button className="outline" onClick={() => setSection("suppliers")}>ملف الموردين</button></div></div>
        </>}
        {section === "products" && <RfqWorkspace mode="catalog" />}
        {section === "rfqs" && <RfqWorkspace mode="dashboard" />}
        {section === "businesses" && <AccountCenter />}
        {section === "company" && <CompanyDashboard />}
        {section === "orders" && <Empty title="إدارة الطلبات" desc="ستظهر هنا الطلبات المؤكدة وحالات التجهيز والتسليم بعد تفعيل دورة الطلب." />}
        {section === "suppliers" && <Empty title="بوابة الموردين" desc="سيتمكن المورد من إنشاء ملف شركته وإضافة المنتجات وإدارة عروض الأسعار." action={() => setNotice("تسجيل الموردين قيد التنفيذ ضمن المرحلة التالية.")} />}
        <footer>© 2026 تاجر · منصة التجارة بالجملة في العراق <span>نسخة تطوير أولية</span></footer>
      </div>
    </main>
  </div>;
}
function Stat({ label, value, delta, icon }: { label: string; value: string; delta: string; icon: string }) { return <div className="stat-card"><div className="stat-top"><span>{label}</span><i>{icon}</i></div><strong>{value}</strong><small>{delta}</small></div>; }
function ProductGrid({ items, onAdd }: { items: Product[]; onAdd: (p: Product) => void }) { return <div className="product-grid">{items.length ? items.map(p => <article className="product-card" key={p.id}><div className={`product-art ${p.color}`}><span>{p.initials}</span><small>صورة توضيحية</small></div><div className="product-info"><small>{p.category}</small><h3>{p.name}</h3><div className="product-price">{money(p.price)} <span>/ للقطعة · تقديري</span></div><div className="product-foot"><span>الحد الأدنى: {p.min} قطعة</span><b className={p.stock === "متوفر" ? "in-stock" : "low-stock"}>{p.stock}</b></div><button className="outline" style={{width:"100%",marginTop:12}} onClick={() => onAdd(p)}>＋ أضف لطلب السعر</button></div></article>) : <div className="empty">لا توجد نتائج مطابقة لبحثك.</div>}</div>; }
function Activity({ title, sub, time }: { title: string; sub: string; time: string }) { return <div className="activity"><i/><div><b>{title}</b><small>{sub}</small></div><time>{time}</time></div>; }
function Empty({ title, desc, action }: { title: string; desc: string; action?: () => void }) { return <div className="empty-state"><div>▤</div><h2>{title}</h2><p>{desc}</p>{action && <button className="primary" onClick={action}>تصفح المنتجات</button>}</div>; }
