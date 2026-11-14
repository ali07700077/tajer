create or replace function public.submit_rfq_offer(p_rfq_id uuid,p_supplier_business_id uuid,p_total_price numeric,p_delivery_days integer,p_notes text default null)
returns uuid language plpgsql security definer set search_path=''
as $$
declare new_offer_id uuid; requested_quantity integer;
begin
 if auth.uid() is null then raise exception 'يجب تسجيل الدخول'; end if;
 if not public.has_business_role(p_supplier_business_id,array['owner'::public.member_role,'manager'::public.member_role]) then raise exception 'لا تملك صلاحية تقديم عرض لهذه الشركة'; end if;
 if not private.is_approved_supplier(p_supplier_business_id) then raise exception 'المورد غير معتمد أو غير نشط'; end if;
 if p_total_price is null or p_total_price<=0 then raise exception 'أدخل سعراً إجمالياً صحيحاً'; end if;
 if p_delivery_days is null or p_delivery_days<1 then raise exception 'أدخل مدة توريد صحيحة'; end if;
 select ri.quantity into requested_quantity from public.rfq_items ri join public.rfqs r on r.id=ri.rfq_id
 where ri.rfq_id=p_rfq_id and ri.supplier_business_id=p_supplier_business_id and r.status in ('open','responded') for update of r;
 if requested_quantity is null then raise exception 'طلب العرض غير موجه لشركتك أو لم يعد مفتوحاً'; end if;
 insert into public.rfq_offers(rfq_id,supplier_business_id,unit_price,total_price,quantity,currency,delivery_days,notes,status)
 values(p_rfq_id,p_supplier_business_id,p_total_price/requested_quantity,p_total_price,requested_quantity,'IQD',p_delivery_days,nullif(trim(p_notes),''),'submitted')
 returning id into new_offer_id;
 update public.rfqs set status='responded',updated_at=now() where id=p_rfq_id and status='open';
 return new_offer_id;
end;
$$;
revoke all on function public.submit_rfq_offer(uuid,uuid,numeric,integer,text) from public,anon;
grant execute on function public.submit_rfq_offer(uuid,uuid,numeric,integer,text) to authenticated;
