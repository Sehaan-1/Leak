// Keeps aria-invalid and the error text in step with the visual :user-invalid
// state, so a screen reader hears an error only once the user has interacted
// with a field — never on page load. Usage: call useFieldErrors(formRef) for a
// <form>, give each field data-error="<id of its error message>", and render
// one <LiveAnnouncer> on the page.
import { type RefObject, useEffect } from "react";

type Field = HTMLInputElement | HTMLSelectElement | HTMLTextAreaElement;

const isField = (el: EventTarget | null): el is Field =>
  el instanceof HTMLInputElement || el instanceof HTMLSelectElement || el instanceof HTMLTextAreaElement;

// Fallback for engines without :user-invalid: a field counts as interacted
// once it has been edited and left, or a submit attempt flagged it.
const edited = new WeakSet<Field>();
const interacted = new WeakSet<Field>();

let userInvalidSupported: boolean | undefined;
function matchesUserInvalid(el: Field): boolean {
  userInvalidSupported ??= typeof CSS !== "undefined" && CSS.supports("selector(:user-invalid)");
  return userInvalidSupported ? el.matches(":user-invalid") : interacted.has(el) && !el.validity.valid;
}

// The error's id is listed in aria-describedby only while it's shown: text that
// aria-describedby references is announced even when it's hidden.
function linkError(el: Field, shown: boolean) {
  const errorId = el.dataset.error;
  if (!errorId) return;
  const ids = (el.getAttribute("aria-describedby") ?? "").split(/\s+/).filter((id) => id && id !== errorId);
  if (shown) ids.push(errorId);
  if (ids.length) el.setAttribute("aria-describedby", ids.join(" "));
  else el.removeAttribute("aria-describedby");
}

// One polite live region per page (see LiveAnnouncer.tsx).
export const ANNOUNCER_ID = "field-error-announcer";
let announceTimer: ReturnType<typeof setTimeout> | undefined;
let announcedField: Field | undefined;

function spokenText(node: Element): string {
  const copy = node.cloneNode(true) as Element;
  for (const hidden of copy.querySelectorAll('[aria-hidden="true"]')) hidden.remove();
  return (copy.textContent ?? "").replace(/\s+/g, " ").trim();
}

function announceError(el: Field) {
  const error = el.dataset.error ? document.getElementById(el.dataset.error) : null;
  const announcer = document.getElementById(ANNOUNCER_ID);
  if (!error || !announcer) return;
  const label = el.labels?.[0] ? `${spokenText(el.labels[0])}: ` : "";
  clearTimeout(announceTimer);
  announcer.textContent = "";
  announcedField = el;
  // Wait until the screen reader has announced the field that receives focus next.
  announceTimer = setTimeout(() => {
    announcer.textContent = label + spokenText(error);
  }, 500);
}

const flagged = new WeakSet<Field>();
const announced = new WeakSet<Field>();

export function syncAria(el: Field, announce = false) {
  if (matchesUserInvalid(el)) {
    if (announce && !announced.has(el)) {
      announceError(el);
      announced.add(el);
    }
    el.setAttribute("aria-invalid", "true");
    linkError(el, true);
    flagged.add(el);
  } else if (flagged.has(el) || el.getAttribute("aria-invalid") !== "true") {
    el.setAttribute("aria-invalid", "false");
    linkError(el, false);
    flagged.delete(el);
    announced.delete(el);
    if (announcedField === el) {
      clearTimeout(announceTimer);
      const announcer = document.getElementById(ANNOUNCER_ID);
      if (announcer) announcer.textContent = "";
    }
  }
}

/**
 * Wires a form up. Native listeners rather than React props, because 'invalid'
 * doesn't bubble and React attaches it to each element, not the form.
 */
export function useFieldErrors(formRef: RefObject<HTMLFormElement | null>) {
  useEffect(() => {
    const form = formRef.current;
    if (!form) return;

    // Start at aria-invalid="false": Firefox and Safari expose an empty
    // required field as invalid from page load.
    for (const el of form.elements) if (isField(el)) syncAria(el);

    const onBlur = (e: Event) => {
      if (!isField(e.target)) return;
      if (edited.has(e.target)) interacted.add(e.target);
      syncAria(e.target, true);
    };
    const onInput = (e: Event) => {
      if (!isField(e.target)) return;
      edited.add(e.target);
      if (e.target.hasAttribute("aria-invalid")) syncAria(e.target);
    };
    // File pickers and checkboxes commit on change without losing focus.
    const onChange = (e: Event) => {
      if (!isField(e.target)) return;
      edited.add(e.target);
      if (e.target.type === "file" || e.target.type === "checkbox") interacted.add(e.target);
      syncAria(e.target, true);
    };
    // A failed submit fires 'invalid' on each failing field. Native validation then
    // moves focus to the first one, which announces its error, so don't announce here.
    const onInvalid = (e: Event) => {
      if (!isField(e.target)) return;
      interacted.add(e.target);
      announced.add(e.target);
      syncAria(e.target);
    };
    // Reset clears :user-invalid after the 'reset' event, so resync afterwards.
    const onReset = () => {
      setTimeout(() => {
        for (const el of form.elements) {
          if (!isField(el)) continue;
          edited.delete(el);
          interacted.delete(el);
          syncAria(el);
        }
      });
    };

    form.addEventListener("blur", onBlur, true);
    form.addEventListener("input", onInput);
    form.addEventListener("change", onChange, true);
    form.addEventListener("invalid", onInvalid, true);
    form.addEventListener("reset", onReset);
    return () => {
      form.removeEventListener("blur", onBlur, true);
      form.removeEventListener("input", onInput);
      form.removeEventListener("change", onChange, true);
      form.removeEventListener("invalid", onInvalid, true);
      form.removeEventListener("reset", onReset);
    };
  }, [formRef]);
}
