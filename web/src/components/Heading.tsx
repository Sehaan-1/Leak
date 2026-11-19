import { type ReactNode, useEffect, useRef } from "react";

/** A page <h1> that takes focus when `focus` is set, so screen readers announce the new view. */
export function PageHeading({ focus, children }: { focus: boolean; children: ReactNode }) {
  const ref = useRef<HTMLHeadingElement>(null);
  useEffect(() => {
    if (focus) ref.current?.focus();
  }, [focus]);
  return (
    <h1 ref={ref} tabIndex={-1}>
      {children}
    </h1>
  );
}
