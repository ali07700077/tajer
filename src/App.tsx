import { useMemo, useState } from "react";
import { isSupabaseConfigured, supabase } from "./lib/supabase";

type Section = "overview" | "products" | "rfqs" | "orders" | "suppliers";
const nav: { id: Section; label: string; icon: string }[] = [
  { id: "overview", label: "الرئيسية", icon: "⌂" },
  { id: "products", label: "المنتجات والمستودع", icon: "▦" },
  { id: "rfqs", label: "طلبات عروض الأسعار", icon: "▤" },
  { id: "orders", label: "الطلبات", icon: "▣" },
  { id: "suppliers", label: "الموردون", icon: "♧" },
];
const products = [
  { name: "سماعات لاسلكية TWS", category: "إلكترونيات", price: "8,500", min: "20 قطعة", stock: "متوفر", color: "lavender", initials: "TW" },
  { name: "شاحن سريع 25W", category: "إكسسوارات الهاتف", price: "4,250", min: "50 قطعة", stock: "متوفر", color: "mint", initials: "25W" },
  { name: "حافظة هاتف سيليكون", category: "إكسسوارات الهاتف", price: "1,200", min: "100 قطعة", stock: "محدود", color: "sand", initials: "CASE" },
  { name: "ساعة ذكية رياضية", category: "أجهزة ذكية", price: "17,000", min: "10 قطع", stock: "متوفر", color: "blue", initials: "SW" },
];
const money = (v: string) => `${v} د.ع`;

export default function App() {
  const [section, setSection] = useState<Section>("overview");
  const [search, setSearch] = useState("");
  const [notice, setNotice] = useState("هذه نسخة تأسيسية للواجهة؛ بيانات المنتجات المعروضة تجريبية لحين ربط الاستعلامات الفعلية.");
  const [showAuth, setShowAuth] = useState(false);
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [authBusy, setAuthBusy] = useState(false);
  const filtered = useMemo(() => products.filter(p => (p.name + p.category).includes(search.trim())), [search]);

  async function signIn() {
    if (!supabase) { setNotice("أضف إعدادات Supabase إلى متغيرات البيئة أولاً."); return; }
    setAuthBusy(true);
    const { error } = await supabase.auth.signInWithPassword({ email, password });
    setAuthBusy(false);
    setNotice(error ? error.message : "تم تسجيل الدخول بنجاح.");
  }
  const title = nav.find(n => n.id === section)?.label ?? "الرئيسية";

  return <div className="app-shell" dir="rtl">
    <aside className="sidebar">
      <div className="brand"><div className="brand-mark">ت</div><div><b>تاجر</b><small>سوق الجملة العراقي</small></div></div>
      <div className="workspace-label">مساحة العمل</div>
      <nav>{nav.map(item => <button key={item.id} className={section === item.id ? "nav-item active" : "nav-item"} onClick={() => setSection(item.id)}><span className="nav-icon">{item.icon}</span>{item.label}{item.id === "rfqs" && <i className="nav-count">3</i>}</button>)}</nav>
      <div className="sidebar-bottom"><div className="help-card"><span>هل تحتاج إلى مساعدة؟</span><small>فريق تاجر معك خطوة بخطوة</small><button onClick={() => setNotice("سيتم تفعيل مركز المساعدة في مرحلة لاحقة.")}>مركز المساعدة ←</button></div><div className="profile"><div className="avatar">ع</div><div><b>حساب تجريبي</b><small>مدير المتجر</small></div><span className="dots">•••</span></div></div>
    </aside>
    <main className="main">
      <header className="topbar"><div className="crumb">تاجر <span>/</span> {title}</div><div className="top-actions"><span className={isSupabaseConfigured ? "connection on" : "connection"}><i/> {isSupabaseConfigured ? "إعداد الاتصال متوفر" : "بانتظار إعداد قاعدة البيانات"}</span><button className="icon-btn" aria-label="الإشعارات">♧</button><button className="user-chip" onClick={() => setShowAuth(v => !v)}>تسجيل الدخول</button></div></header>
      <div className="content">
        <div className="welcome-row"><div><div className="eyebrow">منصة التجارة بين الشركات B2B</div><h1>{section === "overview" ? "مرحباً بك في تاجر" : title}</h1><p>كل تجارة الجملة، في مكان واحد.</p></div><button className="primary" onClick={() => setNotice("سيتم فتح نموذج إضافة المنتج بعد إكمال ربط قاعدة البيانات.")}>＋ إضافة منتج</button></div>
        {notice && <div className="notice"><span>ⓘ</span><p>{notice}</p><button onClick={() => setNotice("")}>×</button></div>}
        {showAuth && <section className="auth-panel"><div><b>الدخول إلى حسابك</b><p>تسجيل الدخول مرتبط بـ Supabase عند إعداد مفاتيح المشروع.</p></div><input type="email" placeholder="البريد الإلكتروني" value={email} onChange={e=>setEmail(e.target.value)} /><input type="password" placeholder="كلمة المرور" value={password} onChange={e=>setPassword(e.target.value)} /><button className="primary" disabled={authBusy} onClick={signIn}>{authBusy ? "جارٍ الدخول..." : "دخول"}</button></section>}
        {section === "overview" && <>
          <div className="stat-grid">
            <Stat label="إجمالي المنتجات" value="128" delta="في الكتالوج" icon="▦" />
            <Stat label="طلبات عروض الأسعار" value="24" delta="8 بانتظار الرد" icon="▤" />
            <Stat label="الطلبات النشطة" value="16" delta="تحت المعالجة" icon="▣" />
            <Stat label="الموردون" value="42" delta="مورد مسجل" icon="♧" />
          </div>
          <div className="section-heading"><div><h2>أحدث المنتجات</h2><p>استكشف المنتجات المتاحة بالجملة</p></div><button className="text-btn" onClick={()=>setSection("products")}>عرض كل المنتجات ←</button></div>
          <ProductGrid items={products.slice(0,3)} />
          <div className="lower-grid"><div className="panel"><div className="panel-head"><h3>آخر النشاطات</h3><span className="muted">هذا الأسبوع</span></div><Activity title="تم تسجيل مورد جديد" sub="شركة النور للتجارة" time="قبل ساعتين" /><Activity title="طلب عرض سعر جديد" sub="مواد وإكسسوارات هاتف" time="قبل 5 ساعات" /><Activity title="تم تحديث كتالوج المنتجات" sub="12 منتجاً" time="أمس" /></div><div className="panel callout"><div className="callout-icon">✦</div><h3>وسّع تجارتك مع تاجر</h3><p>اعرض منتجاتك بالجملة، واستقبل طلبات التجار، ونظّم أعمالك من لوحة واحدة.</p><button className="outline" onClick={()=>setSection("products")}>استكشف الكتالوج</button></div></div>
        </>}
        {section === "products" && <><div className="toolbar"><input className="search" placeholder="ابحث عن منتج أو تصنيف..." value={search} onChange={e=>setSearch(e.target.value)} /><select aria-label="التصنيف"><option>كل التصنيفات</option><option>إلكترونيات</option><option>إكسسوارات الهاتف</option></select><button className="outline" onClick={()=>setNotice("سيتم تفعيل الفلاتر المتقدمة بعد ربط بيانات المستودع.")}>تصفية</button></div><ProductGrid items={filtered} /></>}
        {section === "rfqs" && <Empty title="طلبات عروض الأسعار" desc="ستظهر هنا طلبات الشراء وعروض الموردين بعد ربط العمليات بقاعدة البيانات." />}
        {section === "orders" && <Empty title="إدارة الطلبات" desc="تابع الطلبات وحالات التجهيز والتسليم من مكان واحد." />}
        {section === "suppliers" && <Empty title="دليل الموردين" desc="ملفات الموردين والتحقق التجاري والتقييمات ستظهر هنا." />}
        <footer>© 2026 تاجر · منصة التجارة بالجملة في العراق <span>نسخة تطوير أولية</span></footer>
      </div>
    </main>
  </div>;
}
function Stat({label,value,delta,icon}:{label:string;value:string;delta:string;icon:string}) { return <div className="stat-card"><div className="stat-top"><span>{label}</span><i>{icon}</i></div><strong>{value}</strong><small>{delta}</small></div>; }
function ProductGrid({items}:{items:typeof products}) { return <div className="product-grid">{items.length ? items.map(p=><article className="product-card" key={p.name}><div className={`product-art ${p.color}`}><span>{p.initials}</span><small>صورة المنتج</small></div><div className="product-info"><small>{p.category}</small><h3>{p.name}</h3><div className="product-price">{money(p.price)} <span>/ للقطعة</span></div><div className="product-foot"><span>الحد الأدنى: {p.min}</span><b className={p.stock === "متوفر" ? "in-stock" : "low-stock"}>{p.stock}</b></div></div></article>) : <div className="empty">لا توجد نتائج مطابقة لبحثك.</div>}</div>; }
function Activity({title,sub,time}:{title:string;sub:string;time:string}) { return <div className="activity"><i/><div><b>{title}</b><small>{sub}</small></div><time>{time}</time></div>; }
function Empty({title,desc}:{title:string;desc:string}) { return <div className="empty-state"><div>▤</div><h2>{title}</h2><p>{desc}</p><span>هذه الوحدة ضمن مراحل التنفيذ التالية</span></div>; }
