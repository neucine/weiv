export function metricToneClass(change) {
  if (change > 0) {
    return "metric-card--up";
  }
  if (change < 0) {
    return "metric-card--down";
  }
  return "metric-card--flat";
}
