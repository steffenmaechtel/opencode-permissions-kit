# Evaluate

Evaluation records for third-party tools and addons that could extend,
complement, or replace the kit's model. Each record answers one
question: **what would this add to (or change about) the opencode
permissions kit, and does it fit?**

These are decision documents, not user documentation — verdicts are
recorded per tool with date and issue reference. Where a verdict says
"conflicting", the record explains which kit guarantee or requirement
collides. Re-evaluation is welcome: open an issue when a tool changed
materially.

## Areas

- [Container tools / sandboxes](container-tools/README.md) — OS-level
  sandboxing for the agent (issue #40)
- [DDEV addons](ddev-addons/README.md) — running opencode inside DDEV
  containers (issue #41)

## Verdict vocabulary

| Verdict | Meaning |
|---|---|
| Adopt | use it in the kit |
| Complementary | usable alongside the kit for specific projects/workflows |
| Conflicting | collides with a kit guarantee or the ddev-must-work requirement |
| Not applicable | targets a different problem or replaces the model entirely |
