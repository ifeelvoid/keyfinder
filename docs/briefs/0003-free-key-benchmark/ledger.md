# Free key benchmark execution
blc/2 #0003 done a:done b:done c:done

Brief: brief.md. Started 2026-10-11. Local branch: codex/mik-key-analysis, reusing the isolated checkout and preserving #0002 work.

## Phases

- a — research and orientation: done. Independent project chats own library and data reports.
- b — benchmark tooling: done. Worker owns tools/free-key-benchmark/ and its tests.
- c — skill and validation: done. Root owns Codex skill, integration, pilot execution, and final reporting.

Dependency: a research tracks run in parallel; b framework work can proceed against known schemas while reference selection finishes; c follows b.

## Decisions and evidence

- tools/orient.sh and repository AGENTS.md/CLAUDE.md are absent. Existing current source, benchmark, and brief records inspected.
- No commit/push/native-memory mirror: Alexander has not requested either. User authorization permits local execution and split project chats.
- No production detector change until independent evaluation supports a concrete improvement.
- Existing worktree reused to preserve inherited source changes; no extra branch mutation required.

## Open items

Reference compatibility, dataset audio availability, verified labels, model overlap with test songs, local reference results, code review, and skill installation/validation.

- Created KeyFinder project chats: `01a12d22-6ba8-7431-af4c-d150bb7a3f32` (libraries), `01a12d22-a850-7892-8bf0-3a3d90fddd5d` (datasets). Root collects their results here.
- Delegated only tools/free-key-benchmark/ to benchmark_tooling worker; root owns skill and integration.
- Prepared project skill under skills/keyfinder-benchmark/; global installation awaits validation.
- Created isolated Python 3.12.13 environment at dist/free-key-benchmark-venv. Free librosa dependency install in progress; system Python and apps untouched.

## Execution evidence

- Both project research chats completed their assigned reports (libraries.md, datasets.md), collected by root. Public dataset audio access established with one ranged/CRC-checked MP3.
- Librosa1.0.0 and Essentia2.1b6.dev1389 both successfully processed the12catalogpilotrecordings in the isolated Python3.12.13 environment. Full recordings; audio hashes unchanged. Exact agreement with current KeyFinder:7/12 and9/12 respectively. These are development agreement measurements, not accuracy.
- Essentia initial synthetic probe interrupted during dynamic native algorithm initialization; subsequent actual full pilot completed12/12. This supersedes the library report's earlier inference-unverified snapshot.
- keyfinder-benchmark skill validated by official skill validator, installed globally at ~/.codex/skills/keyfinder-benchmark with source-copy SHA verification.
- Worker completed analyze/labels-template/evaluate plus23 passing unit tests. Root reran23tests successfully. Reviewer found and worker fixed identical-recording family/split leakage and contradictory normalized key labels. Final review: no unresolved blocking findings. Black formatting is advisory; no configured gate exists.
- Review CSV contains12blank verified-label rows; attempted evaluation refused with no independently reviewed labels and created no accuracy artifact.
- GiantSteps+ v2 annotations.zip downloaded408580bytes, MD5 matches official603183d92916313c97dae51edac7655f; raw3271514JSON retained. Its source MP3 SHA verified. Restricted Swift run retained an Apple-decoder failure; permitted host rerun succeeded, returning A Minor against published A minor aeolian. One-sample development demonstration only.
- Current engine source digest485e3f3ef74005d459fd108606be71e95a90d38aae72baaa020c571d9396add5matches #0002 reviewed run. AppleSiliconpreview binary unchanged.
- No classifier training/tuning, global Python change, source audio change, external audio upload, app replacement, commit/push, or PR.

- Public sample end-to-end evaluation completed using the unchanged recording and published annotation: KeyFinder host, librosa and Essentia each returned A Minor. Restricted KeyFinder decode failure remains a separate attempted run, with0/1coverage rather than silently disappearing. This is one sample, not broad accuracy.

## Completion and next experiment

All #0003deliverables are complete: repeatable free tools, installed skill, two research reports, bounded actual comparisons, tested evaluation and independent review. The goal of being the best free detector is not established by these results. The next detector-development milestone is a frozen public challenge benchmark and new reviewed local song-family holdout, then changes selected from measured failures. Public annotations and native decode context must be retained; production classifier remains the verified #0002 implementation.

Task handoff: handoff.md. Observable artifacts: dist/free-key-benchmark/pilot-report.md, pilot-summary.json, review-labels.csv, individual raw reference runs, and giantsteps-sample/published-evaluation.json.
