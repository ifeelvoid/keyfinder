# Fresh key corpus audit

Research date: 2026-10-12. Owned scope: read-only public corpus research and this document. Detector predictions, audio acquisition and implementation remain with the coordinating chat. All recommendations below are additions by Codex.

## Outcome

Use the official **Beatport EDM Key / GiantSteps-MTG release** for the next independent Swift experiment. Its spreadsheet provides human labels and substantially more major-mode examples. Freeze partitions only after comparing every candidate with all 600 previously used GiantSteps+ recordings, including excluded recordings. A metadata-only audit finds **1,061 provisional high-confidence singleton candidates** after conservative credited-artist and explicit annotation-caveat filters. Audio identity and related-version checks remain required; this is not a final corpus count or an independent score.

For genre diversity, the smallest official FMAK audio shard is **1.734 GB**, with **223 annotated IDs** in its numeric range. It is a practical later alternative to downloading all 39 GB. Rights, artists, duration/scope and actual archive-member correspondence need further inspection first.

## Verified acquisition and annotation provenance

The [official MTG release](https://zenodo.org/records/1101082) identifies Eduard Mas Marín and Ángel Faraldo as annotator/reviser. Direct official API metadata declares CC BY-SA 4.0. A HEAD request to the official audio URL returned HTTP 200 and the expected content length; no audio archive or recording was downloaded in this audit.

| Official file | Bytes | Published MD5 | Checked here |
| --- | ---: | --- | --- |
| audio.zip | 2,127,891,180 | f490ee6c23578482d6fcfa11b82636a1 | Metadata and HTTP HEAD only |
| keys.zip | 380,107 | 939abc05f36121badfac4087241ac172 | Full small archive, matching checksum |
| Beatport-EDM-Key-Dataset.xlsx | 148,165 | fbd16ee3ff89b07db48267b8fe61554c | Full spreadsheet, matching checksum |
| original_metadata.zip | 921,083 | bb3e3ac1fe5dee7600ef2814accdf8f8 | Full small archive, matching checksum |

Audio URL: [official audio.zip](https://zenodo.org/records/1101082/files/audio.zip?download=1). The verified record API is [1101082 metadata](https://zenodo.org/api/records/1101082). A reachable URL is not an audio checksum or decode verification.

The [author's thesis](https://zenodo.org/records/1154586), section 5.2.1, printed page 119, documents replacing store key estimates with manual annotations. Its confidence rubric is: **2** expects agreement from other experts; **1** permits subjective alternative interpretations; **0** records difficulty deciding. This now supports a confidence-2 primary subset without inventing a threshold. Preserve lower-confidence items for a separate challenge. The PDF was retrieved and matched its published MD5, `0357a3151d98be37db1f1051fdc45d51`.

The release license is a declared reuse grant, not an independent audit of rights to every Beatport recording. Keep audio out of Git and app bundles. Training-output and distribution obligations require a separate release decision. Existing reference models may have been trained on MTG; their scores must retain that exposure caveat.

## Counts confirmed by local metadata inspection

Source for prior identities: current `dist/giantsteps-plus-v2/prepared-v2/policy.json`, whose 600 records include source IDs, hashes, full filename artist credits and eligibility. None of the new MTG audio bytes were inspected.

| Gate | Remaining rows |
| --- | ---: |
| MTG spreadsheet, unique numeric source IDs | 1,486 |
| ID disjoint from all 600 previous GS+ IDs | 1,486 |
| Singleton canonical major/minor; all time/change fields blank | 1,245 |
| Above, removing shared GS+ primary artists | 1,222 |
| Above, removing any shared comma-delimited artist credit | 1,212 |
| Above, published confidence exactly 2 | 1,069 |
| Above, holding out eight explicit modal/modulation caveats | 1,061 |

The 1,212 rows before the confidence/caveat gates contain 367 major and 845 minor labels; confidence counts are 1,069 at 2, 128 at 1, and 15 at 0. Overall raw confidence counts are 1,182/208/96. These counts are deterministic metadata observations, not final eligibility or tested predictions.

Artist normalization uses Unicode NFKC, case folding and collapsed whitespace. This extends the prior primary-artist heuristic to every comma-delimited credit. It still misses aliases, credits separated by ampersands, featured artists inside titles and remixers. Conservative removal of these additional resolved links can only reduce the final count.

All 1,486 `.txt` labels correspond to spreadsheet IDs and match its `main_key` after trimming whitespace. Spreadsheet columns are `id, artists, title, mix, label, genres, main_key, confidence, time1, change1, time2, change2, comments`. Preserve both raw forms rather than silently repairing an annotation.

There are 33 rows with time/change fields. Time cells carry Excel `h:mm:ss` formats and day-fraction numeric values; treating them directly as seconds would be wrong. Some apparent values are implausible for a two-minute excerpt, so this audit excludes all such rows from the primary singleton subset. It does not reconstruct regional labels.

Blank time/change fields do not establish constant key. Eight otherwise eligible, confidence-2, artist-disjoint rows explicitly mention modality or internal modulation in comments:

| ID | Caveat |
| --- | --- |
| 297521 | Mixolydian/blues-scale interpretation |
| 2028917 | Many internal modulations |
| 3027735 | Modulation to C minor |
| 3074103 | Modulations to E minor |
| 3526880 | Modulations to F-sharp minor |
| 3537560 | Modulation to E minor and ending in A major |
| 3831852 | Modulations to C-sharp major and F minor |
| 4809086 | Internal modulations despite a stated dominant key |

These eight are a conservative explicit-caveat holdout, not proof that all remaining comments are unambiguous. Review the remaining primary-subset comments before freezing policy. Never overwrite their published labels based on detector output.

`original_metadata.zip` contains only 792 relevant JSON members, of which 780 parse and 12 fail strict JSON decoding. It cannot supply complete artist metadata for the corpus. Keep these failures visible; use the human spreadsheet for annotation provenance and its artist/title/mix fields for initial grouping. Machine key fields in original store metadata are not replacement ground truth.

Stripping parenthetical mix text and featured-credit suffixes identifies 23 title coincidences across the two corpora, many generic. This is a review queue, not proof of shared audio. Different source IDs do not establish different song families. Before final split, resolve artist/title/remixer/version links and compute SHA-256 against all previous audio hashes. Hash inequality does not exclude transcoded/cropped versions; report unresolved acoustic-identity limitations.

## Frozen policy recommendation

1. Verify the complete audio archive's byte count and published MD5. Safely inventory/extract bounded regular MP3 members, preserving original filename, source ID, CRC, SHA-256 and acquisition evidence. Join exactly one recording, key file and spreadsheet row per ID; retain failures.
2. Build an exclusion audit against **all 600** prior GS+ identities, hashes and resolved artist/song-family links. Exclude shared artists/families from the new experiment even if their prior annotation was unscorable. Preserve match reasons. Do not call source-ID disjointness full recording independence.
3. Primary labels: confidence 2, one canonical major/minor key, no time/change fields, no explicit contradictory/modal/change caveats. Preserve unknown/non-tonal/modal/ambiguous and confidence-0/1 rows separately with reasons. Enharmonic normalization is permitted and must be logged. Preserve raw comments and annotation hashes.
4. Group duplicate encodings, related versions and collaborations before deterministic development/validation/test assignment. Resolve artist connected components conservatively. Freeze policy and hashes before any predictions; new test predictions remain hidden until candidate selection is frozen. Augment only after grouping.
5. Keep the prior GS+ result historical. This new MTG collection is independent only relative to the locally fitted Swift detector after the gates above; pretrained MTG-trained references are exposed comparators. Report eligible denominators, coverage, decode failures and stratified major/minor/subgenre results. Retain low-confidence/modal challenge tables without forcing keys.

## Smaller diverse alternatives

**FMAK shard:** The [official FMAK API](https://zenodo.org/api/records/10719860) describes expert song-level labels across 17 genres. `110-124.zip` is **1,734,477,426 bytes**, MD5 `88d7dbcca82189ed75b7baa5aa132fc1`. The checksum-verified label CSV contains **223 IDs from 110000 through 124999**, with all 24 major/minor classes represented. This is a numeric-range intersection, not yet an archive inventory. These are song-level labels and full recordings; do not assume an arbitrary 30-second crop carries the same key. The annotations are CC BY 4.0; audio retains per-artist licenses. Obtain actual recording rights/artist metadata and member correspondence before using the shard as a distributable training source. No audio fetched here.

**Freesound Loop Dataset:** The [official release](https://zenodo.org/records/3967852) separates expert annotations from automatic AudioCommons/Essentia estimates. Its audio archive is **8,841,802,341 bytes**, MD5 `c260a1203a82c1dda80ec1de75e5e23f`; verified annotations archive is **1,564,890 bytes**, MD5 `3920ee437802cf047a990b2968fa066c`. Local inspection finds 4,420 human judgments for 2,936 unique sound IDs. A conservative metadata gate leaves **805** loops with defined, identical tonic/mode across all available judgments and no discard/save-for-later flags: 538 have one judgment, 267 multiple. Raw mode tags are `maj`/`min`, not `major`/`minor`. The sounds use individual Creative Commons licenses stored in the audio archive's metadata. This is a useful future sparse-loop challenge, not equivalent to full-song accuracy or an all-human 9,455-loop benchmark. No audio fetched here.

Isophonics and Billboard remain unsuitable as immediately free matching audio routes; the earlier project data report already identifies their missing redistributable audio. Classical title keys or automatically inferred MIDI/chord keys would change label provenance rather than satisfy this human-annotated recording requirement.

## Audit artifacts and remaining gaps

Temporary read-only acquisition/audit files are under `/private/tmp/keyfinder-fresh-corpus-audit/`: official API JSON, checksum-verified small archives/spreadsheet/PDF, parsed `mtg-audit-rows.json`, `mtg-strict-artist-disjoint.json` (1,212 rows, before confidence/caveat gates), and metadata parse failures. They contain no predictions. Coordinating work should copy selected provenance into a dedicated ignored result directory before relying on temporary paths.

Verified SHA-256 receipts:

| File | SHA-256 |
| --- | --- |
| keys.zip | 8163204c685eb63b877e07375aae4a6798dd3a14fa6cb8dcfece9f3f1e8f43a4 |
| Beatport-EDM-Key-Dataset.xlsx | 756ec8c9709a50c03c1c741cf051e2b0bb984df3dc914ec733933cd92cd584dc |
| original_metadata.zip | cd3d7c144dec0031581531315ebc7e340e8ac89161254f37a4167bea77ad13c3 |
| mtg-audit-rows.json | e80ff44b3f022363441921750a9473443ad208d20e64e1c14b039858db8dc3f4 |
| fma_keys_metadata.csv | 7ec4bd22eb5ff7958fbf9d8c44869f955fc6b50b67896b229665b3b92e80190d |
| fsld-annotations.zip | e062f1f8e298730df92a879c302ce2c4f718039a3979442abc8aaca1258ac38e |

Still missing: full audio archive checksum/contents, decoding, duration/scope verification, cross-corpus audio hashes, aliases/remixer links, independent human re-annotation, and all algorithm scores. No audio download, dependency installation, detector edit, prediction, paid service, public post or durable memory save occurred in this research task.
