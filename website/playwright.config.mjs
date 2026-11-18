import { defineConfig } from "@playwright/test";

export default defineConfig({
  testDir: "./tests",
  use: {
    baseURL: "http://127.0.0.1:4389",
    launchOptions: { executablePath: process.env.PLAYWRIGHT_CHROMIUM_EXECUTABLE },
  },
  webServer: { command: "npm run preview -- --ignore-lock --host 127.0.0.1 --port 4389", url: "http://127.0.0.1:4389" },
});
