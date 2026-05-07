export interface GateInput {
  readonly changedFiles: readonly string[];
  readonly gate: "ci" | "quality" | "release";
}

export interface GateDecision {
  readonly requiredChecks: readonly string[];
  readonly releaseEligible: boolean;
}

export function planGate(input: GateInput): GateDecision {
  const checks = new Set<string>(["test_runner", "lint", "typecheck", "policy_config_validator"]);

  if (input.changedFiles.some((file) => file.endsWith(".ps1") || file.endsWith(".yaml"))) {
    checks.add("local_gate_script");
  }

  if (input.gate === "release") {
    checks.add("semgrep");
    checks.add("change_impact");
  }

  return {
    requiredChecks: [...checks].sort(),
    releaseEligible: input.gate === "release" && checks.has("change_impact")
  };
}
