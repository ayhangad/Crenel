import { expect, test } from "@playwright/test";

for (const motion of ["reduce", "no-preference"]) {
  test(`keyboard access to every panel and preview with motion set to ${motion}`, async ({ page }) => {
    await page.emulateMedia({ reducedMotion: motion });
    await page.goto("/");
    const tabs = page.getByRole("tablist", { name: "Notch sizes" }).getByRole("tab");
    await tabs.first().focus();
    for (const [key, index] of [["ArrowRight", 1], ["End", 2], ["ArrowRight", 0], ["ArrowLeft", 2], ["Home", 0]]) {
      await page.keyboard.press(key);
      await expect(tabs.nth(index)).toBeFocused();
      await expect(tabs.nth(index)).toHaveAttribute("aria-selected", "true");
      const panel = page.getByRole("tabpanel");
      await expect(panel).toHaveCount(1);
      await expect(panel).toHaveAttribute("id", await tabs.nth(index).getAttribute("aria-controls"));
    }
    await page.keyboard.press("Tab");
    await expect(page.getByRole("tabpanel")).toBeFocused();

    const preview = page.getByRole("button", { name: /Notch preview/ });
    await preview.focus();
    for (const state of ["dictation", "ready", "meeting"]) {
      await page.keyboard.press("ArrowRight");
      await expect(preview).toHaveAttribute("data-state", state);
    }
    await page.keyboard.press("Enter");
    await expect(preview).toHaveAttribute("aria-expanded", "true");
    await expect(preview).toHaveAttribute("data-state", "open");
    await page.keyboard.press("Space");
    await expect(preview).toHaveAttribute("aria-expanded", "false");
    await expect(preview).toBeFocused();
  });
}
