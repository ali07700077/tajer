import { useEffect, useMemo, useState } from "react";
import { getMyBusinesses, type BusinessSummary } from "../lib/businesses";
import { supabase } from "../lib/supabase";
import { createWholesaleOrders, requestProductSample, type WholesaleCartItem } from "../lib/wholesale-orders";

type WholesaleProduct = {
  id: string;
  business_id: string;
  name: string;
  description: string | null;
  price: number;
  min_order_quantity: number;
  stock_quantity: number;
  available_quantity: number;
  sample_available: boolean;
  sample_price: number | null;
  sample_max_quantity: number;
  tiers: { id: string; min_quantity: number; unit_price: number }[];
};
type CartLine = { product: WholesaleProduct; quantity: number };
const money = (value: number) => new Intl.NumberFormat("en-US").format(value) + " د.ع";
const client = () => { if (!supabase) throw new Error("اتصال قاعدة البيانات غير مضبوط."); return supabase; };

function unitPrice(product: WholesaleProduct, quantity: number) {
  return [...product.tiers]
    .filter(tier => tier.min_quantity <= quantity)
    .sort((a, b) => b.min_quantity - a.min_quantity)[0]?.unit_price ?? product.price;
}

export default function WholesaleCheckout() {
  const [products, setProducts] = useState<WholesaleProduct[]>([]);
  const [buyers, setBuyers] = useState<BusinessSummary[]>([]);
  const [buyerId, setBuyerId] = useState("");
  const [cart, setCart] = useState<CartLine[]>([]);
  const [address, setAddress] = useState("");
  const [search, setSearch] = useState("");
  const [loading, setLoading] = useState(true);
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState("");
  const [createdOrders, setCreatedOrders] = useState<{order_id:string;supplier_business_id:string;total_amount:number}[]>([]);

  useEffect(() => {
    let alive = true;
    (async () => {
      try {
        const db = client();
        const [{ data: sessionData, error: sessionError }, businesses, { data, error }] = await Promise.all([
          db.auth.getSession(),
          getMyBusinesses(),
          db.from("products")
            .select("id,business_id,name,description,price,min_order_quantity,stock_quantity,available_quantity,sample_available,sample_price,sample_max_quantity,tiers:product_price_tiers(id,min_quantity,unit_price)")
            .eq("is_active", true)
            .order("created_at", { ascending: false }),
        ]);
        if (sessionError) throw sessionError;
        if (error) throw error;
        if (!alive) return;
        setBuyers(businesses.filter(item => item.business_type === "buyer"));
        setBuyerId(businesses.find(item => item.business_type === "buyer")?.id ?? "");
        setProducts((data ?? []) as unknown as WholesaleProduct[]);
        if (!sessionData.session) setMessage("سجّل الدخول ثم اختر ملف شركة مشتري لإتمام طلب الجملة.");
      } catch (error) {
        if (alive) setMessage(error instanceof Error ? error.message : "تعذر تحميل سلة الجملة.");
      } finally {
        if (alive) setLoading(false);
      }
    })();
    return () => { alive = false; };
  }, []);

  const visible = useMemo(() => products.filter(product =>
    (product.name + " " + (product.description ?? "")).toLowerCase().includes(search.trim().toLowerCase())
  ), [products, search]);
  const totalQuantity = cart.reduce((sum, line) => sum + line.quantity, 0);
  const total = cart.reduce((sum, line) => sum + line.quantity * unitPrice(line.product, line.quantity), 0);

  function add(product: WholesaleProduct) {
    setCart(current => {
      const existing = current.find(line => line.product.id === product.id);
      const nextQuantity = Math.min(product.available_quantity, (existing?.quantity ?? 0) + product.min_order_quantity);
      return existing
        ? current.map(line => line.product.id === product.id ? { ...line, quantity: nextQuantity } : line)
        : [...current, { product, quantity: Math.min(product.min_order_quantity, product.stock_quantity) }];
    });
    setMessage("أُضيف المنتج إلى سلة الجملة. السعر النهائي سيُعاد احتسابه داخل قاعدة البيانات، والكميات تُحجز مؤقتاً عند إنشاء الطلب.");
  }

  function setQuantity(productId: string, raw: string) {
    const quantity = Number(raw);
    setCart(current => current.map(line => line.product.id !== productId ? line : {
      ...line,
      quantity: Number.isSafeInteger(quantity) ? Math.max(1, Math.min(quantity, line.product.available_quantity)) : line.quantity,
    }));
  }

  async function checkout() {
    if (!buyerId) { setMessage("أنشئ أو اختر ملف شركة مشتري أولاً."); return; }
    setBusy(true); setMessage(""); setCreatedOrders([]);
    try {
      const items: WholesaleCartItem[] = cart.map(line => ({ product_id: line.product.id, quantity: line.quantity }));
      const orders = await createWholesaleOrders(buyerId, items, address);
      setCreatedOrders(orders);
      setCart([]);
      setMessage(`تم إنشاء ${orders.length} طلب جملة مستقل، طلب لكل مورد. تم تثبيت الأسعار وحجز الكميات لمدة 15 دقيقة؛ يُخصم المخزون عند تأكيد الدفع.`);
    } catch (error) {
      setMessage(error instanceof Error ? error.message : "تعذر إتمام طلب الجملة.");
    } finally { setBusy(false); }
  }

  async function sample(product: WholesaleProduct) {
    if (!buyerId) { setMessage("اختر ملف شركة مشتري أولاً."); return; }
    if (address.trim().length < 8) { setMessage("أدخل عنوان التوصيل قبل طلب العينة."); return; }
    setBusy(true); setMessage("");
    try {
      const id = await requestProductSample({ buyerBusinessId: buyerId, productId: product.id, quantity: 1, deliveryAddress: address });
      setMessage(`تم إنشاء طلب العينة المدفوعة رقم ${id}. ينتظر تأكيد الدفع قبل التجهيز.`);
    } catch (error) { setMessage(error instanceof Error ? error.message : "تعذر طلب العينة."); }
    finally { setBusy(false); }
  }

  if (loading) return <section className="panel"><p>جارٍ تحميل منتجات الجملة...</p></section>;

  return <section className="wholesale-checkout">
    <div className="retail-intro">
      <div><span className="eyebrow">B2B · Wholesale</span><h2>سلة الجملة متعددة الموردين</h2><p>أضف منتجات من موردين مختلفين؛ يقسم الخادم السلة تلقائياً إلى طلب مستقل لكل مورد.</p></div>
      <div className="retail-cart-summary"><b>السلة</b><strong>{totalQuantity} قطعة</strong><span>{money(total)}</span></div>
    </div>
    {message && <div className="notice"><p>{message}</p></div>}
    {createdOrders.length > 0 && <div className="panel"><b>الطلبات المنشأة</b>{createdOrders.map(order =>
      <div className="retail-cart-line" key={order.order_id}><span>طلب {order.order_id.slice(0,8)} · المورد {order.supplier_business_id.slice(0,8)}</span><b>{money(Number(order.total_amount))}</b></div>
    )}</div>}
    <div className="toolbar">
      <input className="search" placeholder="ابحث في منتجات الجملة..." value={search} onChange={event => setSearch(event.target.value)} />
      <select value={buyerId} onChange={event => setBuyerId(event.target.value)} aria-label="شركة المشتري">
        <option value="">اختر شركة المشتري</option>
        {buyers.map(buyer => <option key={buyer.id} value={buyer.id}>{buyer.name_ar}</option>)}
      </select>
    </div>
    {buyers.length === 0 && <div className="notice">لا يوجد ملف شركة مشتري مرتبط بحسابك. أنشئ ملف مشتري من صفحة «شركاتي والحساب» أولاً.</div>}
    <div className="product-grid">{visible.map(product => <article className="product-card" key={product.id}>
      <div className="product-art mint"><span>▦</span><small>جملة B2B</small></div>
      <div className="product-info"><h3>{product.name}</h3><p>{product.description || "منتج متاح للشراء بالجملة."}</p>
        <div className="product-price">{money(Number(product.price))}<span> / سعر الأساس</span></div>
        <div className="rfq-price-tiers"><small>شرائح الكمية:</small>
          {product.tiers.length ? product.tiers.map(tier => <span key={tier.id}>من {tier.min_quantity}: {money(Number(tier.unit_price))}</span>) : <span>لا توجد شرائح إضافية</span>}
        </div>
        <div className="product-foot"><span>MOQ: {product.min_order_quantity}</span><b>{product.stock_quantity} متوفر</b></div>
        <button className="primary rfq-full" disabled={busy || product.stock_quantity < product.min_order_quantity} onClick={() => add(product)}>＋ أضف إلى سلة الجملة</button>
        {product.sample_available && product.sample_price != null && <button className="outline rfq-full" disabled={busy} onClick={() => void sample(product)}>طلب عينة مدفوعة · {money(Number(product.sample_price))}</button>}
      </div>
    </article>)}</div>
    <div className="retail-checkout-note">
      <b>إتمام طلب الجملة</b>
      {cart.length === 0 ? <span>أضف المنتجات إلى السلة. لا يتم إنشاء طلب قبل التحقق من MOQ والمخزون في قاعدة البيانات.</span> : <>
        {cart.map(line => <div className="retail-cart-line" key={line.product.id}>
          <span>{line.product.name}<small>السعر المحسوب حالياً: {money(Number(unitPrice(line.product,line.quantity)))}/قطعة</small></span>
          <div><input aria-label={`كمية ${line.product.name}`} type="number" min={line.product.min_order_quantity} max={line.product.stock_quantity} value={line.quantity} onChange={event => setQuantity(line.product.id,event.target.value)} /></div>
          <b>{money(line.quantity * unitPrice(line.product,line.quantity))}</b>
          <button className="outline" onClick={() => setCart(current => current.filter(item => item.product.id !== line.product.id))}>حذف</button>
        </div>)}
        <label>عنوان التوصيل<input value={address} onChange={event => setAddress(event.target.value)} placeholder="المحافظة، المنطقة، الشارع، أقرب نقطة دالة" /></label>
        <b>الإجمالي التقديري: {money(total)}</b>
        <button className="primary" disabled={busy || !buyerId || address.trim().length < 8 || cart.some(line => line.quantity < line.product.min_order_quantity || line.quantity > line.product.stock_quantity)} onClick={() => void checkout()}>
          {busy ? "جارٍ إنشاء الطلبات..." : "تأكيد طلب الجملة"}
        </button>
        <small>الأسعار الظاهرة تقديرية فقط؛ قاعدة البيانات تعيد حساب شرائح السعر وتتحقق من MOQ والمخزون قبل إنشاء الطلبات.</small>
      </>}
    </div>
  </section>;
}
