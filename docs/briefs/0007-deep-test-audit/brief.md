# Deep test audit and evidence-based legacy cleanup
**Serial:** #0007 · **Created:** 2026-10-17T20:05:25.497574+00:00 · **Author:** ifeelvoid@proton.me · **Depends on:** #0006

## Claim and desired outcome
Trace suspected legacy paths to actual application, plugin, benchmark and test entrypoints. Remove only code proven obsolete, fix genuine bugs, preserve useful regression coverage and report checks and blockers.

## Constraints
Preserve inherited dirty work and the current branch. Local audit only: no commit, push, release, install or audio mutation. No detector tuning against private catalog labels. Public APIs and historical benchmark baselines are retained unless demonstrably unreachable and unnecessary. Initial status, diff and file hashes preserved privately at /private/tmp/keyfinder-deep-audit/.

## Anchor and plan
Establish runnable baseline checks before edits. Independent read-only engine, plugin and app/tool audits inform a bounded set of changes. Then reproduce real bugs with meaningful tests, make the smallest coherent fixes/removals and review the final diff.

## Risks and evidence
Inherited changes span engine, app, plugin and release scripts. Xcode license/toolchain selection may prevent normal checks; Command Line Tools are available. Synthetic regression success does not prove private-catalog accuracy, host integration or physical Intel compatibility.

## Acceptance
Evidence for every removal and bug fix; relevant Swift, Python, JS and plugin checks run where available; remaining blockers explicitly recorded.
