export function formatRelativeMinutes(minutes: number) {
  if (minutes <= 0) {
    return "Saved just now";
  }
  if (minutes === 1) {
    return "Saved 1 minute ago";
  }
  return `Saved ${minutes} minutes ago`;
}
