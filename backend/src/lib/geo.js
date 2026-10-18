// Haversine, identik dengan fn_distance_km lama (R = 6371 km).
const rad = (d) => (d * Math.PI) / 180;
export function distanceKm(lat1, lon1, lat2, lon2) {
  const a =
    Math.sin(rad(lat2 - lat1) / 2) ** 2 +
    Math.cos(rad(lat1)) * Math.cos(rad(lat2)) * Math.sin(rad(lon2 - lon1) / 2) ** 2;
  return 2 * 6371.0 * Math.asin(Math.sqrt(Math.min(1.0, a)));
}

export function maskName(p) {
  if (p == null || p === '') return '***';
  const c = [...p];
  if (c.length <= 2) return c[0] + '***';
  return c.slice(0, 2).join('') + '***' + c[c.length - 1];
}
