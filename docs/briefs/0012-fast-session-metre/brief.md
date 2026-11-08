# Fast double-time sessions keep their metre
**Serial:** #0012 · **Created:** 2026-11-02 · **Author:** ifeelvoid@proton.me · **Depends on:** #0011

## Outcome

#0011 made KeyFinder report the Ableton session tempo on 41 of 54 songs, up from 31. It also introduced a new error that the old detector did not make: fast trap sessions set at 141–174 BPM are read as 2/3 of the session (5 of 54 songs). Alexander approved a follow-up (2026-11-02, "Yes, open it").

The aim is to remove the 2/3 error on fast double-time sessions without giving back the half-time 80–90 BPM gains, measured on fresh truth that no #0011 decision has seen.

## Evidence (diagnosis on the #0011 songs, now development data)

| T02 | Session | #0011 comb | What decided it |
|---|---|---|---|
| T30 | 160 | 106.6 | Flat autocorrelation (r 0.68–0.86 at 1–16 beats). Comb 160 ≈ 106.7 (0.794 vs 0.786), so the 110-centred prior picks 2/3. |
| T24 | 160 | 106.6 | Flat autocorrelation; comb slightly prefers 106.7 (0.855 vs 0.816). |
| T36 | 174 | 116.1 | Flat autocorrelation (0.55–0.82). The prior decides. |
| T51 | 160 | 106.6 | Comb prefers 160 (0.751 vs 0.637); the prior (0.83 vs 1.0) flips it. |
| T29 | 141 | 94 | Comb prefers 70.5, the octave of the truth; the prior flips it to 2/3. |
| S81 | 81 | 122.3 | Bounce is nearly aperiodic (r 0.14–0.20 at every lag). No lag method has evidence. |

The legacy detector got the four flat-autocorrelation or prior-flipped fast songs right (160.6, 160.5, 173.5, 160.3), plus T29 (141.5).

## Anchor constraint

**Fresh held-out truth.** All 54 #0011 songs have been scored, so they can only be used for development. Candidates must be judged on songs no #0011 decision has seen. Alexander does not want manual review work.

## Decisions carried from #0011

- Ground truth is the master tempo in `.als` sets.
- Projects and audio are read-only, never moved, never uploaded.
- Splits are frozen and hashed before measurement.
- At most two prespecified candidates; negative results are reportable.
- Swift/C++ parity is required.
- Nothing is committed, pushed or installed without explicit authorization.
- No Mixed In Key or Tunebat parity claims.

## Open decisions

- **D1 — fresh held-out source (blocks phase b).** Options:
  - (a) Render about 60 s master exports of the unscored sets in Ableton Live into `dist/`, opening each set read-only and closing without saving. There are up to 233 candidate songs in genre.
  - (b) Download the public GiantSteps tempo set: EDM, with fast 170+ material and CC BY-SA annotations. This needs explicit download permission.
  - (c) Wait for new projects Alexander bounces after 2026-11-02.
- **D2 — candidate shape (blocks phase c; decided in the ledger before any fresh score).** Working hypotheses from the diagnosis:
  - The prior chooses only between octaves, never between metres.
  - When the autocorrelation is flat across metric relatives, defer to the legacy peak folded into the comb's octave.

## Phases

- **a — diagnosis.** On the #0011 songs (development): the table above, plus per-song comb contrast. Done while filing.
- **b — fresh truth** (needs D1). Pair, filter and freeze a held-out split with hashes.
- **c — candidates.** Prespecify ≤2 candidates. Measure on development (the #0011 54 plus any development half of b).
- **d — acceptance.** One run on the fresh held-out. Adoption rule fixed in the ledger before that run.
- **e — port and docs.** C++ parity, KeyFinderRegression, `tools/test-*.sh`, plugin regression and tools, ACCURACY.md.

Strict chain: a → b → c → d → e. Phase c may start on development while b is collecting, but no candidate is frozen until b's split is hashed.

## Expected affected files

- `BPMDetector+Comb.swift`
- `KeyFinderVST/Source/BPMDetector.{h,cpp}`
- `tools/tempo-truth/` (possibly a render manifest tool)
- `Fixtures/TempoFixtures.swift`
- `ACCURACY.md`
