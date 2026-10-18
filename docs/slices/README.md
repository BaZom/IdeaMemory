# Slices

A slice is the next small thing you can use on your phone, end to end (design, app, API, database). Slices are written **just in time**: only the current one and the next one exist in detail; later ones are a line in the [roadmap](../roadmap.md).

**How the end goal stays in view:**

- The end goal is fixed in the [concept](../concept.md) and the [target design](../design/oh-app.html). Every slice says which part of it it builds (*Towards*) and what it leaves out on purpose.
- **Design the data for the end goal, build the screens for the near goal.** A slice’s data model already fits later slices (owner per memory, “who it’s for” as names that later link to spaces), so later slices add, they don’t migrate.
- Ideas that come up while working go to *Parked* in the slice, not into the code.
- After each milestone: a short review, then update the concept, the target design and the roadmap if reality taught us something.

**Each slice has:**

1. `docs/slices/<n>-<name>.md` with the sections below.
2. A design board `docs/design/slices/<n>-<name>.html`: the screens of *this slice only*, cut down from the target design, with the states the target skips (empty, error, offline, editing, deleting, dark mode).

**Workflow:** the owner reviews the slice and its design → build it → try it on the phone → mark it done in the roadmap.

## Template

```markdown
# <n> — <what you can do afterwards>

Status: draft | agreed | building | done
Milestone: M1 Just me v1

## Goal
One sentence.

## Towards
Which part of the concept and target design this builds. What it leaves out on purpose.

## Design
Link to the design board; the screens and states; the words used.

## Data
Tables and columns, with what later slices will add.

## API and app
Routes, request and response changes; app pages and components.

## Security and privacy
Who may read and write what; what is never logged.

## Done when
What you check on your phone.

## Not now

## Open questions

## Parked
```
