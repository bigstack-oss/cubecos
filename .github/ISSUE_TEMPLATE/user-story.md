---
name: User Story
about: A concise statement written from the perspective of the person requesting a
  new capability; it defines their role, the action they want to take, and the expected
  outcome.
title: "[User Story] "
labels: ''
type: "User Story"
assignees: ''

---

## Description

As a **[type of user]**, I want **[some goal]** so that **[some reason]**.

## Acceptance Criteria

> A detailed list of conditions that must be met for the story to be accepted. These statements must focus on functional behavior and constraints rather than specific code-level implementation.

- [ ] Condition 1
- [ ] Condition 2
- [ ] Condition 3

## Story Points: ❓ 

>| Points | Effort / Resources | Description |
> | -- | -- | -- |
>| 1 | Low | Low complexity; can be resolved easily.
>| 3 | Medium | Moderate workload; requires some focus, but risks are well-managed.
>| 5 | High | High complexity; difficult to implement, requiring significant time and effort.
>| 8 | Very High | Extreme complexity or high uncertainty. If possible, this should be divided into multiple user stories.

## QA Verification

> How QA verifies this story once it ships — write **checkable claims**: the exact
> command or click path plus the expected outcome. "Verify it works" is not a checkable
> claim. These claims are what the Qase test suite is generated from, so write them for a
> reader who has not seen the code.

| # | Command / steps | Expected outcome |
|---|---|---|
| 1 | `...` | `...` |

- [ ] **QA Status declared at Done** — when this issue reaches `Done`, set the board's
      `QA Status` field to `Not needed` or `Ready to QA`. Never leave it empty on a Done
      ticket; `In QA` / `Verified` are QA's own transitions.

## Output artifacts (Definition of Done)

> Beyond code, docs, and config changes, completing this issue must also deliver:

- [ ] **Handbook knowledge update** — land the durable, team-readable knowledge from this
      work into the bigstack-handbook cubecos kb (`kb/cubecos/…`) via
      `/bigstack-core:save-to-handbook` (Topic / Runbook / Known-issue / ADR as fits).
      Diagnosed or fixed a failure? Ship the scenario sidecar (`<note>.scenario.yaml`)
      beside the note.
