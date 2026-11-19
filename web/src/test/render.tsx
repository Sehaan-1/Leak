import { QueryClientProvider } from "@tanstack/react-query";
import { render } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { App } from "../App";
import { createQueryClient } from "../queryClient";

/** Renders the whole app at a hash route ("#/review"); the default is the findings screen. */
export function renderApp(route = "") {
  window.location.hash = route;
  const user = userEvent.setup();
  const client = createQueryClient();
  client.setDefaultOptions({ queries: { ...client.getDefaultOptions().queries, retry: false } });
  render(
    <QueryClientProvider client={client}>
      <App />
    </QueryClientProvider>,
  );
  return { user, client };
}
