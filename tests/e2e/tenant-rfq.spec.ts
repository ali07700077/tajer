import { test, expect } from "@playwright/test";
import { createClient, type SupabaseClient } from "@supabase/supabase-js";
import { randomUUID } from "node:crypto";

// Supabase CLI exports API_URL / ANON_KEY / SERVICE_ROLE_KEY into GITHUB_ENV.
// Support those names as well as explicit SUPABASE_* variables used locally.
const url = process.env.SUPABASE_URL || process.env.API_URL || "";
const anonKey = process.env.SUPABASE_ANON_KEY || process.env.ANON_KEY || "";
const serviceKey = process.env.SUPABASE_SERVICE_ROLE_KEY || process.env.SERVICE_ROLE_KEY || "";
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
  expect(url, "Supabase URL must be supplied by the local Supabase CLI").toMatch(/^https?:\\/\\//);
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

    await page.goto("/");
    await expect(page.getByText("سوق الجملة، أقرب إليك")).toBeVisible();
  } finally {
    for (const actor of actors) {
      await admin.auth.admin.deleteUser(actor.id);
    }
  }
});
