import { useCallback, useEffect, useMemo, useState } from "react";
import { supabase } from "../lib/supabase";

type OrderItem = { id:string; product_name:string; quantity:number; unit_price:number };
type Order = { id:string; status:string; total_amount:number; currency:string; created_at:string; delivery_address:string|null; buyer_business_id:string; supplier_business_id:string; order_items:OrderItem[] };
type Warehouse = { id:string; business_id:string; governorate_id:string; city_id:string|null; code:string; name_ar:string; warehouse_type:string; address_text:string|null; is_default:boolean; is_active:boolean };
type Stock = { id:string; warehouse_id:string; product_id:string; on_hand_quantity:number; reserved_quantity:number; available_quantity:number };
type Region = { id:string; name_ar:string; code?:string };
const statusLabels:Record<string,string>={pending:"بانتظار الاعتماد",confirmed:"معتمد",processing:"قيد التجهيز",shipped:"تم الشحن",delivered:"تم التسليم",cancelled:"مرفوض / ملغى"};
const currencyLabel=(currency:string)=>currency==="USD"?"$":"د.ع";
const formatMoney=(amount:number,currency:string)=>new Intl.NumberFormat("en-US",{maximumFractionDigits:2}).format(Number(amount))+ " "+currencyLabel(currency);

export default function OrdersWorkspace({businessId,onOpenRfq,onReorder}:{businessId:string|null;onOpenRfq:()=>void;onReorder:()=>void}) {
 const [orders,setOrders]=useState<Order[]>([]),[warehouses,setWarehouses]=useState<Warehouse[]>([]),[stocks,setStocks]=useState<Stock[]>([]);
 const [governorates,setGovernorates]=useState<Region[]>([]),[cities,setCities]=useState<Region[]>([]);
 const [loading,setLoading]=useState(true),[busy,setBusy]=useState<string|null>(null),[message,setMessage]=useState(""),[filter,setFilter]=useState("all"),[otp,setOtp]=useState<{orderId:string;code:string}|null>(null);
 const load=useCallback(async()=>{
  if(!supabase){setLoading(false);setMessage("اتصال قاعدة البيانات غير مضبوط.");return;}
  setLoading(true);
  const db=supabase as any;
  try{
   let oq=db.from("orders").select("id,status,total_amount,currency,created_at,delivery_address,buyer_business_id,supplier_business_id,order_items(id,product_name,quantity,unit_price)").order("created_at",{ascending:false}).limit(50);
   let wq=db.from("warehouses").select("id,business_id,governorate_id,city_id,code,name_ar,warehouse_type,address_text,is_default,is_active").eq("is_active",true).order("name_ar");
   if(businessId){oq=oq.or(`buyer_business_id.eq.${businessId},supplier_business_id.eq.${businessId}`);wq=wq.eq("business_id",businessId);}
   const [o,w,g,c]=await Promise.all([oq,wq,db.from("governorates").select("id,name_ar,code").eq("is_active",true).order("sort_order"),db.from("cities").select("id,name_ar").eq("is_active",true).order("sort_order")]);
   if(o.error)throw o.error;if(w.error)throw w.error;if(g.error)throw g.error;if(c.error)throw c.error;
   const warehouseRows=(w.data??[]) as Warehouse[];
   const warehouseIds=warehouseRows.map(x=>x.id);
   let stockRows:Stock[]=[];
   if(warehouseIds.length){const s=await db.from("warehouse_stock").select("id,warehouse_id,product_id,on_hand_quantity,reserved_quantity,available_quantity").in("warehouse_id",warehouseIds);if(s.error)throw s.error;stockRows=(s.data??[]) as Stock[];}
   setOrders((o.data??[]) as unknown as Order[]);setWarehouses(warehouseRows);setStocks(stockRows);setGovernorates((g.data??[]) as Region[]);setCities((c.data??[]) as Region[]);setMessage("");
  }catch(e){setMessage(e instanceof Error?e.message:"تعذر تحميل الطلبات والمخازن. تحقق من تسجيل الدخول وصلاحيات الشركة.");}
  finally{setLoading(false);}
 },[businessId]);
 useEffect(()=>{void load();},[load]);
 const filtered=useMemo(()=>orders.filter(o=>filter==="all"||o.status===filter),[orders,filter]);
 const warehouseStats=useMemo(()=>({count:warehouses.length,units:stocks.reduce((n,s)=>n+Number(s.on_hand_quantity),0),available:stocks.reduce((n,s)=>n+Number(s.available_quantity),0)}),[warehouses,stocks]);
 async function transition(order:Order,status:"confirmed"|"cancelled"){
  if(!supabase)return;
  const reason=status==="cancelled"?window.prompt("اكتب سبب رفض الطلب (إلزامي):"):null;
  if(status==="cancelled"&&(!reason||reason.trim().length<4)){setMessage("لم يتم الرفض: يجب إدخال سبب واضح من أربعة أحرف على الأقل.");return;}
  setBusy(order.id);setMessage("");
  try{const {error}=await db.rpc("transition_order_status",{p_order_id:order.id,p_next_status:status,p_reason:reason});if(error)throw error;setMessage(status==="confirmed"?"تم اعتماد الطلب وتسجيل العملية.":"تم رفض الطلب وتوثيق السبب.");await load();}
  catch(e){setMessage(e instanceof Error?e.message:"تعذر تنفيذ الإجراء.");}finally{setBusy(null);}
 }
 async function changeQuantity(order:Order,item:OrderItem){
  if(!supabase)return;const db=supabase as any;const value=window.prompt(`الكمية الجديدة للمنتج: ${item.product_name}`,String(item.quantity));if(value===null)return;
  const quantity=Number(value);if(!Number.isFinite(quantity)||quantity<=0){setMessage("أدخل كمية أكبر من صفر.");return;}
  const reason=window.prompt("سبب تعديل الكمية:");if(!reason||reason.trim().length<4){setMessage("سبب تعديل الكمية مطلوب.");return;}
  setBusy(order.id);try{const {error}=await db.rpc("update_order_item_quantity",{p_order_item_id:item.id,p_quantity:quantity,p_reason:reason});if(error)throw error;setMessage("تم تحديث الكمية وإعادة احتساب إجمالي الطلب.");await load();}
  catch(e){setMessage(e instanceof Error?e.message:"تعذر تعديل الكمية.");}finally{setBusy(null);}
 }
 async function issueCode(order:Order){
  if(!supabase)return;const db=supabase as any;setBusy(order.id);setOtp(null);
  try{const {data,error}=await db.rpc("issue_order_handoff_code",{p_order_id:order.id});if(error)throw error;setOtp({orderId:order.id,code:String(data)});setMessage("رمز تسليم أحادي الاستخدام صالح لمدة 30 دقيقة. اعرضه للمستلم بأمان.");}
  catch(e){setMessage(e instanceof Error?e.message:"تعذر إصدار رمز التسليم.");}finally{setBusy(null);}
 }
 const governorateName=(id:string)=>governorates.find(g=>g.id===id)?.name_ar??"محافظة غير محددة";
 const cityName=(id:string|null)=>id?cities.find(c=>c.id===id)?.name_ar??"مدينة غير محددة":"";
 return <section className="wms-workspace" data-testid="wms-workspace" dir="rtl">
  <div className="wms-hero"><div><span className="eyebrow">TAJER · WAREHOUSE & ORDER OPERATIONS</span><h2>إدارة الطلبات والمخازن</h2><p>متابعة مخزون الشركات والطلبات ضمن صلاحيات Supabase، مع سجل إجراءات موثق.</p></div><button className="outline" onClick={()=>void load()} disabled={loading}>↻ تحديث البيانات</button></div>
  {message&&<div className="notice" role="status"><p>{message}</p><button onClick={()=>setMessage("")}>×</button></div>}
  {otp&&<div className="wms-otp" role="status"><div><b>رمز التسليم للطلب</b><small>{otp.orderId.slice(0,8)} · صالح 30 دقيقة · استخدام واحد</small></div><strong>{otp.code}</strong><button className="outline" onClick={()=>{void navigator.clipboard?.writeText(otp.code);setMessage("تم نسخ رمز التسليم.");}}>نسخ الرمز</button></div>}
  <div className="wms-metrics"><article><small>المخازن النشطة</small><b>{warehouseStats.count}</b><span>ضمن شركاتك</span></article><article><small>إجمالي الوحدات</small><b>{new Intl.NumberFormat("en-US").format(warehouseStats.units)}</b><span>مخزون على الرف</span></article><article><small>المتاح للبيع</small><b>{new Intl.NumberFormat("en-US").format(warehouseStats.available)}</b><span>بعد الحجوزات</span></article><article><small>الطلبات الظاهرة</small><b>{orders.length}</b><span>حسب سياسات RLS</span></article></div>
  <div className="panel">
   <div className="section-heading"><div><span className="eyebrow">MULTI-WAREHOUSE WMS</span><h2>مخازن الشركة</h2><p>التوزيع الجغرافي للمخازن المسجلة. المحافظات العراقية النشطة في الدليل تشمل 19 محافظة.</p></div><span className="muted">{warehouses.length} مخزن</span></div>
   {loading?<p>جارٍ تحميل بيانات المخازن...</p>:warehouses.length===0?<div className="empty">لا توجد مخازن متاحة لهذه الشركة، أو لا تملك عضويتك صلاحية رؤيتها.</div>:<div className="wms-warehouse-grid">{warehouses.map(w=><article className="wms-warehouse" key={w.id}><div className="wms-warehouse-icon">▣</div><div><b>{w.name_ar}</b><small>{governorateName(w.governorate_id)} {cityName(w.city_id)} · {w.code}</small><small>{w.warehouse_type==="distribution_center"?"مركز توزيع":w.warehouse_type==="fulfillment"?"تجهيز الطلبات":w.warehouse_type==="returns"?"مرتجعات":w.warehouse_type==="storefront"?"متجر":"مخزن قياسي"} {w.is_default?"· الافتراضي":""}</small></div></article>)}</div>}
  </div>
  <div className="panel">
   <div className="section-heading"><div><span className="eyebrow">ORDER WORKFLOW</span><h2>الطلبات وإجراءاتها السريعة</h2><p>الاعتماد والرفض وتعديل الكميات تتم عبر دوال خادمية مع تحقق العضوية وتسجيل الأثر.</p></div><select aria-label="تصفية الطلبات" value={filter} onChange={e=>setFilter(e.target.value)}><option value="all">كل الحالات</option><option value="pending">بانتظار الاعتماد</option><option value="confirmed">معتمد</option><option value="processing">قيد التجهيز</option><option value="shipped">تم الشحن</option><option value="delivered">تم التسليم</option><option value="cancelled">مرفوض / ملغى</option></select></div>
   {loading?<p>جارٍ تحميل الطلبات...</p>:filtered.length===0?<div className="empty" data-testid="orders-empty">لا توجد طلبات ظاهرة حالياً. تظهر الطلبات التي تسمح بها سياسات RLS لحسابك فقط.</div>:filtered.map(o=><article className="wms-order" key={o.id} data-testid="wms-order"><div className="wms-order-head"><div><b>طلب #{o.id.slice(0,8).toUpperCase()}</b><small>{new Date(o.created_at).toLocaleString("ar-IQ")} · {o.delivery_address??"عنوان التسليم غير محدد"}</small></div><span className={`wms-status status-${o.status}`}>{statusLabels[o.status]??o.status}</span></div>
    <div className="wms-order-total"><strong>{formatMoney(Number(o.total_amount),o.currency)}</strong><small>{o.order_items?.length??0} بند · {o.currency}</small></div>
    {o.order_items?.map(item=><div className="wms-order-line" key={item.id}><span>{item.product_name}<small>{item.quantity} × {formatMoney(Number(item.unit_price),o.currency)}</small></span>{o.status==="pending"&&<button className="text-btn" disabled={busy===o.id} onClick={()=>void changeQuantity(o,item)}>تعديل الكمية</button>}</div>)}
    <div className="wms-actions">
     {o.status==="pending"&&<><button className="primary" disabled={busy===o.id} onClick={()=>void transition(o,"confirmed")}>✓ اعتماد فوري</button><button className="danger-outline outline" disabled={busy===o.id} onClick={()=>void transition(o,"cancelled")}>رفض مع سبب</button></>}
     {o.status==="confirmed"&&<button className="outline" disabled={busy===o.id} onClick={()=>void transition(o,"processing")}>بدء التجهيز</button>}{o.status==="processing"&&<button className="outline" disabled={busy===o.id} onClick={()=>void transition(o,"shipped")}>تسجيل الشحن</button>}<button className="outline" onClick={onOpenRfq}>طلب عرض سعر RFQ</button>
     <button className="outline" onClick={onReorder}>إعادة الطلب</button>
     {(o.status==="processing"||o.status==="shipped")&&<button className="outline" disabled={busy===o.id} onClick={()=>void issueCode(o)}>إصدار OTP للتسليم</button>}
    </div>
   </article>)}
  </div>
 </section>;
}
