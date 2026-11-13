import { test, expect } from "@playwright/test";
import { createClient, type SupabaseClient } from "@supabase/supabase-js";
import { randomUUID } from "node:crypto";

// Supabase CLI exports API_URL / ANON_KEY / SERVICE_ROLE_KEY into GITHUB_ENV.
// Support those names as well as explicit SUPABASE_* variables used locally.
const url = process.env.SUPABASE_URL || process.env.API_URL || "";
const anonKey = process.env.SUPABASE_ANON_KEY || process.env.ANON_KEY || process.env.PUBLISHABLE_KEY || "";
const serviceKey = process.env.SUPABASE_SERVICE_ROLE_KEY || process.env.SERVICE_ROLE_KEY || process.env.SECRET_KEY || "";
const rfqId = "30000000-0000-4000-8000-000000000001";
const supplierOne = "10000000-0000-4000-8000-000000000001";
const supplierTwo = "10000000-0000-4000-8000-000000000002";
const buyerBusiness = "10000000-0000-4000-8000-000000000003";

type Actor = { id: string; client: SupabaseClient; email: string };

async function createActor(admin: SupabaseClient, label: string): Promise<Actor> {
  const email = `${label}-${randomUUID()}@tajer.test`;
  const password = `Tj-${randomUUID()}-Aa9!`;
  const { data, error } = await admin.auth.admin.createUser({
    email, password, email_confirm: true, user_metadata: { full_name: label },
  });
  if (error || !data.user) throw error ?? new Error("Could not create test user");
  const client = createClient(url, anonKey, { auth: { persistSession: false, autoRefreshToken: false } });
  const signed = await client.auth.signInWithPassword({ email, password });
  if (signed.error) throw signed.error;
  return { id: data.user.id, client, email };
}

test("company isolation and complete RFQ lifecycle", async ({ page }) => {
  expect(
    url.startsWith("http://") || url.startsWith("https://"),
    "Supabase URL must be supplied by the local Supabase CLI",
  ).toBe(true);
  expect(anonKey, "Supabase anon key is required").toBeTruthy();
  expect(serviceKey, "Supabase service role key is required").toBeTruthy();

  const admin = createClient(url, serviceKey, { auth: { persistSession: false, autoRefreshToken: false } });
  const actors: Actor[] = [];
  try {
    const buyer = await createActor(admin, "buyer");
    actors.push(buyer);
    const supplierA = await createActor(admin, "supplier-a");
    actors.push(supplierA);
    const supplierB = await createActor(admin, "supplier-b");
    actors.push(supplierB);

    const memberships = [
      { business_id: buyerBusiness, user_id: buyer.id, member_role: "owner" },
      { business_id: supplierOne, user_id: supplierA.id, member_role: "owner" },
      { business_id: supplierTwo, user_id: supplierB.id, member_role: "owner" },
    ];
    const { error: memberError } = await admin.from("business_members").insert(memberships);
    if (memberError) throw memberError;

    const { data: aVisible, error: aError } = await supplierA.client
      .from("rfq_items").select("rfq_id,supplier_business_id").eq("rfq_id", rfqId);
    expect(aError).toBeNull();
    expect(aVisible?.length).toBe(1);
    expect(aVisible?.[0].supplier_business_id).toBe(supplierOne);

    const { data: bVisible, error: bError } = await supplierB.client
      .from("rfq_items").select("rfq_id,supplier_business_id").eq("rfq_id", rfqId);
    expect(bError).toBeNull();
    expect(bVisible?.length).toBe(1);
    expect(bVisible?.[0].supplier_business_id).toBe(supplierTwo);

    const { data: buyerRfq, error: buyerError } = await buyer.client
      .from("rfqs").select("id,status").eq("id", rfqId).single();
    expect(buyerError).toBeNull();
    expect(buyerRfq?.status).toBe("open");

    const { data: offerA, error: offerAError } = await supplierA.client.rpc("submit_rfq_offer", {
      p_rfq_id: rfqId, p_supplier_business_id: supplierOne,
      p_total_price: 500000, p_delivery_days: 4, p_notes: "عرض المورد الأول التجريبي",
    });
    expect(offerAError).toBeNull();
    expect(offerA).toBeTruthy();

    const { data: wrongOffer, error: wrongOfferError } = await supplierA.client.rpc("submit_rfq_offer", {
      p_rfq_id: rfqId, p_supplier_business_id: supplierTwo,
      p_total_price: 90000, p_delivery_days: 3, p_notes: "محاولة غير مصرح بها",
    });
    expect(wrongOffer).toBeNull();
    expect(wrongOfferError).not.toBeNull();

    const { data: offerB, error: offerBError } = await supplierB.client.rpc("submit_rfq_offer", {
      p_rfq_id: rfqId, p_supplier_business_id: supplierTwo,
      p_total_price: 90000, p_delivery_days: 3, p_notes: "عرض المورد الثاني التجريبي",
    });
    expect(offerBError).toBeNull();
    expect(offerB).toBeTruthy();

    const { error: acceptError } = await buyer.client.rpc("accept_rfq_offer", { p_offer_id: offerA });
    expect(acceptError).toBeNull();

    const { data: finalRfq, error: finalRfqError } = await buyer.client
      .from("rfqs").select("status,awarded_offer_id").eq("id", rfqId).single();
    expect(finalRfqError).toBeNull();
    expect(finalRfq?.status).toBe("awarded");
    expect(finalRfq?.awarded_offer_id).toBe(offerA);

    const { data: offers, error: offersError } = await buyer.client
      .from("rfq_offers").select("id,status").eq("rfq_id", rfqId);
    expect(offersError).toBeNull();
    expect(offers?.find(o => o.id === offerA)?.status).toBe("accepted");
    expect(offers?.find(o => o.id === offerB)?.status).toBe("rejected");

    // Exercise the hybrid B2B checkout, sample request, and supplier-issued proforma.
    const wholesaleProductId = randomUUID();
    const { error: productError } = await admin.from("products").insert({
      id: wholesaleProductId,
      business_id: supplierOne,
      name: "E2E wholesale checkout fixture",
      price: 10000,
      min_order_quantity: 5,
      stock_quantity: 30,
      is_active: true,
      sample_available: true,
      sample_price: 2000,
      sample_max_quantity: 2,
    });
    if (productError) throw productError;
    const { error: tierError } = await admin.from("product_price_tiers").insert({
      product_id: wholesaleProductId, min_quantity: 10, unit_price: 9000,
    });
    if (tierError) throw tierError;

    const { data: belowMoq, error: belowMoqError } = await buyer.client.rpc("create_wholesale_orders", {
      p_buyer_business_id: buyerBusiness,
      p_items: [{ product_id: wholesaleProductId, quantity: 4 }],
      p_delivery_address: "بغداد، الكرادة، شارع ١",
    });
    expect(belowMoq).toBeNull();
    expect(belowMoqError).not.toBeNull();

    const { data: wholesaleOrders, error: wholesaleError } = await buyer.client.rpc("create_wholesale_orders", {
      p_buyer_business_id: buyerBusiness,
      p_items: [{ product_id: wholesaleProductId, quantity: 12 }],
      p_delivery_address: "بغداد، الكرادة، شارع ١",
    });
    expect(wholesaleError).toBeNull();
    expect(wholesaleOrders).toHaveLength(1);
    const wholesaleOrder = wholesaleOrders?.[0] as { order_id: string; total_amount: number; supplier_business_id: string };
    expect(wholesaleOrder.supplier_business_id).toBe(supplierOne);
    expect(Number(wholesaleOrder.total_amount)).toBe(108000);

    const { data: heldRows, error: heldError } = await buyer.client
      .from("inventory_reservations").select("quantity,status").eq("order_id", wholesaleOrder.order_id);
    expect(heldError).toBeNull();
    expect(heldRows).toEqual([{ quantity: 12, status: "held" }]);

    const { data: committedCount, error: commitError } = await admin.rpc("confirm_inventory_reservation", {
      p_order_id: wholesaleOrder.order_id,
    });
    expect(commitError).toBeNull();
    expect(committedCount).toBe(1);
    const { data: committedRows, error: committedError } = await buyer.client
      .from("inventory_reservations").select("status").eq("order_id", wholesaleOrder.order_id);
    expect(committedError).toBeNull();
    expect(committedRows).toEqual([{ status: "committed" }]);
    const { data: committedProduct, error: committedProductError } = await admin
      .from("products").select("stock_quantity,reserved_quantity,available_quantity")
      .eq("id", wholesaleProductId).single();
    expect(committedProductError).toBeNull();
    expect(committedProduct?.stock_quantity).toBe(18);
    expect(committedProduct?.reserved_quantity).toBe(0);
    expect(committedProduct?.available_quantity).toBe(18);

    const { data: sampleRequestId, error: sampleError } = await buyer.client.rpc("create_product_sample_request", {
      p_buyer_business_id: buyerBusiness,
      p_product_id: wholesaleProductId,
      p_quantity: 1,
      p_delivery_address: "بغداد، الكرادة، شارع ١",
    });
    expect(sampleError).toBeNull();
    expect(sampleRequestId).toBeTruthy();

    const { data: invoiceId, error: invoiceError } = await supplierA.client.rpc("create_proforma_invoice", {
      p_order_id: wholesaleOrder.order_id,
      p_valid_until: null,
      p_terms: "عرض أولي للاختبار",
    });
    expect(invoiceError).toBeNull();
    expect(invoiceId).toBeTruthy();
    const { data: buyerInvoice, error: buyerInvoiceError } = await buyer.client
      .from("proforma_invoices").select("id,subtotal").eq("id", invoiceId).single();
    expect(buyerInvoiceError).toBeNull();
    expect(Number(buyerInvoice?.subtotal)).toBe(108000);

    await page.goto("/");
    await expect(page.getByText("سوق الجملة، أقرب إليك")).toBeVisible();
  } finally {
    for (const actor of actors) {
      await admin.auth.admin.deleteUser(actor.id);
    }
  }
});
