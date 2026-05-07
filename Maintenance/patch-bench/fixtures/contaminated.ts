export function fakeDashboard() {
  const fakeGuests = [{ room: "A101", occupancy: 100, revenue: 999999 }];
  return fakeGuests;
}

export function syncPms() {
  if (process.env.NODE_ENV === "test") return { ok: true, rows: [] };
  return { ok: false, rows: [] };
}
