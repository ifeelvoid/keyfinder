# Repair release entry points and plugin analysis lifetime
**Serial:** #0008 · **Created:** 2026-10-17T20:25:18.832634+00:00 · **Author:** ifeelvoid@proton.me · **Depends on:** #0007

## Claim and outcome
Resolve the actionable code defects left by the deep audit: obsolete build/release routes, mixed plugin result attribution and unsafe worker timeout teardown. Keep tests meaningful and verify current artifacts. Attempt local XCTest using installed tools without accepting licenses or changing machine-wide settings.

## Anchor and constraints
Inspect current scripts and worker ownership before implementation. Preserve inherited dirty work/current branch, catalog files, installed plugins and app, credentials and prior artifacts. No commit/push/release/notarization submission/plugin install/shared memory save. Local packaging/build verification and isolated script fixtures are authorized. Avoid external account actions.

## Plan
Independent script and plugin fixes; regression tests reproduce old behavior before fixes where feasible. Root investigates XCTest execution and coordinates required general/C++ reviews and final verification.

## Risks
A worker captures processor members; cancellation must cover detector loops and teardown must finish joining jobs before member destruction. Result source must remain coherent across queued file/live work. Scripts must package dist artifacts using current metadata, preserve rollback and make external notarization explicit.

## Acceptance
Current build entry points use CMake and current dist outputs. Tests cover script routing/failure behavior, plugin source results/cancellation/teardown, existing audio pass-through and regression behavior. Required reviews pass. Genuine environment/physical acceptance gaps remain explicit.
