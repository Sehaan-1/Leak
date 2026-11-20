import { useMutation, useQueryClient } from "@tanstack/react-query";
import { type FormEvent, useRef, useState } from "react";
import { isDemoInstance, signIn, startDemo } from "../api/client";
import { useFieldErrors } from "../lib/fieldErrors";
import { useTitle } from "../lib/title";
import { PageHeading } from "./Heading";

export function SignIn({ focusHeading }: { focusHeading: boolean }) {
  const queryClient = useQueryClient();
  const formRef = useRef<HTMLFormElement>(null);
  useFieldErrors(formRef);
  const [showPassword, setShowPassword] = useState(false);
  useTitle("Sign in");

  const demo = isDemoInstance();
  const demoMutation = useMutation({
    mutationFn: startDemo,
    onSuccess: (me) => queryClient.setQueryData(["me"], me),
  });

  const mutation = useMutation({
    mutationFn: (credentials: { email: string; password: string }) =>
      signIn(credentials.email, credentials.password),
    onSuccess: (me) => queryClient.setQueryData(["me"], me),
  });

  function onSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const field = (name: string) => (event.currentTarget.elements.namedItem(name) as HTMLInputElement).value;
    mutation.mutate({ email: field("email_address"), password: field("password") });
  }

  return (
    <main className="page narrow">
      <PageHeading focus={focusHeading}>{demo ? "Try Leak" : "Sign in to Leak"}</PageHeading>
      {demo && (
        <section aria-labelledby="demo-heading">
          <h2 id="demo-heading" className="visually-hidden">
            Try it with made-up data
          </h2>
          <p>
            Leak finds the subscriptions in a bank statement, tells you when one costs more, and spots when
            you're paying for the same thing twice.
          </p>
          <p>
            Try it on a year of a made-up SBI statement. Nothing is uploaded, and your demo account is deleted
            after a day.
          </p>
          <button type="button" onClick={() => demoMutation.mutate()} disabled={demoMutation.isPending}>
            {demoMutation.isPending ? "Setting up your demo…" : "Try it with made-up data"}
          </button>
          <div role="alert" className="form-error">
            {demoMutation.isError && demoMutation.error.message}
          </div>
        </section>
      )}
      {demo && <h2>Have an account? Sign in</h2>}
      <form ref={formRef} method="post" action="/session" onSubmit={onSubmit}>
        <div className="field">
          <label htmlFor="email">Email address</label>
          <input
            id="email"
            name="email_address"
            type="email"
            autoComplete="username"
            autoCapitalize="none"
            autoCorrect="off"
            spellCheck={false}
            enterKeyHint="next"
            required
            data-error="email-error"
          />
          <p id="email-error" className="error-msg">
            <span aria-hidden="true">⚠ </span>Enter your email address, like name@example.com.
          </p>
        </div>

        <div className="field">
          <label htmlFor="current-password">Password</label>
          <div className="with-button">
            <input
              id="current-password"
              name="password"
              type={showPassword ? "text" : "password"}
              autoComplete="current-password"
              enterKeyHint="done"
              required
              data-error="password-error"
            />
            <button
              type="button"
              className="secondary"
              aria-pressed={showPassword}
              aria-controls="current-password"
              onClick={() => setShowPassword((shown) => !shown)}
            >
              Show password
            </button>
          </div>
          <p id="password-error" className="error-msg">
            <span aria-hidden="true">⚠ </span>Enter your password.
          </p>
        </div>

        {/* Always in the page, so filling it in is announced. */}
        <div role="alert" className="form-error">
          {mutation.isError && mutation.error.message}
        </div>

        <button type="submit" disabled={mutation.isPending}>
          {mutation.isPending ? "Signing in…" : "Sign in"}
        </button>
      </form>
      <p>
        <a href="/passwords/new">Forgot your password?</a>
      </p>
    </main>
  );
}
