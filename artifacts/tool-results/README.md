# Tool Result Artifacts

This directory is for large command-output artifacts written by the
harness. `README.md` is active managed source. `*.txt` files are ignored
runtime output and historical evidence, not fresh validation unless the
current run names the file and timestamp.

Do not copy live runtime logs, secrets, sessions, SQLite state, browser
state, or raw prompt payloads here. Prefer current command reruns, keep
artifact references in reports or trajectories, and handle deletion or
archiving in a separate bounded cleanup pass.
