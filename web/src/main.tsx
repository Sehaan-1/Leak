// Initialises React Fast Refresh when Rails, not Vite, serves the HTML shell.
import "@vitejs/plugin-react/preamble";
import { QueryClientProvider } from "@tanstack/react-query";
import { StrictMode } from "react";
import { createRoot } from "react-dom/client";
import { App } from "./App";
import { loadTemporal } from "./lib/dates";
import { createQueryClient } from "./queryClient";
import "./styles.css";

await loadTemporal();

const root = document.getElementById("root");
if (!root) throw new Error("Missing #root element");

createRoot(root).render(
  <StrictMode>
    <QueryClientProvider client={createQueryClient()}>
      <App />
    </QueryClientProvider>
  </StrictMode>,
);
