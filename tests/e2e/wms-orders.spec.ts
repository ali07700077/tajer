import { test, expect } from "@playwright/test";

test("Arabic WMS workspace renders region-aware warehouse and order controls", async ({ page }) => {
  await page.goto("/");
  await page.getByRole("button", { name: "الطلبات" }).click();
  const workspace = page.getByTestId("wms-workspace");
  await expect(workspace).toBeVisible();
  await expect(workspace).toContainText("إدارة الطلبات والمخازن");
  await expect(workspace).toContainText("مخازن الشركة");
  await expect(workspace).toContainText("الطلبات وإجراءاتها السريعة");
  await expect(workspace).toContainText("19 محافظة");
  await expect(workspace.locator("select[aria-label='تصفية الطلبات']")).toBeVisible();
});

test("WMS never renders privileged order actions without an RLS-visible order", async ({ page }) => {
  await page.goto("/");
  await page.getByRole("button", { name: "الطلبات" }).click();
  const workspace = page.getByTestId("wms-workspace");
  await expect(workspace).toBeVisible();
  const empty = workspace.getByTestId("orders-empty");
  if (await empty.isVisible().catch(() => false)) {
    await expect(workspace.getByRole("button", { name: "اعتماد فوري" })).toHaveCount(0);
    await expect(workspace.getByRole("button", { name: "رفض مع سبب" })).toHaveCount(0);
  }
});
