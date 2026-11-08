# Public key challenge execution
blc/2 #0004 done a:done b:done c:done branch:codex/mik-key-analysis

Brief: brief.md. Branch codex/mik-key-analysis; existing isolated checkout reused.

- a — corpus and frozen policy: done locally. Corpus worker owns tools/key-challenge/.
- b — measurements and development diagnosis: done locally. Native key-only baseline, references, tonal exports and both controlled experiments are measured; collector parity is independently verified.
- c — candidate and acceptance: done locally on codex/mik-key-analysis. Exact learned50 profiles adopted after native parity, synthetic regressions, independent review and reserved-test gain; verified preview built.

a and runner preparation are parallel; measurements depend on frozen corpus; candidate and reserved-test inspection follow development/validation measurements.

Existing tools/orient.sh and repository instruction files are absent, as verified in #0003. No new commit/push/native-memory save. User has authorized continued implementation and parallel agents.

## Decisions

The larger public corpus is a biased EDM challenge, not private-song or whole-market accuracy. Raw annotations and all exclusions must be retained. Candidate adoption needs actual independent results; no forced success.

## Preparation evidence

- Official GiantSteps+ v2 audio archive downloaded from Zenodo locally: 855761126 bytes, published MD5 verified; 273.4 seconds. No private audio uploaded.
- Swift key-only runner release build and self-test pass. Independent reviewer found no actionable new issues. Optional analysisMode preserves legacy run decoding; parent-only path canonicalization fixes /var versus /private/var inventory alias behavior without dereferencing final symlink entries.
- Public sample 3271514 smoke succeeded: A Minor, same source hash/key/confidence as full analysis, elapsed 0.452 seconds versus prior full-run 5.34 seconds. This sample and its artist group are forced to development; it is not independent test evidence.

- Initial preparation retained 600 recordings, 378 eligible single-key labels and 222 visible exclusions (modal/other/ambiguous labels, changing tonics, invalid intervals). This output is historical and NOT accepted for measurements. Independent review found known primary artists split between solo and collaboration credits. Before any new corpus predictions, worker will normalize first comma-delimited primary artist, retain ampersand artist names, test grouping and emit fresh prepared-v2 policy. Initial policy hash ae21aacf68450a482465bc36c06612e8ac6f4c6d7c4042b965661ae97d0650d1 is explicitly rejected.

- Fresh prepared-v2 corrected primary-artist grouping, preserving ampersand names. 18 importer tests pass. 482 normalized primary-artist groups have zero cross-split memberships. All 600 records remain visible; 378 eligible: development 230/354 recordings, validation 85/138, reserved test 63/108. Policy SHA256 2a9a5b60bea279f75891d09a0d27ff500eeb66a7ffd69046065f1f3a433283af; partitions and labels frozen before corpus prediction. Baseline binary and exact eight engine source files preserved under dist/giantsteps-plus-v2/.

## Candidate protocol (before candidate predictions)

Validation baseline completed 138/138 source-intact attempts, 85 eligible; 29 exact, 14 parallel major/minor, 6 relative, 15 fifth, 21 other, zero decode errors/abstentions. Development baseline continues. No test prediction artifacts exist.

Two controlled candidates are prespecified: (1) KS profiles with fixed chroma compression exponent 0.7; (2) independently derived development-only mode profiles, rotation-normalized per labeled tonic, per-record segment average then per-mode median, normalized and shrunk 50% toward normalized existing KS profiles, with unchanged adaptive compression. No grid search. Need development results and validation support before selecting either; synthetic regressions and a reserved test comparison remain acceptance gates.

Worker will extract same tonal segment collector (chroma12, rms, timestamp) into a public evidence API and add optional analyze-features CLI output. This refactor must preserve exact sample baseline key/confidence and all regressions. Profile tool must replay baseline keys exactly before fitting, prove only frozen eligible development IDs contribute, record coefficients/counts/hashes, and prevent test fitting. Primary runtime remains independent Swift, with no Essentia/libkeyfinder code or trained weights copied.

## Baseline measurements

Preserved Swift key-only baseline completed all 492 development/validation attempts with sourceUnchanged true and no decoding failures. Development: 104/230 exact (45.22%), 48 parallel major/minor, 11 relative, 32 fifth, 35 other. Validation: 29/85 exact (34.12%), 14 parallel, 6 relative, 15 fifth, 21 other. Both 100% prediction coverage. Librosa validation completed 138/138 attempts and 52/85 exact (61.18%) at 100% coverage. Optional Essentia validation and both development references continue; adapter/runtime parameters and native decode warnings preserved. No test artifacts exist.

Collector refactor static review approved: extraction/order/scoring preserved; feature mode intentionally computes chroma twice, so its elapsedSeconds measures export overhead rather than detector speed. Awaiting synthetic regression and exact sample parity evidence.

## Candidate selected before reserved test

All492 feature runs matched frozen baseline exactly; independent Python current replay matches492/492; all34 corpus/profile tests pass and independent review approved. Full refs finished with100%coverage: development lib130/230,Ess182/230; validation lib52/85,Ess64/85. Prespecified fixed0.7 candidate dev105/230,val29/85; learned50 candidate dev125/230,val38/85 versus baseline104/230,val29/85. Selected learned50, with parameters frozen before any reserved-test prediction. Fitting uses230eligible development recordings (24major,206minor). Metadata/coefficients/hashes in dist/giantsteps-plus-v2/candidate-selection.json and profiles-development/parameters.json. No hidden search or test-driven tuning. Swift exact replay parity, synthetic regressions, review and reserved test still required.

Phase re-plan: a and b are verified local artifacts; no PR merge exists or is required within the explicitly local-only scope. Reused isolated branch; no commit/push/memory write under user boundaries. c is now concrete learned50 static coefficients plus recorded public-data provenance. Candidate adoption still depends on native parity/regressions and reserved-test result. Public references outperform our development/validation detector; future spectral extraction work remains separate rather than a claim of overall best accuracy.

## Acceptance and completion

Candidate native parity: 354/354 development and138/138 validation, zero mismatches versus frozen replay. All17 regression groups and CLIself-test pass. Independent review verified all24coefficients,230development contributors, frozen parameter choice before test, matching source/binary and unchanged108test audio hashes.

Reserved native exact score26/63→32/63 (41.27%→50.79%), six gains and zero losses,100%coverage. Paired discordance binomial p=0.03125 is descriptive small-cohort evidence, with artist/family uncertainties retained. All600attempts for both native versions and both refs completed without prediction failures or source changes; test refs lib35/63 and Ess50/63. Essentia is still the stronger measured free reference; no overall-best or MIK-parity claim.

Local Apple Silicon preview built and deep/strict ad-hoc signature verified; arm64 and minimum macOS12.0 confirmed. Preview binary SHA2562c0e11d14d49ab8b602e7e5e05851cefeb0e5711ea032f0034d5defcef28c250. Candidate engine53fd195708fb64e86b083156db7eff87bc6753b7025568f4cf8cb6a07f0c6ed9. Prior app preserved by build script; no installed app replacement or GUI test. Tracked handoff/profile provenance and ACCURACY.md updated. Summary.json binds complete matrix and preview; no remote publication, purchases, private audio uploads or memory writes.

All phases are done as local artifacts; PR/merge/release work remains outside this brief's authorized scope. Next independent accuracy experiment should target spectral representation and obtain new reviewed data; it must not retune against the now-examined test subset.
