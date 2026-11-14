import { useEffect, useState } from "react";
import { getMyBusinesses, type BusinessSummary } from "../lib/businesses";
import { supabase } from "../lib/supabase";

type Campaign = {
  id: string; supplier_business_id: string; product_id: string; title_ar: string;
  target_quantity: number; max_quantity: number; committed_quantity: number;
  unit_price: number; currency: string; status: string; ends_at: string;
};
type CreditAccount = {
  id: string; buyer_business_id: string; credit_limit: number;
  outstanding_balance: number; currency: string; status: string; payment_term_days: number;
};
type Shipment = {
  id: string; shipment_reference: string; carrier_name: string | null;
  tracking_reference: string | null; status: string; delivery_address: string;
  shipping_cost: number; estimated_delivery_at: string | null;
};
const money = (amount: number) => new Intl.NumberFormat("ar-IQ", { maximumFractionDigits: 2 }).format(Number(amount)) + " د.ع";
const campaignStatus: Record<string,string> = { open:"مفتوحة", target_met:"اكتمل الهدف", expired:"منتهية", cancelled:"ملغاة", converted:"تحولت إلى طلب" };
const shipmentStatus: Record<string,string> = { planning:"قيد التخطيط", collecting:"تجميع الشحنات", dispatched:"تم الإرسال", in_transit:"في الطريق", delivered:"تم التسليم", exception:"تحتاج متابعة", cancelled:"ملغاة" };

export default function CommercialHub() {
  const [businesses,setBusinesses] = useState<BusinessSummary[]>([]);
  const [buyerId,setBuyerId] = useState("");
  const [campaigns,setCampaigns] = useState<Campaign[]>([]);
  const [credits,setCredits] = useState<CreditAccount[]>([]);
  const [shipments,setShipments] = useState<Shipment[]>([]);
  const [quantities,setQuantities] = useState<Record<string,string>>({});
  const [busy,setBusy] = useState<string | null>(null);
  const [message,setMessage] = useState("");
  const [loading,setLoading] = useState(true);

  async function load() {
    if (!supabase) { setMessage("اتصال قاعدة البيانات غير مضبوط."); setLoading(false); return; }
    try {
      const [mine,campaignResult,creditResult,shipmentResult] = await Promise.all([
        getMyBusinesses(),
        supabase.from("group_buy_campaigns").select("id,supplier_business_id,product_id,title_ar,target_quantity,max_quantity,committed_quantity,unit_price,currency,status,ends_at").in("status",["open","target_met"]).order("ends_at",{ascending:true}),
        supabase.from("b2b_credit_accounts").select("id,buyer_business_id,credit_limit,outstanding_balance,currency,status,payment_term_days"),
        supabase.from("consolidated_shipments").select("id,shipment_reference,carrier_name,tracking_reference,status,delivery_address,shipping_cost,estimated_delivery_at").order("created_at",{ascending:false}).limit(30),
      ]);
      if (campaignResult.error) throw campaignResult.error;
      if (creditResult.error) throw creditResult.error;
      if (shipmentResult.error) throw shipmentResult.error;
      setBusinesses(mine);
      const buyers=mine.filter(b=>b.business_type==="buyer");
      setBuyerId(current=>current || buyers[0]?.id || "");
      setCampaigns(campaignResult.data ?? []);
      setCredits(creditResult.data ?? []);
      setShipments(shipmentResult.data ?? []);
    } catch(error) {
      setMessage(error instanceof Error ? error.message : "تعذر تحميل الخدمات التجارية.");
    } finally { setLoading(false); }
  }
  useEffect(()=>{ void load(); },[]);

  async function join(campaign: Campaign) {
    if (!supabase || !buyerId) { setMessage("اختر شركة مشتري أولاً."); return; }
    const quantity=Number(quantities[campaign.id] ?? 1);
    if (!Number.isSafeInteger(quantity) || quantity<1) { setMessage("أدخل كمية صحيحة."); return; }
    setBusy(campaign.id); setMessage("");
    try {
      const {error}=await supabase.rpc("join_group_buy",{
        p_campaign_id:campaign.id,p_buyer_business_id:buyerId,p_quantity:quantity,
        p_idempotency_key:crypto.randomUUID(),
      });
      if(error) throw error;
      setMessage("تم تسجيل مشاركة شركتك في حملة الشراء الجماعي.");
      await load();
    } catch(error) { setMessage(error instanceof Error ? error.message : "تعذرت المشاركة في الحملة."); }
    finally { setBusy(null); }
  }

  if(loading) return <section className="panel"><p>جارٍ تحميل خدمات التجارة والتمويل...</p></section>;
  const buyers=businesses.filter(b=>b.business_type==="buyer");
  return <section className="wholesale-checkout">
    <div className="retail-intro">
      <div><span className="eyebrow">TAJER · Commercial Services</span><h2>الخدمات التجارية والمالية</h2><p>الشراء الجماعي، حدود الائتمان التجاري، والشحن المجمع في مساحة واحدة مرتبطة ببيانات المنصة.</p></div>
      <div className="retail-cart-summary"><b>شركتك المشترية</b><select value={buyerId} onChange={e=>setBuyerId(e.target.value)}><option value="">اختر الشركة</option>{buyers.map(b=><option key={b.id} value={b.id}>{b.name_ar}</option>)}</select><small>البيانات المالية للقراءة فقط؛ اعتماد الائتمان والحركات المالية صلاحيات خادمية.</small></div>
    </div>
    {message && <div className="notice"><p>{message}</p></div>}
    <div className="panel">
      <div className="section-heading"><div><span className="eyebrow">GROUP BUY</span><h2>حملات الشراء الجماعي</h2></div><span>{campaigns.length} حملة</span></div>
      {campaigns.length===0 ? <p>لا توجد حملات مفتوحة حالياً.</p> : <div className="product-grid">{campaigns.map(c=><article className="product-card" key={c.id}>
        <div className="product-art mint"><span>شراء جماعي</span><small>TAJER GROUP BUY</small></div>
        <div className="product-info"><h3>{c.title_ar}</h3><div className="product-price">{money(c.unit_price)} <span>للوحدة</span></div>
          <div className="product-foot"><span>المتحقق: {c.committed_quantity} / {c.target_quantity}</span><b>{campaignStatus[c.status] ?? c.status}</b></div>
          <div className="product-foot"><span>الحد الأعلى: {c.max_quantity}</span><span>ينتهي: {new Date(c.ends_at).toLocaleDateString("ar-IQ")}</span></div>
          <label>الكمية المطلوبة<input type="number" min="1" max={c.max_quantity-c.committed_quantity} value={quantities[c.id] ?? "1"} onChange={e=>setQuantities(v=>({...v,[c.id]:e.target.value}))}/></label>
          <button className="primary" disabled={busy!==null || c.status!=="open" || !buyerId} onClick={()=>void join(c)}>{busy===c.id?"جارٍ التسجيل...":"انضم إلى الحملة"}</button>
        </div></article>)}</div>}
    </div>
    <div className="panel">
      <div className="section-heading"><div><span className="eyebrow">B2B CREDIT</span><h2>الائتمان التجاري</h2></div></div>
      {credits.length===0 ? <p>لا يوجد تسهيل ائتماني مسجل لشركاتك. طلب الائتمان ومراجعته يخضعان لاعتماد الإدارة.</p> :
      <div className="product-grid">{credits.filter(c=>!buyerId || c.buyer_business_id===buyerId).map(c=><article className="product-card" key={c.id}><div className="product-info">
        <h3>{c.status==="approved"?"تسهيل ائتماني معتمد":c.status==="pending"?"قيد المراجعة":"حالة الحساب: "+c.status}</h3>
        <div className="product-price">الحد الائتماني: {money(c.credit_limit)}</div>
        <div className="product-foot"><span>الرصيد المستخدم</span><b>{money(c.outstanding_balance)}</b></div>
        <div className="product-foot"><span>المتاح</span><b>{money(Math.max(0,Number(c.credit_limit)-Number(c.outstanding_balance)))}</b></div>
        <small>مدة السداد: {c.payment_term_days} يوم · لا يتم إنشاء دين أو تعديل حد ائتماني من واجهة العميل.</small>
      </div></article>)}</div>}
    </div>
    <div className="panel">
      <div className="section-heading"><div><span className="eyebrow">CONSOLIDATED LOGISTICS</span><h2>الشحنات المجمعة</h2></div><span>{shipments.length} شحنة</span></div>
      {shipments.length===0 ? <p>لا توجد شحنات مجمعة مرتبطة بشركتك حالياً.</p> : shipments.map(s=><div className="retail-cart-line" key={s.id}>
        <span><b>{s.shipment_reference}</b><small>{s.carrier_name ?? "شركة النقل لم تحدد"} · {s.tracking_reference ?? "لا يوجد رقم تتبع"}<br/>{s.delivery_address}</small></span>
        <span>{shipmentStatus[s.status] ?? s.status}</span><b>{money(s.shipping_cost)}</b>
      </div>)}
    </div>
  </section>;
}
