import { expect, test } from "@playwright/test";

test("release notes disclose where recordings and transcript text are processed", async ({ page }) => {
  await page.goto("/releases");
  const notes = page.locator("article[id='v1.0'] .prose");
  await expect(notes).toContainText("Apple Speech transcribes meeting audio on your Mac by default");
  await expect(notes).toContainText("Choosing ElevenLabs sends it the combined recording");
  await expect(notes).toContainText("Choosing OpenAI or Anthropic sends transcript text to that provider");
  await expect(notes).toContainText("Claude Code sends text to Anthropic");
});

test("site previews describe the on-device defaults", async ({ page }) => {
  await page.goto("/");
  for (const selector of ["meta[name=description]", 'meta[property="og:description"]']) {
    await expect(page.locator(selector)).toHaveAttribute("content", /On-device transcription and notes by default/);
  }
});

test("FAQ discloses where dictation clean-up sends text", async ({ page }) => {
  await page.goto("/");
  await expect(page.locator("body")).toContainText("If dictation clean-up uses OpenAI, Anthropic or Claude Code, the dictated text goes to that provider");
});
