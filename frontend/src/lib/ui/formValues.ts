/** Converts a form value into a positive whole-minute estimate. */
export function estimateMinutes(value: FormDataEntryValue | null): number | null {
  const minutes = Number(value);
  return Number.isInteger(minutes) && minutes > 0 ? minutes : null;
}

/** Converts the comma-separated labels field into trimmed non-empty labels. */
export function parseLabels(value: FormDataEntryValue | null): string[] {
  return String(value ?? '').split(',').map((label) => label.trim()).filter(Boolean);
}
