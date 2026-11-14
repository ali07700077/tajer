import { test, expect } from "@playwright/test";

test("Arabic live logistics workspace renders Iraq map and tracking controls", async ({ page }) => {
  await page.goto("/");
  await page.getByRole("button", { name: "تتبع الشحنات" }).click();
  const workspace = page.getByTestId("live-tracking-workspace");
  await expect(workspace).toBeVisible();
  await expect(workspace).toContainText("التتبع اللوجستي الحي");
  await expect(workspace).toContainText("OpenStreetMap");
  await expect(workspace.getByRole("combobox", { name: "اختيار الشحنة" })).toBeVisible();
  await expect(workspace.getByRole("button", { name: "تحديث موقعي الحالي (GPS)" })).toBeDisabled();
  await expect(workspace.getByRole("button", { name: "تحقق وأكد التسليم" })).toBeDisabled();
  await expect(workspace.getByRole("img", { name: "خريطة العراق والشحنات" })).toBeVisible();
});

test("shipment tracking exposes a manual OTP fallback for delivery confirmation", async ({ page }) => {
  await page.goto("/");
  await page.getByRole("button", { name: "تتبع الشحنات" }).click();
  const workspace = page.getByTestId("live-tracking-workspace");
  await expect(workspace.getByRole("textbox", { name: "OTP لتأكيد التسليم" })).toBeVisible();
  await workspace.getByRole("textbox", { name: "OTP لتأكيد التسليم" }).fill("ABC123");
  await expect(workspace.getByRole("button", { name: "تحقق وأكد التسليم" })).toBeDisabled();
});
