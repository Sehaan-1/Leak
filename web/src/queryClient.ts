import { QueryClient } from "@tanstack/react-query";
import { ApiError } from "./api/client";

export function createQueryClient() {
  return new QueryClient({
    defaultOptions: {
      queries: {
        // Retrying a 4xx can't help; a flaky connection or 5xx might.
        retry: (failures, error) => !(error instanceof ApiError && error.status < 500) && failures < 2,
        refetchOnWindowFocus: false,
      },
    },
  });
}
