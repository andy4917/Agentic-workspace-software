import assert from "node:assert/strict";
import test from "node:test";

import { add, assertCoverageSmoke } from "../coverage-smoke.js";

test("coverage smoke uses runtime inputs", () => {
  const inputs = [
    [1, 2],
    [5, 8],
    [-3, 4]
  ];

  const outputs = inputs.map(([left, right]) => add(left, right));

  assert.deepEqual(outputs, [3, 13, 1]);
  assert.equal(assertCoverageSmoke(), "coverage smoke ok");
});
