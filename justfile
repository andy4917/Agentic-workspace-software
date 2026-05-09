set shell := ["powershell", "-NoProfile", "-ExecutionPolicy", "Bypass", "-Command"]

default:
    just --list

# Show the current runtime, ledger, and report summary.
summary:
    python -m Tools.harness_py summary

# Show runtime JSONL ledger counts and recent timestamps.
ledgers:
    python -m Tools.harness_py ledgers

# Show the latest Maintenance report headings and verdict/status lines.
reports:
    python -m Tools.harness_py reports

# Parse the hook runner with the PowerShell AST without executing it.
hook-parse:
    powershell -NoProfile -ExecutionPolicy Bypass -File Maintenance/Test-HookParse.ps1

# Run the existing final runtime proof report writer.
final-runtime-proof:
    powershell -NoProfile -ExecutionPolicy Bypass -File Maintenance/Run-FinalRuntimeProof.ps1
