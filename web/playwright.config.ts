import { defineConfig, devices } from "@playwright/test";

// One end-to-end flow against the real stack: Rails (test environment)
// serving the built SPA, on a database seeded with the synthetic demo
// household (db/seeds.rb). CI prepares both; locally:
//
//   npm run build
//   RAILS_ENV=test bin/rails db:reset          # from the repo root
//   npm run e2e
//
// The flow answers a review question, so seed again before re-running.
const BASE_URL = process.env.E2E_BASE_URL ?? "http://localhost:3000";

export default defineConfig({
  testDir: "./e2e",
  forbidOnly: !!process.env.CI,
  retries: 0,
  workers: 1,
  reporter: process.env.CI ? [["github"], ["html", { open: "never" }]] : "list",
  use: {
    baseURL: BASE_URL,
    locale: "en-IN",
    timezoneId: "Asia/Kolkata",
    trace: "retain-on-failure",
    screenshot: "only-on-failure",
  },
  projects: [{ name: "chromium", use: { ...devices["Desktop Chrome"] } }],
  ...(process.env.E2E_BASE_URL
    ? {}
    : {
        webServer: {
          command: "bin/rails server -p 3000 -b 127.0.0.1",
          cwd: "..",
          url: `${BASE_URL}/up`,
          env: { RAILS_ENV: "test" },
          reuseExistingServer: !process.env.CI,
          timeout: 120_000,
          stdout: "pipe",
        },
      }),
});
