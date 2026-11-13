import { useEffect, useMemo, useState } from "react";
import { getPublicCatalog, type CatalogProduct } from "../lib/catalog";
import { createRetailOrders } from "../lib/retail-orders";

const money = (value: number) => new Intl.NumberFormat("en-US").format(value) + " د.ع";

type CartLine = { product: CatalogProduct; quantity: number };

export default function RetailCatalog() {
  const [products, setProducts] = useState<CatalogProduct[]>([]);
  const [cart, setCart] = useState<CartLine[]>([]);
  const [search, setSearch] = useState("");
  const [loading, setLoading] = useState(true);
  const [message, setMessage] = useState("");
  const [deliveryAddress, setDeliveryAddress] = useState("");
  const [checkoutBusy, setCheckoutBusy] = useState(false);

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

  async function checkout() {
    setCheckoutBusy(true); setMessage("");
    try {
      const orders = await createRetailOrders(cart.map(line => ({ product_id: line.product.id, quantity: line.quantity })), deliveryAddress);
      setCart([]); setDeliveryAddress("");
      setMessage(`تم إنشاء ${orders.length} طلب مفرد بنجاح. يمكنك متابعة الطلبات من قسم الطلبات.`);
    } catch (error) { setMessage(error instanceof Error ? error.message : "تعذر إتمام طلب المفرد."); }
    finally { setCheckoutBusy(false); }
  }

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
    <div className="retail-checkout-note">
      <b>إتمام طلب المفرد · B2C</b>
      {cart.length === 0 ? <span>أضف المنتجات إلى السلة لبدء الطلب المباشر. لا يدخل هذا المسار في RFQ أو MOQ الجملة.</span> : <>
        <div className="retail-cart-lines">{cart.map(line => <div className="retail-cart-line" key={line.product.id}>
          <span>{line.product.name} · {money(Number(line.product.retail_price))}</span>
          <div><button className="outline" aria-label="تقليل الكمية" onClick={() => setCart(current => current.flatMap(item => item.product.id !== line.product.id ? [item] : item.quantity <= 1 ? [] : [{...item,quantity:item.quantity-1}]))}>−</button>
          <b>{line.quantity}</b>
          <button className="outline" aria-label="زيادة الكمية" disabled={line.quantity >= line.product.stock_quantity} onClick={() => add(line.product)}>＋</button></div>
        </div>)}</div>
        <label>عنوان التوصيل<input value={deliveryAddress} onChange={e => setDeliveryAddress(e.target.value)} placeholder="المحافظة، المنطقة، الشارع، أقرب نقطة دالة" /></label>
        <div><b>الإجمالي: {money(total)}</b></div>
        <button className="primary" disabled={checkoutBusy || deliveryAddress.trim().length < 8} onClick={() => void checkout()}>{checkoutBusy ? "جارٍ إنشاء الطلب..." : "تأكيد طلب المفرد"}</button>
        <small>يتطلب تسجيل الدخول. تُثبت الأسعار والمخزون داخل قاعدة البيانات، وتُقسّم السلة تلقائياً إلى طلب مستقل لكل مورد.</small>
      </>}
    </div>
  </section>;
}
