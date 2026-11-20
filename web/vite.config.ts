import react from "@vitejs/plugin-react";
import { defineConfig } from "vitest/config";

// Rails renders the HTML shell (so the CSRF token is embedded) and Vite only
// serves JavaScript and CSS.
//
// Development: open http://localhost:5173. Vite answers its own paths and
// proxies everything else (the shell, /api, the HTML sign-in) to Rails on
// :3000, so the browser only ever sees one origin.
//
// Production: `vite build` writes hashed files plus a manifest to
// public/spa, which Rails' ViteHelper reads.
const RAILS = process.env.RAILS_URL ?? "http://127.0.0.1:3000";
// Vite only answers localhost by default. To open the dev server through
// another name (a tunnel, a VM, a cloud preview), list it here:
// VITE_ALLOWED_HOSTS=dev.example.com,.preview.example.net
const ALLOWED_HOSTS = process.env.VITE_ALLOWED_HOSTS?.split(",")
  .map((host) => host.trim())
  .filter(Boolean);
const VITE_OWN_PATHS = "@vite/|@react-refresh|@id/|@fs/|src/|node_modules/|__vite";

export default defineConfig(({ command }) => ({
  plugins: [react()],
  base: command === "build" ? "/spa/" : "/",
  build: {
    outDir: "../public/spa",
    emptyOutDir: true,
    manifest: true,
    rollupOptions: { input: "src/main.tsx" },
  },
  server: {
    host: "0.0.0.0",
    port: 5173,
    strictPort: true,
    ...(ALLOWED_HOSTS?.length ? { allowedHosts: ALLOWED_HOSTS } : {}),
    proxy: {
      [`^/(?!${VITE_OWN_PATHS}).*`]: { target: RAILS },
    },
  },
  test: {
    environment: "jsdom",
    environmentOptions: { jsdom: { url: "http://localhost:5173/" } },
    include: ["src/**/*.test.{ts,tsx}"], // e2e/ is Playwright's
    setupFiles: ["src/test/setup.ts"],
    restoreMocks: true,
  },
}));
