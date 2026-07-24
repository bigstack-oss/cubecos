---
name: Bug Report
about: Create a report to help us improve
title: '[Bug]: '
labels: 'bug'
type: Bug
assignees: ''

---

## Describe the bug

>A clear and concise description of what the bug is.

Insert content here.

## Affected Component / Service

>Which repo, service, or subsystem is this bug in?
[e.g. `cube-cos-api`, `workloadmgr`/Trilio WLM, `contego`/Datamover, Horizon dashboard, install.sh]

## Version

> - Product/Fixpack version: [e.g. CubeCOS 3.1.0-002, CubeDPX 5.27]
> - Component version (if different from product version): [e.g. cube-cos-api commit/tag]

What version of the product is affected [e.g. 3.x.x].

## To Reproduce

>Steps to reproduce the behavior. For UI bugs, describe the click path
(1. Go to '...' 2. Click on '....' 3. See error). For backend/API/CLI bugs,
describe the command(s) run, the API call, or the code path exercised instead.

1. Go to '...'
2. Click on '....'
3. Scroll down to '....'
4. See error

## Expected behavior

>A clear and concise description of what you expected to happen.

Insert content here.

## Root Cause (if known)

> Skip this section if you haven't investigated the cause yet — that's fine,
> triage can fill it in. If you have traced it, put the specifics here:
> affected file/function/line, the exact mechanism, and how you confirmed it
> (log excerpt, code snippet, reproduction steps).

Insert content here.

## Suggested Fix (Optional)

> If you have a concrete fix in mind (even just a one-liner), put it here.

Insert content here.

## Screenshots (Optional)

>If applicable, add screenshots to help explain your problem.

## Additional Context (Optional)

>Add any other context about the problem here.
>- Cluster topology: [e.g. single control-converged node, 3 control + 2 compute HA]
>- Hardware: [e.g. Dell PowerEdge R630, storage backend NFS/S3/Ceph]
>- Supporting logs

## Output artifacts (Definition of Done)

> Beyond code, docs, and config changes, completing this issue must also deliver:

- [ ] **Handbook knowledge update** — land the durable, team-readable knowledge from this
      work into the bigstack-handbook cubecos kb (`kb/cubecos/…`) via
      `/bigstack-core:save-to-handbook` (Topic / Runbook / Known-issue / ADR as fits).
