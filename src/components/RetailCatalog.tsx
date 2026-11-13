import { useEffect, useMemo, useState } from "react";
import { getPublicCatalog, type CatalogProduct } from "../lib/catalog";

const money = (value: number) => new Intl.NumberFormat("en-US").format(value) + " د.ع";

type CartLine = { product: CatalogProduct; quantity: number };

export default function RetailCatalog() {
  const [products, setProducts] = useState<CatalogProduct[]>([]);
  const [cart, setCart] = useState<CartLine[]>([]);
  const [search, setSearch] = useState("");
  const [loading, setLoading] = useState(true);
  const [message, setMessage] = useState("");

  useEffect(() => {
    let alive = true;
    getPublicCatalog().then(rows => {
      if (alive) setProducts(rows.filter(p => p.is_retail_available && p.retail_price != null && p.stock_quantity > 0));
    }).catch(error => {
      if (alive) setMessage(error instanceof Error ? error.message : "تعذر تحميل منتجات المفرد.");
    }).finally(() => { if (alive) setLoading(false); });
    return () => { alive = false; };
  }, []);

  const visible = useMemo(() => products.filter(p =>
    (p.name + " " + (p.description ?? "")).toLowerCase().includes(search.trim().toLowerCase())
  ), [products, search]);
  const count = cart.reduce((sum, line) => sum + line.quantity, 0);
  const total = cart.reduce((sum, line) => sum + line.quantity * Number(line.product.retail_price), 0);

  function add(product: CatalogProduct) {
    setCart(current => {
      const line = current.find(item => item.product.id === product.id);
      return line
        ? current.map(item => item.product.id === product.id ? { ...item, quantity: item.quantity + 1 } : item)
        : [...current, { product, quantity: 1 }];
    });
    setMessage("أُضيف المنتج إلى سلة المفرد.");
  }

  return <section className="retail-store">
    <div className="retail-intro">
      <div><span className="eyebrow">B2C · تسوق مباشر</span><h2>تسوق القطعة الواحدة</h2><p>هذه المنتجات أتاحها المورد للبيع بالمفرد. لا حاجة إلى طلب عرض سعر أو حد أدنى للجملة.</p></div>
      <div className="retail-cart-summary"><b>سلة المفرد</b><strong>{count} قطعة</strong><span>{money(total)}</span></div>
    </div>
    <input className="search retail-search" placeholder="ابحث عن منتج متاح بالمفرد..." value={search} onChange={e => setSearch(e.target.value)} />
    {message && <p className="notice">{message}</p>}
    {loading ? <div className="panel">جارٍ تحميل منتجات المفرد...</div> : visible.length === 0 ? <div className="empty-state"><div>🛍</div><h2>لا توجد منتجات مفرد منشورة حالياً</h2><p>عندما يفعّل المورد البيع بالمفرد ويحدد سعر القطعة، سيظهر المنتج هنا.</p></div> :
      <div className="product-grid">{visible.map(product => <article className="product-card" key={product.id}>
        <div className="product-art mint"><span>{product.name.slice(0, 5)}</span><small>متاح للمفرد</small></div>
        <div className="product-info"><small>{product.category?.name_ar ?? "منتج"}</small><h3>{product.name}</h3>
          <div className="product-price">{money(Number(product.retail_price))} <span>/ القطعة</span></div>
          <div className="product-foot"><span>المتوفر: {product.stock_quantity}</span><span className="in-stock">متاح</span></div>
          <button className="primary rfq-full" onClick={() => add(product)}>＋ أضف للسلة</button>
        </div>
      </article>)}</div>}
    <div className="retail-checkout-note"><b>الخطوة التالية في دورة B2C</b><span>السلة الحالية للمعاينة. إنشاء طلب المفرد والدفع والتوصيل يحتاج استكمال تكامل الطلبات والدفع قبل تفعيل الشراء الفعلي.</span></div>
  </section>;
}
