---
name: Feature
about: A distinct unit of functionality or a significant part that forms a specific
  user story.
title: "[Feature] "
labels: ''
type: Feature
assignees: ''

---

## Description

> A brief summary to help everyone understand this feature.

Insert content here.

## Definition of Done (DoD)

> A list of technical requirements must be met for completion. These may include, but are not limited to:
>  - API data conforming to a specified structure.
>  - An UI delivering defined functionalities.
>  - Passing all unit tests.
>  - Passing a code review.

- [ ] Condition 1
- [ ] Condition 2
- [ ] Condition 3

## Technical Notes

> A section for tech leads to to document technical risks and/or any concerns regarding the DoD.

- **Feature Owner:**
- **Frontend:** 
- **Backend:** 
- **Infra:**

## UI/UX Mockups (Optional)

> Links to design prototypes or wireframes (if applicable).

None

## QA Verification

> How QA verifies this feature once it ships — write **checkable claims**: the exact
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
