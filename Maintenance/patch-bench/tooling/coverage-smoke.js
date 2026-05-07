export function add(a, b) {
  return a + b;
}

export function assertCoverageSmoke() {
  if (add(2, 3) !== 5) {
    throw new Error("coverage smoke failed");
  }
  return "coverage smoke ok";
}
