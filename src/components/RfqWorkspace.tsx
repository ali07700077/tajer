import { useEffect, useMemo, useState } from "react";
import { getMyBusinesses, type BusinessSummary } from "../lib/businesses";
import { supabase } from "../lib/supabase";

type Product = {
  id: string; name: string; description: string | null; price: number;
  min_order_quantity: number; stock_quantity: number; category?: { name_ar: string } | null;
  supplier_name?: string;
};
type RfqItem = { id: string; product_id: string; quantity: number; supplier_business_id: string; products?: { name: string; price: number } | null };
type Offer = { id: string; supplier_business_id: string; total_price: number; delivery_days: number | null; notes: string | null; status: string; quantity: number };
type Rfq = { id: string; title: string; description: string | null; status: string; created_at: string; rfq_items?: RfqItem[]; rfq_offers?: Offer[] };
const money = (v: number) => new Intl.NumberFormat("en-US").format(Number(v || 0)) + " د.ع";
const db = () => { if (!supabase) throw new Error("اتصال قاعدة البيانات غير مضبوط."); return supabase as any; };
const statusLabel: Record<string,string> = { open:"بانتظار رد المورد", responded:"تم الرد بعرض سعر", awarded:"تم قبول العرض", closed:"مغلق" };

export default function RfqWorkspace({ mode }: { mode: "catalog" | "dashboard" }) {
  const [businesses,setBusinesses] = useState<BusinessSummary[]>([]);
  const [selectedBuyer,setSelectedBuyer] = useState("");
  const [selectedSupplier,setSelectedSupplier] = useState("");
  const [products,setProducts] = useState<Product[]>([]);
  const [requests,setRequests] = useState<Rfq[]>([]);
  const [offers,setOffers] = useState<Record<string,Offer[]>>({});
  const [supplierNames,setSupplierNames] = useState<Record<string,string>>({});
  const [search,setSearch] = useState("");
  const [category,setCategory] = useState("الكل");
  const [selectedProduct,setSelectedProduct] = useState<Product|null>(null);
  const [quantity,setQuantity] = useState("1");
  const [notes,setNotes] = useState("");
  const [quoteRfq,setQuoteRfq] = useState<Rfq|null>(null);
  const [quoteTotal,setQuoteTotal] = useState("");
  const [deliveryDays,setDeliveryDays] = useState("3");
  const [quoteNotes,setQuoteNotes] = useState("");
  const [loading,setLoading] = useState(true);
  const [busy,setBusy] = useState(false);
  const [message,setMessage] = useState("");
  const [signedIn,setSignedIn] = useState(false);

  const buyerBusinesses = businesses.filter(b=>b.business_type==="buyer");
  const supplierBusinesses = businesses.filter(b=>b.business_type==="supplier");
  const categories = useMemo(()=>["الكل",...Array.from(new Set(products.map(p=>p.category?.name_ar).filter((x):x is string=>Boolean(x))))],[products]);
  const filtered = useMemo(()=>products.filter(p=>(p.name+" "+(p.description??"")+" "+(p.category?.name_ar??"")).toLowerCase().includes(search.trim().toLowerCase())&&(category==="الكل"||p.category?.name_ar===category)),[products,search,category]);

  async function loadCatalog() {
    const {data,error}=await db().from("products")
      .select("id,business_id,name,description,price,min_order_quantity,stock_quantity,category:categories(name_ar)")
      .eq("is_active",true)
      .order("created_at",{ascending:false});
    if(error) throw error;
    const rows=(data??[]) as any[];
    const supplierIds=Array.from(new Set(rows.map(p=>p.business_id)));
    const {data:suppliers,error:supplierError}=supplierIds.length?await db().from("public_supplier_directory").select("id,name_ar").in("id",supplierIds):{data:[],error:null};
    if(supplierError) throw supplierError;
    const names=Object.fromEntries((suppliers??[]).map((b:any)=>[b.id,b.name_ar]));
    setProducts(rows.map(p=>({...p,supplier_name:names[p.business_id]??"مورد معتمد"})));
  }

  async function loadBusinesses() {
    const rows=await getMyBusinesses();
    setBusinesses(rows);
    setSelectedBuyer(cur=>rows.some(b=>b.id===cur&&b.business_type==="buyer")?cur:rows.find(b=>b.business_type==="buyer")?.id??"");
    setSelectedSupplier(cur=>rows.some(b=>b.id===cur&&b.business_type==="supplier")?cur:rows.find(b=>b.business_type==="supplier")?.id??"");
  }

  async function loadBuyerRequests(buyerId:string) {
    const {data,error}=await db().from("rfqs")
      .select("id,title,description,status,created_at,rfq_items(id,product_id,quantity,supplier_business_id,products(name,price)),rfq_offers(id,supplier_business_id,total_price,delivery_days,notes,status,quantity)")
      .eq("buyer_business_id",buyerId).order("created_at",{ascending:false});
    if(error) throw error;
    const rows=(data??[]) as Rfq[];
    setRequests(rows);
    const ids=Array.from(new Set(rows.flatMap(r=>(r.rfq_offers??[]).map(o=>o.supplier_business_id))));
    if(ids.length){
      const {data:names,error:namesError}=await db().from("public_supplier_directory").select("id,name_ar").in("id",ids);
      if(namesError) throw namesError;
      setSupplierNames(Object.fromEntries((names??[]).map((b:any)=>[b.id,b.name_ar])));
    } else setSupplierNames({});
  }

  async function loadSupplierRequests(supplierId:string) {
    const {data,error}=await db().from("rfqs")
      .select("id,title,description,status,created_at,rfq_items!inner(id,product_id,quantity,supplier_business_id,products(name,price))")
      .eq("rfq_items.supplier_business_id",supplierId).order("created_at",{ascending:false});
    if(error) throw error;
    setRequests((data??[]) as Rfq[]);
  }

  async function refresh() {
    if(!supabase){setLoading(false);return;}
    setLoading(true);setMessage("");
    try{
      const {data:{session},error}=await db().auth.getSession();
      if(error) throw error;
      setSignedIn(Boolean(session));
      if(session) await loadBusinesses();
      if(mode==="catalog") await loadCatalog();
    }catch(e){setMessage(e instanceof Error?e.message:"تعذر تحميل البيانات.");}
    finally{setLoading(false);}
  }

  useEffect(()=>{void refresh();},[mode]);
  useEffect(()=>{
    if(mode!=="dashboard"||!signedIn)return;
    let alive=true;
    (async()=>{
      setLoading(true);
      try{
        if(selectedBuyer) await loadBuyerRequests(selectedBuyer);
        else if(selectedSupplier) await loadSupplierRequests(selectedSupplier);
        else setRequests([]);
      }catch(e){if(alive)setMessage(e instanceof Error?e.message:"تعذر تحميل طلبات عروض الأسعار.");}
      finally{if(alive)setLoading(false);}
    })();
    return()=>{alive=false;};
  },[mode,signedIn,selectedBuyer,selectedSupplier]);

  async function createRfq(){
    if(!selectedProduct)return;
    if(!signedIn){setMessage("سجّل الدخول أولاً لإرسال طلب عرض السعر.");return;}
    const qty=Number(quantity);
    if(!selectedBuyer){setMessage("أنشئ أو اختر ملف شركة مشتري أولاً.");return;}
    if(!Number.isInteger(qty)||qty<selectedProduct.min_order_quantity){setMessage("الكمية يجب أن تساوي الحد الأدنى للطلب أو أكثر.");return;}
    setBusy(true);setMessage("");
    try{
      const {error}=await db().rpc("create_rfq_for_product",{p_buyer_business_id:selectedBuyer,p_product_id:selectedProduct.id,p_quantity:qty,p_notes:notes.trim()||null});
      if(error)throw error;
      setSelectedProduct(null);setQuantity("1");setNotes("");
      setMessage("تم إرسال طلب عرض السعر إلى المورد بنجاح.");
    }catch(e){setMessage(e instanceof Error?e.message:"تعذر إرسال طلب عرض السعر.");}
    finally{setBusy(false);}
  }

  async function submitQuote(){
    if(!quoteRfq||!selectedSupplier)return;
    const total=Number(quoteTotal),days=Number(deliveryDays);
    if(!Number.isFinite(total)||total<=0||!Number.isInteger(days)||days<1){setMessage("أدخل السعر الإجمالي ومدة التوريد بشكل صحيح.");return;}
    setBusy(true);setMessage("");
    try{
      const {error}=await db().rpc("submit_rfq_offer",{p_rfq_id:quoteRfq.id,p_supplier_business_id:selectedSupplier,p_total_price:total,p_delivery_days:days,p_notes:quoteNotes.trim()||null});
      if(error)throw error;
      setQuoteRfq(null);setQuoteTotal("");setQuoteNotes("");
      await loadSupplierRequests(selectedSupplier);
      setMessage("تم إرسال عرض السعر للمشتري.");
    }catch(e){setMessage(e instanceof Error?e.message:"تعذر تقديم عرض السعر.");}
    finally{setBusy(false);}
  }

  async function acceptOffer(offerId:string){
    if(!window.confirm("هل تريد قبول هذا العرض؟ سيتم رفض بقية العروض على الطلب نفسه."))return;
    setBusy(true);setMessage("");
    try{
      const {error}=await db().rpc("accept_rfq_offer",{p_offer_id:offerId});
      if(error)throw error;
      if(selectedBuyer)await loadBuyerRequests(selectedBuyer);
      setMessage("تم قبول العرض وإغلاق المنافسة على هذا الطلب.");
    }catch(e){setMessage(e instanceof Error?e.message:"تعذر قبول العرض.");}
    finally{setBusy(false);}
  }

  if(loading&&!products.length&&!requests.length)return <section className="panel rfq-workspace"><p>جارٍ تحميل البيانات...</p></section>;

  if(mode==="catalog")return <section className="rfq-workspace">
    <div className="toolbar">
      <input className="search" placeholder="ابحث عن منتج أو وصف أو مورد..." value={search} onChange={e=>setSearch(e.target.value)}/>
      <select value={category} onChange={e=>setCategory(e.target.value)} aria-label="التصنيف">{categories.map(c=><option key={c}>{c}</option>)}</select>
      <button className="outline" onClick={()=>{setSearch("");setCategory("الكل");}}>مسح الفلاتر</button>
    </div>
    {message&&<div className="notice"><p>{message}</p></div>}
    {!products.length?<div className="empty-state"><h2>لا توجد منتجات معتمدة منشورة حالياً</h2><p>ستظهر هنا منتجات الشركات المعتمدة والنشطة فقط.</p></div>:
      <div className="product-grid">{filtered.map(p=><article className="product-card rfq-product" key={p.id}>
        <div className="product-art mint"><span>▦</span><small>{p.category?.name_ar??"منتج جملة"}</small></div>
        <div className="product-info"><small>{p.supplier_name}</small><h3>{p.name}</h3><p className="rfq-description">{p.description||"منتج متاح للطلب بالجملة."}</p>
          <div className="product-price">{money(p.price)} <span>/ سعر إرشادي للوحدة</span></div>
          <div className="product-foot"><span>الحد الأدنى: {p.min_order_quantity}</span><b className={p.stock_quantity>0?"in-stock":"low-stock"}>{p.stock_quantity>0?"متوفر":"حسب الطلب"}</b></div>
          <button className="primary rfq-full" onClick={()=>{setSelectedProduct(p);setQuantity(String(p.min_order_quantity));setMessage("");}}>طلب عرض سعر</button>
        </div>
      </article>)}
      {!filtered.length&&<div className="empty">لا توجد منتجات مطابقة للبحث.</div>}</div>}
    {selectedProduct&&<div className="rfq-modal-backdrop" onClick={()=>setSelectedProduct(null)}><section className="panel rfq-modal" onClick={e=>e.stopPropagation()}>
      <div className="panel-head"><h3>طلب عرض سعر</h3><button className="outline" onClick={()=>setSelectedProduct(null)}>إغلاق</button></div>
      <b>{selectedProduct.name}</b><small className="muted">المورد: {selectedProduct.supplier_name} · MOQ: {selectedProduct.min_order_quantity}</small>
      <label>شركة المشتري<select value={selectedBuyer} onChange={e=>setSelectedBuyer(e.target.value)}>{buyerBusinesses.map(b=><option key={b.id} value={b.id}>{b.name_ar}</option>)}</select></label>
      <label>الكمية المطلوبة<input type="number" min={selectedProduct.min_order_quantity} step="1" value={quantity} onChange={e=>setQuantity(e.target.value)}/></label>
      <label>ملاحظات الطلب<textarea rows={3} value={notes} onChange={e=>setNotes(e.target.value)} placeholder="المواصفات، المدينة، موعد التسليم المطلوب..."/></label>
      {!signedIn&&<p className="muted">يلزم تسجيل الدخول قبل الإرسال.</p>}
      <button className="primary" disabled={busy||!signedIn||!buyerBusinesses.length} onClick={createRfq}>{busy?"جارٍ الإرسال...":"إرسال طلب عرض السعر"}</button>
      {!buyerBusinesses.length&&signedIn&&<small className="muted">لا يوجد ملف مشتري مرتبط بحسابك. أنشئه من صفحة شركاتي والحساب.</small>}
    </section></div>}
  </section>;

  if(!signedIn)return <section className="panel rfq-workspace"><h3>طلبات عروض الأسعار</h3><p>سجّل الدخول لعرض طلباتك أو الطلبات الموجهة لشركتك.</p></section>;

  return <section className="panel rfq-workspace">
    <div className="panel-head"><div><h3>إدارة طلبات عروض الأسعار</h3><span className="muted">طلبات المشتري وعروض الموردين ضمن صلاحيات شركتك</span></div><button className="outline" onClick={()=>void refresh()}>تحديث</button></div>
    <div className="rfq-role-switch">
      <button className={buyerBusinesses.length?"selected":""} disabled={!buyerBusinesses.length} onClick={()=>{setSelectedBuyer(buyerBusinesses[0]?.id??"");setSelectedSupplier("");}}>طلباتي كمشتري</button>
      <button className={supplierBusinesses.length?"selected":""} disabled={!supplierBusinesses.length} onClick={()=>{setSelectedSupplier(supplierBusinesses[0]?.id??"");setSelectedBuyer("");}}>الوارد للمورد</button>
    </div>
    {buyerBusinesses.length>0&&selectedBuyer&&<label className="rfq-company-select">شركة المشتري<select value={selectedBuyer} onChange={e=>setSelectedBuyer(e.target.value)}>{buyerBusinesses.map(b=><option key={b.id} value={b.id}>{b.name_ar}</option>)}</select></label>}
    {supplierBusinesses.length>0&&selectedSupplier&&<label className="rfq-company-select">شركة المورد<select value={selectedSupplier} onChange={e=>setSelectedSupplier(e.target.value)}>{supplierBusinesses.map(b=><option key={b.id} value={b.id}>{b.name_ar}</option>)}</select></label>}
    {message&&<div className="notice"><p>{message}</p></div>}
    {loading?<p>جارٍ تحميل الطلبات...</p>:requests.length===0?<div className="empty">لا توجد طلبات في هذا القسم حالياً.</div>:requests.map(r=><article className="rfq-request-card" key={r.id}>
      <div className="rfq-request-head"><div><b>{r.title}</b><small>{new Date(r.created_at).toLocaleString("ar-IQ")}</small></div><span className={r.status==="awarded"?"status-active":"draft-pill"}>{statusLabel[r.status]??r.status}</span></div>
      {r.description&&<p>{r.description}</p>}
      {(r.rfq_items??[]).map(item=><div className="rfq-line" key={item.id}><span>{item.products?.name??"منتج"}</span><b>{item.quantity.toLocaleString("en-US")} قطعة</b></div>)}
      {selectedBuyer&&<div className="rfq-offers"><b>عروض الموردين ({(r.rfq_offers??[]).length})</b>
        {(r.rfq_offers??[]).map(o=><div className="rfq-offer" key={o.id}><div><b>{supplierNames[o.supplier_business_id]??"المورد"}</b><small>{o.delivery_days??"—"} يوم توريد · {o.notes??"بدون ملاحظات"}</small></div><strong>{money(Number(o.total_price))}</strong>{o.status==="accepted"?<span className="status-active">مقبول</span>:o.status==="rejected"?<span className="draft-pill">مرفوض</span>:r.status!=="awarded"?<button className="primary" disabled={busy} onClick={()=>acceptOffer(o.id)}>قبول العرض</button>:null}</div>)}
      </div>}
      {selectedSupplier&&r.status!=="awarded"&&<div className="rfq-request-actions"><button className="primary" onClick={()=>{setQuoteRfq(r);setQuoteTotal("");setDeliveryDays("3");setQuoteNotes("");}}>تقديم عرض سعر</button></div>}
    </article>)}
    {quoteRfq&&<div className="rfq-modal-backdrop" onClick={()=>setQuoteRfq(null)}><section className="panel rfq-modal" onClick={e=>e.stopPropagation()}>
      <div className="panel-head"><h3>تقديم عرض سعر</h3><button className="outline" onClick={()=>setQuoteRfq(null)}>إغلاق</button></div>
      <b>{quoteRfq.title}</b>
      <label>السعر الإجمالي (د.ع)<input type="number" min="1" step="1" value={quoteTotal} onChange={e=>setQuoteTotal(e.target.value)}/></label>
      <label>مدة التوريد (يوم)<input type="number" min="1" step="1" value={deliveryDays} onChange={e=>setDeliveryDays(e.target.value)}/></label>
      <label>ملاحظات العرض<textarea rows={3} value={quoteNotes} onChange={e=>setQuoteNotes(e.target.value)} placeholder="تفاصيل التوريد أو شروط العرض..."/></label>
      <button className="primary" disabled={busy} onClick={submitQuote}>{busy?"جارٍ الإرسال...":"إرسال العرض للمشتري"}</button>
    </section></div>}
  </section>;
}
