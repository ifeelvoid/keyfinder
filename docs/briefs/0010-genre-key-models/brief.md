# Genre-aware key models trained on open data
**Serial:** #0010 · **Created:** 2026-10-28 · **Author:** ifeelvoid@proton.me · **Depends on:** #0004, #0005

## Outcome

Alexander's direction, relayed by the KeyFinder 2.0 status session: "keep the EDM dataset for EDM stuff, but if it's trap or hip hop, just train it on my catalog"; "just train the data set. We need stronger data sets. It has to be as good as Mixed In Key or better, and free and open source."

The aim is a measurably stronger key detector for trap/hip-hop and EDM, with three parts:

- Two template sets, chosen by a user style setting ("Trap / Hip-Hop" by default, or "EDM").
- Our own small key classifier, trained only on data we may legally use.
- The same results in the app (Swift/CoreML) and the plugin (C++).

Templates stay as the fallback and the baseline.

## Evidence and anchor constraint

- #0005 rejected whitening and harmonic weighting. Both raised fifth errors on GiantSteps+ and on the catalog.
- The shipped learned50 detector scores 125/230 on GiantSteps+ development and 38/85 on validation. Essentia scores 182/230 and 64/85.
- Catalog split frozen 2026-10-29: 420 tracks in 340 families, split development 204 / held-out 216.

The anchor constraint is **trusted label volume**. There are only about 121 explicit-mode filename labels, and many are wav/mp3 duplicates of the same beat. Trust comes from agreement with Essentia, which leaves an estimated few dozen families per half. That supports fitting templates with shrinkage. It does not support training a CNN on the catalog alone. Public human-labelled data must carry the model.

## Approved decisions (Alexander, relayed 2026-10-29)

1. CC BY-SA 4.0 training annotations (GiantSteps-MTG, GiantSteps+) accepted. Attribution (dataset names, authors, licence, links) ships in ACCURACY.md and an app/plugin credits note; provenance JSON states the weights derive from CC BY-SA annotations. GTZAN audio excluded. No Essentia (AGPL) or madmom (CC BY-NC-SA) code/models embedded.
2. GiantSteps-MTG eligible set split train/test by artist family, frozen and hashed before any training prediction; the test half is the fresh public acceptance set.
3. #0009 UI restriction lifted for the style toggle only: `Views/Redesign/TopBar.swift` (⋯ menu or settings sheet, @AppStorage) and `KeyFinderVST/Source/PluginEditor.cpp` + `PluginProcessor` get/setStateInformation. Existing plugin regression/snapshot tools keep passing; toggle gets tests.
4. Catalog auto-trust only; held-out catalog half untouched until the final run; no Mixed In Key parity claim (no head-to-head possible here); nothing committed/pushed; nothing installed into /Applications or ~/Library/Audio/Plug-Ins. Negative results are reportable.

## Phases

- a: data. Catalog trust labels (done in #0005 deviation), with augmentation of trusted development tracks by 12 pitch shifts through rubberband or librosa, applied after the split. Acquire public data and run licence and overlap audits. Freeze held-out sets.
- b: templates. Fit a trap/hip-hop set on trusted catalog development tracks with the learned50 method and fixed 50% KS shrinkage. Add the style setting to the app and plugin. Confirm C++ parity for both sets.
- c: model. Train a small chroma/CQT CNN in PyTorch on CPU/MPS. Export to CoreML and to C++/ONNX. Prespecify the architecture and selection rule.
- d: acceptance. Evaluate once on the frozen catalog held-out half, GiantSteps+ validation and fresh public data. Report cross-genre costs and compare with Essentia on identical audio, with the circularity caveat stated.

## Expected affected files

`KeyDetector.swift` (profile set selection, model hook), `KeyFinderVST/Source/KeyDetector.cpp`, `PluginEditor.cpp`/`PluginProcessor.cpp` (state), app Settings or TopBar, new `tools/key-model/`, provenance JSONs and `ACCURACY.md`.
