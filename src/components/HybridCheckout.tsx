import { useEffect, useMemo, useState } from "react";
import { getMyBusinesses, type BusinessSummary } from "../lib/businesses";
import { getPublicCatalog, type CatalogProduct } from "../lib/catalog";
import { createHybridCheckout, type HybridCheckoutResult } from "../lib/hybrid-checkout";
import { supabase } from "../lib/supabase";

type Mode = "b2c" | "b2b";
type Product = CatalogProduct & { tiers: { id: string; min_quantity: number; unit_price: number }[] };
type CartLine = { product: Product; mode: Mode; quantity: number };
const money = (value: number) => new Intl.NumberFormat("en-US").format(value) + " د.ع";

function wholesaleUnitPrice(product: Product, quantity: number) {
  return [...product.tiers]
    .filter(tier => tier.min_quantity <= quantity)
    .sort((a, b) => b.min_quantity - a.min_quantity)[0]?.unit_price ?? product.price;
}

function lineUnitPrice(line: CartLine) {
  return line.mode === "b2c" ? Number(line.product.retail_price) : wholesaleUnitPrice(line.product, line.quantity);
}

export default function HybridCheckout() {
  const [products, setProducts] = useState<Product[]>([]);
  const [buyers, setBuyers] = useState<BusinessSummary[]>([]);
  const [buyerId, setBuyerId] = useState("");
  const [cart, setCart] = useState<CartLine[]>([]);
  const [search, setSearch] = useState("");
  const [address, setAddress] = useState("");
  const [loading, setLoading] = useState(true);
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState("");
  const [result, setResult] = useState<HybridCheckoutResult | null>(null);

  useEffect(() => {
    let active = true;
    async function load() {
      try {
        const [catalog, businesses] = await Promise.all([getPublicCatalog(), getMyBusinesses()]);
        let tiers: { id: string; product_id: string; min_quantity: number; unit_price: number }[] = [];
        if (supabase && catalog.length) {
          const { data, error } = await supabase
            .from("product_price_tiers")
            .select("id,product_id,min_quantity,unit_price")
            .in("product_id", catalog.map(product => product.id));
          if (error) throw error;
          tiers = data ?? [];
        }
        if (!active) return;
        setProducts(catalog.map(product => ({
          ...product,
          tiers: tiers.filter(tier => tier.product_id === product.id).map(({ id, min_quantity, unit_price }) => ({ id, min_quantity, unit_price })),
        })));
        const buyerBusinesses = businesses.filter(item => item.business_type === "buyer");
        setBuyers(buyerBusinesses);
        setBuyerId(buyerBusinesses[0]?.id ?? "");
      } catch (error) {
        if (active) setMessage(error instanceof Error ? error.message : "تعذر تحميل بيانات سلة الشراء.");
      } finally {
        if (active) setLoading(false);
      }
    }
    void load();
    return () => { active = false; };
  }, []);

  const visible = useMemo(() => products.filter(product =>
    (product.name + " " + (product.description ?? "")).toLowerCase().includes(search.trim().toLowerCase())
  ), [products, search]);
  const retailLines = cart.filter(line => line.mode === "b2c");
  const wholesaleLines = cart.filter(line => line.mode === "b2b");
  const quantity = cart.reduce((sum, line) => sum + line.quantity, 0);
  const total = cart.reduce((sum, line) => sum + line.quantity * lineUnitPrice(line), 0);

  function add(product: Product, mode: Mode) {
    if (mode === "b2c" && (!product.is_retail_available || product.retail_price == null)) return;
    setCart(current => {
      const existing = current.find(line => line.product.id === product.id && line.mode === mode);
      const minimum = mode === "b2b" ? product.min_order_quantity : 1;
      const next = existing ? existing.quantity + 1 : minimum;
      const safeQuantity = Math.min(next, product.available_quantity);
      if (existing) return current.map(line => line.product.id === product.id && line.mode === mode ? { ...line, quantity: Math.max(minimum, safeQuantity) } : line);
      if (current.some(line => line.product.id === product.id && line.mode !== mode)) {
        setMessage("لا يمكن وضع المنتج نفسه في مساري المفرد والجملة ضمن عملية شراء واحدة.");
        return current;
      }
      return [...current, { product, mode, quantity: safeQuantity }];
    });
    setResult(null);
    setMessage(mode === "b2c" ? "أُضيف المنتج إلى مسار المفرد." : "أُضيف المنتج إلى مسار الجملة بالحد الأدنى للطلب.");
  }

  function changeQuantity(line: CartLine, raw: string) {
    const next = Number(raw);
    const minimum = line.mode === "b2b" ? line.product.min_order_quantity : 1;
    if (!Number.isSafeInteger(next) || next < minimum || next > line.product.available_quantity) return;
    setCart(current => current.map(item => item.product.id === line.product.id && item.mode === line.mode ? { ...item, quantity: next } : item));
    setResult(null);
  }

  async function checkout() {
    setBusy(true);
    setMessage("");
    setResult(null);
    try {
      const created = await createHybridCheckout({
        buyerBusinessId: buyerId || null,
        retailItems: retailLines.map(line => ({ product_id: line.product.id, quantity: line.quantity })),
        wholesaleItems: wholesaleLines.map(line => ({ product_id: line.product.id, quantity: line.quantity })),
        deliveryAddress: address,
      });
      setResult(created);
      setCart([]);
      setAddress("");
      setMessage("تم إنشاء عملية الشراء الرئيسية وربط جميع طلبات الموردين بها. حُجز المخزون مؤقتاً لمدة 15 دقيقة بانتظار الدفع.");
    } catch (error) {
      setMessage(error instanceof Error ? error.message : "تعذر إتمام عملية الشراء الموحدة.");
    } finally {
      setBusy(false);
    }
  }

  if (loading) return <section className="panel"><p>جارٍ تحميل كتالوج الشراء الموحد...</p></section>;

  return <section className="wholesale-checkout">
    <div className="retail-intro">
      <div><span className="eyebrow">TAJER · Unified Checkout</span><h2>سلة شراء موحدة للمفرد والجملة</h2><p>اجمع مشتريات المفرد والجملة في عملية واحدة؛ تنشئ قاعدة البيانات طلباً فرعياً لكل مورد وتربطها بمعرّف دفع رئيسي.</p></div>
      <div className="retail-cart-summary"><b>السلة الموحدة</b><strong>{quantity} قطعة</strong><span>{money(total)}</span><small>{retailLines.length} مفرد · {wholesaleLines.length} جملة</small></div>
    </div>
    {message && <div className="notice"><p>{message}</p></div>}
    {result && <div className="panel">
      <b>عملية الشراء الرئيسية: {result.checkout_session_id}</b>
      <div className="retail-cart-line"><span>الحالة: {result.status} · تنتهي صلاحية الحجز: {new Date(result.expires_at).toLocaleString("ar-IQ")}</span><strong>{money(Number(result.total_amount))}</strong></div>
      <div className="retail-cart-line"><span>طلبات المفرد: {result.retail_orders.length}</span><span>طلبات الجملة: {result.wholesale_orders.length}</span></div>
      {[...result.retail_orders, ...result.wholesale_orders].map(order => <div className="retail-cart-line" key={order.order_id}><span>طلب مورد {order.supplier_business_id.slice(0, 8)} · {order.order_id.slice(0, 8)}</span><b>{money(Number(order.total_amount))}</b></div>)}
    </div>}
    <div className="toolbar">
      <input className="search" placeholder="ابحث في جميع المنتجات..." value={search} onChange={event => setSearch(event.target.value)} />
      <select value={buyerId} onChange={event => setBuyerId(event.target.value)} aria-label="شركة المشتري">
        <option value="">شراء المفرد فقط / لا توجد شركة</option>
        {buyers.map(buyer => <option key={buyer.id} value={buyer.id}>{buyer.name_ar}</option>)}
      </select>
    </div>
    {visible.length === 0 ? <div className="empty-state"><h2>لا توجد منتجات متاحة</h2><p>تحقق من اعتماد الموردين ونشر المنتجات في الكتالوج.</p></div> :
      <div className="product-grid">{visible.map(product => <article className="product-card" key={product.id}>
        <div className="product-art mint"><span>{product.name.slice(0, 5)}</span><small>كتالوج TAJER</small></div>
        <div className="product-info"><h3>{product.name}</h3><p>{product.description || "منتج من مورد معتمد."}</p>
          <div className="product-price">جملة: {money(Number(product.price))}<span> · MOQ {product.min_order_quantity}</span></div>
          <div className="rfq-price-tiers"><small>شرائح الجملة:</small>{product.tiers.length ? product.tiers.map(tier => <span key={tier.id}>من {tier.min_quantity}: {money(Number(tier.unit_price))}</span>) : <span>سعر الأساس</span>}</div>
          {product.is_retail_available && product.retail_price != null && <div className="product-price">مفرد: {money(Number(product.retail_price))}<span> / القطعة</span></div>}
          <div className="product-foot"><span>المتاح: {product.available_quantity}</span><b className={product.available_quantity > 0 ? "in-stock" : "low-stock"}>{product.available_quantity > 0 ? "متوفر" : "نفد المخزون"}</b></div>
          <div className="form-pair">
            <button className="outline" disabled={product.available_quantity < product.min_order_quantity} onClick={() => add(product, "b2b")}>أضف جملة</button>
            <button className="primary" disabled={!product.is_retail_available || product.retail_price == null || product.available_quantity < 1} onClick={() => add(product, "b2c")}>أضف مفرد</button>
          </div>
        </div>
      </article>)}</div>}
    <div className="retail-checkout-note">
      <b>مراجعة السلة الموحدة</b>
      {cart.length === 0 ? <span>أضف المنتجات إلى أحد المسارين. لا يتم إنشاء الطلبات إلا بعد التحقق الذري من السعر والمخزون داخل PostgreSQL.</span> : <>
        {cart.map(line => <div className="retail-cart-line" key={line.product.id + line.mode}>
          <span>{line.product.name}<small>{line.mode === "b2c" ? "مفرد B2C" : "جملة B2B"} · {money(lineUnitPrice(line))} للقطعة</small></span>
          <input aria-label={`كمية ${line.product.name} ${line.mode}`} type="number" min={line.mode === "b2b" ? line.product.min_order_quantity : 1} max={line.product.available_quantity} value={line.quantity} onChange={event => changeQuantity(line, event.target.value)} />
          <b>{money(line.quantity * lineUnitPrice(line))}</b>
          <button className="outline" onClick={() => setCart(current => current.filter(item => item.product.id !== line.product.id || item.mode !== line.mode))}>حذف</button>
        </div>)}
        {wholesaleLines.length > 0 && <label>شركة المشتري<select value={buyerId} onChange={event => setBuyerId(event.target.value)}><option value="">اختر شركة المشتري</option>{buyers.map(buyer => <option key={buyer.id} value={buyer.id}>{buyer.name_ar}</option>)}</select></label>}
        <label>عنوان التوصيل<input value={address} onChange={event => setAddress(event.target.value)} placeholder="المحافظة، المنطقة، الشارع، أقرب نقطة دالة" /></label>
        <b>الإجمالي التقديري: {money(total)}</b>
        <button className="primary" disabled={busy || address.trim().length < 8 || (wholesaleLines.length > 0 && !buyerId)} onClick={() => void checkout()}>{busy ? "جارٍ إنشاء عملية الشراء..." : "تأكيد الشراء الموحد"}</button>
        <small>تُحسب شرائح الجملة وتُفرض MOQ ويُحجز المخزون داخل معاملة قاعدة البيانات. المهلة 15 دقيقة؛ تحرير الحجوزات المنتهية يحتاج تشغيل المجدول الخلفي.</small>
      </>}
    </div>
  </section>;
}
