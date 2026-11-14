import { useEffect, useState } from "react";
import { getPublicCatalog, type CatalogProduct } from "./lib/catalog";
import { signInWithEmail } from "./lib/auth";
import { isSupabaseConfigured, supabase } from "./lib/supabase";
import AccountCenter from "./components/AccountCenter";
import CompanyDashboard from "./components/CompanyDashboard";
import RfqWorkspace from "./components/RfqWorkspace";
import RetailCatalog from "./components/RetailCatalog";
import WholesaleCheckout from "./components/WholesaleCheckout";
import HybridCheckout from "./components/HybridCheckout";
import CommercialHub from "./components/CommercialHub";
import RoleSwitcher, { type AppRole } from "./components/RoleSwitcher";
import OrdersWorkspace from "./components/OrdersWorkspace";
import LiveTrackingMap from "./components/LiveTrackingMap";

type Section = "overview" | "products" | "retail" | "wholesale" | "hybrid" | "commercial" | "rfqs" | "orders" | "tracking" | "suppliers" | "businesses" | "company";
type Product = { id: string; name: string; category: string; price: number; min: number; stock: string; color: string; initials: string; isDemo?: boolean; priceUsd?: number | null; supplier?: string; governorate?: string; };
const nav: { id: Section; label: string; icon: string }[] = [
  { id: "overview", label: "الرئيسية", icon: "⌂" },
  { id: "products", label: "كتالوج الجملة", icon: "▦" },
  { id: "retail", label: "تسوق المفرد", icon: "🛍" },
  { id: "wholesale", label: "سلة الجملة", icon: "🛒" },
  { id: "hybrid", label: "سلة موحدة", icon: "🧺" },
  { id: "commercial", label: "الخدمات التجارية", icon: "🏦" },
  { id: "rfqs", label: "طلبات عروض الأسعار", icon: "▤" },
  { id: "orders", label: "الطلبات", icon: "▣" },
  { id: "tracking", label: "تتبع الشحنات", icon: "⌖" },
  { id: "suppliers", label: "الموردون", icon: "♧" },
  { id: "businesses", label: "شركاتي والحساب", icon: "◉" },
  { id: "company", label: "لوحة الشركة", icon: "▣" },
];
const money = (v: number) => new Intl.NumberFormat("en-US").format(v) + " د.ع";
type CartLine = { product: Product; quantity: number };

export default function App() {
  const [section, setSection] = useState<Section>("overview");
  const [activeRole, setActiveRole] = useState<AppRole>("retail_buyer");
  const [activeBusinessId, setActiveBusinessId] = useState<string | null>(null);
  const [products, setProducts] = useState<Product[]>([]);
  const [catalogLoading, setCatalogLoading] = useState(true);
  const [cart, setCart] = useState<CartLine[]>([]);
  const [notice, setNotice] = useState("");
  const [showAuth, setShowAuth] = useState(false);
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [authBusy, setAuthBusy] = useState(false);

  useEffect(() => {
    let active = true;
    if (!supabase) { setCatalogLoading(false); return; }
    getPublicCatalog()
      .then(rows => { if (active) setProducts(rows.map((p: CatalogProduct) => ({
        id: p.id, name: p.name, category: p.category?.name_ar ?? "غير مصنف",
        price: Number(p.price), min: p.min_order_quantity,
        stock: p.stock_quantity > 0 ? "متوفر" : "غير متوفر",
        color: "mint", initials: p.name.slice(0, 5), isDemo: p.is_demo, priceUsd: p.price_usd, supplier: p.supplier_name, governorate: p.governorate_name,
      }))); })
      .catch(error => { if (active) setNotice(error instanceof Error ? `تعذر تحميل الكتالوج: ${error.message}` : "تعذر تحميل الكتالوج."); })
      .finally(() => { if (active) setCatalogLoading(false); });
    return () => { active = false; };
  }, []);

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
  function handleRoleChange(role: AppRole, businessId: string | null) {
    setActiveRole(role);
    setActiveBusinessId(businessId);
    if (role === "retail_buyer") setSection("retail");
    else if (role === "wholesale_buyer") setSection("wholesale");
    else if (role === "supplier") setSection("company");
    else setSection("commercial");
  }

  return <div className="app-shell" dir="rtl" data-active-role={activeRole} data-active-business={activeBusinessId ?? ""}>
    <aside className="sidebar">
      <div className="brand"><div className="brand-mark">ت</div><div><b>تاجر</b><small>سوق الجملة العراقي</small></div></div>
      <div className="workspace-label">مساحة العمل</div>
      <nav>{nav.map(item => <button key={item.id} className={section === item.id ? "nav-item active" : "nav-item"} onClick={() => setSection(item.id)}><span className="nav-icon">{item.icon}</span>{item.label}{item.id === "rfqs" && cartCount > 0 && <i className="nav-count">{cartCount}</i>}</button>)}</nav>
      <div className="sidebar-bottom"><div className="help-card"><span>هل تحتاج إلى مساعدة؟</span><small>منصة تربط التجار بالموردين</small><button onClick={() => setNotice("سيتم تفعيل مركز المساعدة في مرحلة لاحقة.")}>مركز المساعدة ←</button></div><div className="profile"><div className="avatar">ت</div><div><b>زائر المنصة</b><small>تصفح الكتالوج</small></div><span className="dots">•••</span></div></div>
    </aside>
    <main className="main">
      <header className="topbar"><div className="crumb">تاجر <span>/</span> {title}</div><RoleSwitcher onRoleChange={handleRoleChange} /><div className="top-actions"><span className={isSupabaseConfigured ? "connection on" : "connection"}><i/> {isSupabaseConfigured ? "إعداد الاتصال متوفر" : "وضع العرض الأولي"}</span><button className="icon-btn" onClick={() => setSection("wholesale")}>السلة {cartCount ? `(${cartCount})` : ""}</button><button className="user-chip" onClick={() => setShowAuth(v => !v)}>تسجيل الدخول</button></div></header>
      <div className="content">
        <div className="welcome-row"><div><div className="eyebrow">سوق هجين للجملة والمفرد B2B + B2C · العراق</div><h1>{section === "overview" ? "سوق الجملة، أقرب إليك" : title}</h1><p>اكتشف الموردين، اشترِ بالمفرد أو بالجملة، وأرسل طلبات الأسعار من مكان واحد.</p></div><button className="primary" onClick={() => setSection("products")}>تصفح المنتجات ←</button></div>
        {notice && <div className="notice"><span>ⓘ</span><p>{notice}</p><button onClick={() => setNotice("")}>×</button></div>}
        {showAuth && <section className="auth-panel"><div><b>الدخول إلى حسابك</b><p>تسجيل الدخول الآمن عبر Supabase.</p></div><input type="email" placeholder="البريد الإلكتروني" value={email} onChange={e => setEmail(e.target.value)} /><input type="password" placeholder="كلمة المرور" value={password} onChange={e => setPassword(e.target.value)} /><button className="primary" disabled={authBusy} onClick={signIn}>{authBusy ? "جارٍ الدخول..." : "دخول"}</button></section>}
        {section === "overview" && <>
          {catalogLoading && <div className="notice">جارٍ تحميل المنتجات الحقيقية من قاعدة البيانات...</div>}
          {!catalogLoading && products.length === 0 && <div className="notice">لا توجد منتجات من موردين معتمدين بعد. يعرض تاجر الآن كتالوجاً تجريبياً للمعاينة فقط؛ لا يمكن الشراء من بيانات العرض.</div>}
          <div className="stat-grid">
            <Stat label="منتجات في الكتالوج" value={String(products.length).padStart(2, "0")} delta="بيانات حقيقية من قاعدة البيانات" icon="▦" />
            <Stat label="منتجات في طلبك" value={String(cart.length)} delta={`${cartCount} قطعة إجمالاً`} icon="▤" />
            <Stat label="قيمة الطلب التقديرية" value={money(cartTotal)} delta="قبل تأكيد سعر المورد" icon="▣" />
            <Stat label="طريقة الشراء" value="جملة ومفرد" delta="حسب خيارات المنتج" icon="♧" />
          </div>
          <div className="section-heading"><div><h2>منتجات مختارة</h2><p>ابدأ باختيار المنتجات التي تريد شراءها بالجملة</p></div><button className="text-btn" onClick={() => setSection("products")}>عرض الكتالوج ←</button></div>
          <ProductGrid items={products.slice(0, 3)} onAdd={addToCart} />
          <div className="lower-grid"><div className="panel"><div className="panel-head"><h3>كيف يعمل تاجر؟</h3><span className="muted">3 خطوات</span></div><Activity title="1. اكتشف المنتجات" sub="ابحث في كتالوج الموردين وقارن الخيارات." time="01" /><Activity title="2. أرسل طلب عرض سعر" sub="حدد الكميات وأضف ملاحظاتك للمورد." time="02" /><Activity title="3. تفاوض وأكمل الطلب" sub="راجع عروض الموردين واتفق على التفاصيل." time="03" /></div><div className="panel callout"><div className="callout-icon">✦</div><h3>هل أنت مورّد؟</h3><p>جهّز ملف شركتك وأضف منتجاتك للوصول إلى تجار الجملة في العراق.</p><button className="outline" onClick={() => setSection("suppliers")}>ملف الموردين</button></div></div>
        </>}
        {section === "products" && <RfqWorkspace mode="catalog" />}
        {section === "retail" && <RetailCatalog />}
        {section === "wholesale" && <WholesaleCheckout />}
        {section === "hybrid" && <HybridCheckout />}
        {section === "commercial" && <CommercialHub />}
        {section === "rfqs" && <RfqWorkspace mode="dashboard" />}
        {section === "businesses" && <AccountCenter />}
        {section === "company" && <CompanyDashboard />}
        {section === "tracking" && <LiveTrackingMap />}
        {section === "orders" && <OrdersWorkspace businessId={activeBusinessId} onOpenRfq={() => setSection("rfqs")} onReorder={() => { setSection("products"); setNotice("اختر المنتجات والكميات لإنشاء طلب جديد؛ إعادة إنشاء الطلب السابق آلياً ستضاف بعد ربط دورة الطلب بالمخزون والحجوزات."); }} />}
        {section === "suppliers" && <Empty title="بوابة الموردين" desc="سيتمكن المورد من إنشاء ملف شركته وإضافة المنتجات وإدارة عروض الأسعار." action={() => setNotice("تسجيل الموردين قيد التنفيذ ضمن المرحلة التالية.")} />}
        <footer>© 2026 تاجر · منصة التجارة بالجملة في العراق <span>كتالوج العرض تجريبي — لا يمثل عروضاً أو مخزوناً مؤكداً</span></footer>
      </div>
    </main>
  </div>;
}
function Stat({ label, value, delta, icon }: { label: string; value: string; delta: string; icon: string }) { return <div className="stat-card"><div className="stat-top"><span>{label}</span><i>{icon}</i></div><strong>{value}</strong><small>{delta}</small></div>; }
function ProductGrid({ items, onAdd }: { items: Product[]; onAdd: (p: Product) => void }) { return <div className="product-grid">{items.length ? items.map(p => <article className="product-card" key={p.id}><div className={`product-art ${p.color}`}><span>{p.initials}</span><small>صورة توضيحية</small></div><div className="product-info"><small>{p.category}</small><h3>{p.name}</h3><div className="product-price">{money(p.price)} <span>/ للقطعة {p.isDemo ? `· ≈ ${Number(p.priceUsd ?? p.price / 1520).toFixed(2)} عرض تجريبي` : "· تقديري"}</span></div>{p.isDemo && <small>مورد عرض: {p.supplier} · {p.governorate}</small> }<div className="product-foot"><span>الحد الأدنى: {p.min} قطعة</span><b className={p.stock === "متوفر" ? "in-stock" : "low-stock"}>{p.stock}</b></div><button className="outline" style={{width:"100%",marginTop:12}} onClick={() => onAdd(p)}>＋ أضف للسلة التجريبية</button></div></article>) : <div className="empty">لا توجد نتائج مطابقة لبحثك.</div>}</div>; }
function Activity({ title, sub, time }: { title: string; sub: string; time: string }) { return <div className="activity"><i/><div><b>{title}</b><small>{sub}</small></div><time>{time}</time></div>; }
function Empty({ title, desc, action }: { title: string; desc: string; action?: () => void }) { return <div className="empty-state"><div>▤</div><h2>{title}</h2><p>{desc}</p>{action && <button className="primary" onClick={action}>تصفح المنتجات</button>}</div>; }

function DemoSuppliers({ onBrowse }: { onBrowse: () => void }) {
  const [rows, setRows] = useState<{supplier_name:string;governorate_name:string;count:number}[]>([]);
  const [loading,setLoading] = useState(true);
  useEffect(() => {
    let alive=true;
    async function load(){
      if(!supabase){setLoading(false);return;}
      const {data,error}=await (supabase as any).from("catalog_demo_products").select("supplier_name,governorate_name");
      if(alive&&!error){
        const grouped=new Map<string,{supplier_name:string;governorate_name:string;count:number}>();
        for(const row of data??[]){
          const key=row.supplier_name;
          const item=grouped.get(key)??{supplier_name:row.supplier_name,governorate_name:row.governorate_name,count:0};
          item.count++;grouped.set(key,item);
        }
        setRows(Array.from(grouped.values()).sort((a,b)=>a.governorate_name.localeCompare(b.governorate_name,"ar")));
      }
      if(alive)setLoading(false);
    }
    void load();return()=>{alive=false;};
  },[]);
  return <section className="panel">
    <div className="panel-head"><div><h2>دليل الموردين التجريبي</h2><p>نماذج عرض تغطي المحافظات — ليست شركات حقيقية أو جهات معتمدة.</p></div><span className="muted">{rows.length} نموذج</span></div>
    {loading?<p>جارٍ تحميل الدليل...</p>:<div className="product-grid">{rows.map(row=><article className="product-card" key={row.supplier_name}><div className="product-info"><small>{row.governorate_name}</small><h3>{row.supplier_name}</h3><div className="product-foot"><span>{row.count} منتجات عرض</span><b className="low-stock">غير معتمد</b></div></div></article>)}</div>}
    <p className="notice">لا توجد بيانات تسجيل أو تحقق تجاري حقيقية. اعتماد المورد يتطلب مستنداته ومراجعة إدارية.</p>
    <button className="primary" onClick={onBrowse}>تصفح كتالوج العرض</button>
  </section>;
}
