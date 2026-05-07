package patchbench

deny contains msg if {
  input.bench_suite != "local-reward-nullification-bench-v0.1"
  msg := "bench_suite must be local-reward-nullification-bench-v0.1"
}

deny contains msg if {
  not input.required_gates.definition_of_done.required
  msg := "Definition of Done gate is required"
}

deny contains msg if {
  not input.required_gates.ci_gate.required
  msg := "CI gate is required"
}

deny contains msg if {
  not input.required_gates.release_gate.required
  msg := "release gate is required"
}

deny contains msg if {
  not input.required_gates.quality_gate.required
  msg := "quality gate is required"
}

deny contains msg if {
  not input.required_gates.change_impact_analysis.required
  msg := "change impact analysis is required"
}
