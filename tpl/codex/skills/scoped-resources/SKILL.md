---
name: scoped-resources
description: Operate project containers, Multipass VMs or OpenShift resources using the resource prefix recorded in AGENTS.md.
---

Find the resource prefix in the active project instructions before changing
Podman containers or images, Multipass VMs, or OpenShift namespaces. If it is
unset, obtain a prefix before creating or changing resources.

For named resources, match the start of the name against the literal prefix,
including its trailing dash. For OpenShift, select the matching namespace
explicitly and inspect the current context before mutations. Preview exact
targets for bulk operations. A matching prefix scopes the targets; it does not
authorize deletion or other actions outside the user's request.

Avoid commands that operate on every resource, such as global prune, stop-all,
VM purge, or cluster-wide deletion. Do not alter unrelated resources. Report
the resources changed and the checks used to verify the requested result.
