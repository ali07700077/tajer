import { test, expect } from "@playwright/test";

test("Arabic RTL role switcher exposes roles and does not grant unavailable permissions", async ({ page }) => {
  await page.goto("/");
  const switcher = page.getByTestId("role-switcher");
  await expect(switcher).toBeVisible();
  await expect(page.locator("html")).toHaveAttribute("dir", /rtl/i).catch(async () => {
    await expect(page.locator(".app-shell")).toHaveAttribute("dir", "rtl");
  });

  await expect(page.getByTestId("role-retail_buyer")).toContainText("مشتري مفرد");
  await expect(page.getByTestId("role-wholesale_buyer")).toContainText("تاجر جملة");
  await expect(page.getByTestId("role-supplier")).toContainText("مورد");
  await expect(page.getByTestId("role-warehouse_manager")).toContainText("أمين مخزن");

  await expect(page.getByTestId("role-warehouse_manager")).toBeDisabled();
  await expect(page.getByTestId("role-retail_buyer")).toHaveAttribute("aria-pressed", "true");
  await expect(page.getByTestId("role-wholesale_buyer")).toBeDisabled();
  await expect(page.getByTestId("role-supplier")).toBeDisabled();
});
