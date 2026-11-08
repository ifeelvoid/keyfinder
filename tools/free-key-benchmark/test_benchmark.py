"""Safety and evaluation tests use tiny generated WAVs and controlled references."""

import csv
import json
import math
from pathlib import Path
import struct
import tempfile
import unittest
import wave

import benchmark as b


class BenchmarkTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        # macOS /var and /tmp aliases can themselves be symlinks; use their physical path.
        self.base = Path(self.temporary.name).resolve()
        self.catalog = self.base / "catalog"
        self.catalog.mkdir()
        self.output = self.base / "output"
        self.baseline_dir = self.base / "baseline"
        self.baseline_dir.mkdir()
        self.manifest_path = self.base / "manifest.json"
        self.baseline_path = self.baseline_dir / "results.json"
        self.audio = self.catalog / "triad.wav"
        with wave.open(str(self.audio), "wb") as handle:
            handle.setparams((1, 2, 22050, 0, "NONE", "not compressed"))
            signal = [sum(math.sin(2 * math.pi * frequency * index / 22050)
                          for frequency in [261.6256, 329.6276, 391.9954]) / 4
                      for index in range(2205)]
            handle.writeframes(b"".join(struct.pack("<h", int(value * 32767)) for value in signal))
        self.manifest = {"schemaVersion": 1, "root": str(self.catalog), "candidates": [
            {"id": "one", "relativePath": "triad.wav", "provisionalKey": "C Major"}]}
        self.baseline = [{"id": "one", "relativePath": "triad.wav", "audioSHA256": b.sha256(self.audio),
                          "sourceUnchanged": True, "key": "C Major", "error": None}]
        self.save_inputs()

    def tearDown(self):
        self.temporary.cleanup()

    def save_inputs(self):
        self.manifest_path.write_text(json.dumps(self.manifest), encoding="utf-8")
        self.baseline_path.write_text(json.dumps(self.baseline), encoding="utf-8")
        self.run = {"manifestSHA256": b.sha256(self.manifest_path),
                    "selectedIDs": [row["id"] for row in self.baseline],
                    "engineSHA256": "a" * 64, "executableSHA256": "b" * 64}
        (self.baseline_dir / "run.json").write_text(json.dumps(self.run), encoding="utf-8")

    def mock_run(self, response=("C Major", 0.75), directory="reference"):
        def adapter(path, reference, duration):
            if isinstance(response, Exception):
                raise response
            return response
        return b.analyze(self.manifest_path, self.baseline_path, self.base / directory, "librosa", adapter)

    def labels(self):
        path = self.base / "labels.csv"
        b.labels_template(self.manifest_path, self.baseline_path, path)
        with path.open(newline="", encoding="utf-8") as handle:
            rows = list(csv.DictReader(handle))
        for row in rows:
            row.update(verifiedKey="C Major", evidence="Human-reviewed tonic and chords in project score",
                       familyID=row["id"], split="development")
        self.write_labels(path, rows)
        return path, rows

    def write_labels(self, path, rows):
        with path.open("w", newline="", encoding="utf-8") as handle:
            writer = csv.DictWriter(handle, fieldnames=b.LABEL_FIELDS)
            writer.writeheader()
            writer.writerows(rows)

    def evaluate(self, paths, labels=None):
        if labels is None:
            labels, _ = self.labels()
        return b.evaluate(self.manifest_path, self.baseline_path, labels, paths, self.base / "evaluation.json")

    def add_candidate(self, identifier):
        path = self.catalog / (identifier + ".wav")
        # A trailing marker gives each fixture recording a distinct identity; WAV decoders ignore it.
        path.write_bytes(self.audio.read_bytes() + identifier.encode())
        self.manifest["candidates"].append({"id": identifier, "relativePath": path.name, "provisionalKey": None})
        self.baseline.append({"id": identifier, "relativePath": path.name, "audioSHA256": b.sha256(path),
                              "sourceUnchanged": True, "key": "C Major", "error": None})
        self.save_inputs()

    def test_reference_is_read_only_and_provenance_bound(self):
        before = self.audio.read_bytes()
        result = b.read_json(self.mock_run())
        self.assertEqual(before, self.audio.read_bytes())
        row = result["measurements"][0]
        self.assertEqual(row["audioSHA256"], row["audioSHA256After"])
        self.assertTrue(row["sourceUnchanged"])
        self.assertEqual(row["status"], "ok")
        self.assertEqual(result["run"]["baselineResultsSHA256"], b.sha256(self.baseline_path))
        self.assertEqual(result["run"]["toolSHA256"], b.sha256(Path(b.__file__)))
        self.assertEqual(result["run"]["selectedIDs"], ["one"])

    def test_reference_errors_and_abstentions_are_retained(self):
        error = b.read_json(self.mock_run(ImportError("not installed"), "failure"))["measurements"][0]
        abstention = b.read_json(self.mock_run((None, None), "abstention"))["measurements"][0]
        self.assertEqual(error["status"], "error")
        self.assertIn("not installed", error["error"])
        self.assertIsNone(error["key"])
        self.assertEqual(abstention["status"], "abstained")
        self.assertIsNone(abstention["error"])

    def test_output_inside_catalog_or_existing_is_rejected(self):
        for output in [self.catalog / "output", self.catalog]:
            with self.subTest(output=output), self.assertRaises(b.BenchmarkError):
                b.analyze(self.manifest_path, self.baseline_path, output, "librosa")
        self.mock_run()
        with self.assertRaises(b.BenchmarkError):
            self.mock_run()

    def test_output_symlink_and_dangling_symlink_rejected(self):
        target = self.base / "target"
        target.mkdir()
        link = self.base / "link"
        link.symlink_to(target, target_is_directory=True)
        with self.assertRaises(b.BenchmarkError):
            b.analyze(self.manifest_path, self.baseline_path, link / "reference", "librosa")
        dangling = self.base / "dangling"
        dangling.symlink_to(self.base / "missing")
        with self.assertRaises(b.BenchmarkError):
            b.labels_template(self.manifest_path, self.baseline_path, dangling)

    def test_source_symlink_rejected_even_when_target_inside_catalog(self):
        link = self.catalog / "alias.wav"
        link.symlink_to(self.audio)
        self.manifest["candidates"][0]["relativePath"] = link.name
        self.baseline[0]["relativePath"] = link.name
        self.save_inputs()
        with self.assertRaises(b.BenchmarkError):
            self.mock_run()
        self.assertFalse((self.base / "reference").exists())

    def test_parent_symlink_and_path_traversal_rejected(self):
        folder = self.catalog / "alias"
        folder.symlink_to(self.catalog, target_is_directory=True)
        for relative in ["alias/triad.wav", "../catalog/triad.wav", str(self.audio)]:
            self.manifest["candidates"][0]["relativePath"] = relative
            self.baseline[0]["relativePath"] = relative
            self.save_inputs()
            with self.subTest(relative=relative), self.assertRaises(b.BenchmarkError):
                self.mock_run()

    def test_hash_mismatch_aborts_before_adapter(self):
        self.audio.write_bytes(b"changed")
        called = []
        with self.assertRaises(b.BenchmarkError):
            b.analyze(self.manifest_path, self.baseline_path, self.output, "librosa",
                      lambda *args: called.append(True))
        self.assertEqual(called, [])
        self.assertFalse(self.output.exists())

    def test_source_mutation_is_retained_and_run_aborted(self):
        def malicious_adapter(path, *_):
            path.write_bytes(b"changed by mock")
            return "C Major", 0.9
        with self.assertRaises(b.BenchmarkError):
            b.analyze(self.manifest_path, self.baseline_path, self.output, "librosa", malicious_adapter)
        row = b.read_json(self.output / "reference-results.json")["measurements"][0]
        self.assertFalse(row["sourceUnchanged"])
        self.assertEqual(row["status"], "error")
        self.assertIsNone(row["key"])

    def test_source_mutation_is_checked_after_adapter_failure(self):
        def bad_adapter(path, *_):
            path.write_bytes(b"changed then raised")
            raise RuntimeError("decoder failure")
        with self.assertRaises(b.BenchmarkError):
            b.analyze(self.manifest_path, self.baseline_path, self.output, "librosa", bad_adapter)
        self.assertFalse(b.read_json(self.output / "reference-results.json")["measurements"][0]["sourceUnchanged"])

    def test_baseline_requires_run_fingerprint_and_unique_known_ids(self):
        self.baseline.append(dict(self.baseline[0]))
        self.save_inputs()
        with self.assertRaises(b.BenchmarkError):
            self.mock_run()
        self.baseline.pop()
        self.save_inputs()
        self.run["manifestSHA256"] = "c" * 64
        (self.baseline_dir / "run.json").write_text(json.dumps(self.run))
        with self.assertRaises(b.BenchmarkError):
            self.mock_run()

    def test_template_never_promotes_provisional_labels_or_assigns_splits(self):
        path = self.base / "review.csv"
        b.labels_template(self.manifest_path, self.baseline_path, path)
        with path.open(newline="", encoding="utf-8") as handle:
            row = next(csv.DictReader(handle))
        self.assertEqual(row["provisionalKey"], "C Major")
        for field in ["verifiedKey", "evidence", "familyID", "split"]:
            self.assertEqual(row[field], "")
        with self.assertRaisesRegex(b.BenchmarkError, "No independently reviewed"):
            b.load_labels(path, self.baseline)

    def test_review_requires_evidence_family_split_and_valid_exact_key(self):
        path, rows = self.labels()
        for field, value in [("evidence", ""), ("familyID", ""), ("split", "heldout"),
                             ("verifiedKey", "8B"), ("verifiedKey", "C"), ("verifiedKey", "")]:
            edited = [dict(rows[0], **{field: value})]
            self.write_labels(path, edited)
            with self.subTest(field=field, value=value), self.assertRaises(b.BenchmarkError):
                b.load_labels(path, self.baseline)

    def test_label_duplicates_unknown_ids_and_recording_hash_mismatch_rejected(self):
        path, rows = self.labels()
        invalid = [rows * 2, [dict(rows[0], id="unknown")], [dict(rows[0], audioSHA256="d" * 64)],
                   [dict(rows[0], relativePath="other.wav")]]
        for edited in invalid:
            self.write_labels(path, edited)
            with self.subTest(rows=edited), self.assertRaises(b.BenchmarkError):
                b.load_labels(path, self.baseline)

    def test_song_family_leakage_checked_before_split_filter(self):
        self.add_candidate("two")
        path, rows = self.labels()
        rows[0].update(familyID="same song", split="train")
        rows[1].update(familyID="same song", split="test")
        self.write_labels(path, rows)
        with self.assertRaisesRegex(b.BenchmarkError, "leaks"):
            b.evaluate(self.manifest_path, self.baseline_path, path, [self.baseline_path], self.output, split="test")

    def test_identical_recordings_cannot_hide_leakage_under_different_family_ids(self):
        self.add_candidate("two")
        (self.catalog / "two.wav").write_bytes(self.audio.read_bytes())
        self.baseline[1]["audioSHA256"] = b.sha256(self.audio)
        self.save_inputs()
        path, rows = self.labels()
        rows[0]["split"] = "train"
        rows[1]["split"] = "test"
        self.write_labels(path, rows)
        with self.assertRaisesRegex(b.BenchmarkError, "Identical recording"):
            b.load_labels(path, self.baseline)

    def test_identical_recordings_cannot_have_conflicting_verified_keys(self):
        self.add_candidate("two")
        (self.catalog / "two.wav").write_bytes(self.audio.read_bytes())
        self.baseline[1]["audioSHA256"] = b.sha256(self.audio)
        self.save_inputs()
        path, rows = self.labels()
        for row in rows:
            row["familyID"] = "same recording"
        rows[1]["verifiedKey"] = "F# Minor"
        self.write_labels(path, rows)
        with self.assertRaisesRegex(b.BenchmarkError, "contradictory verified keys"):
            b.load_labels(path, self.baseline)
        rows[0]["verifiedKey"] = "Db Major"
        rows[1]["verifiedKey"] = "C# Major"
        self.write_labels(path, rows)
        self.assertEqual(len(b.load_labels(path, self.baseline)), 2)

    def test_failures_abstentions_and_missing_count_in_accuracy_denominator(self):
        for identifier in ["two", "three", "four"]:
            self.add_candidate(identifier)
        labels, _ = self.labels()
        result = b.read_json(self.mock_run())
        result["measurements"][1].update(key=None, status="error", error="decoder failure")
        result["measurements"][2].update(key=None, status="abstained")
        result["measurements"].pop()
        path = self.base / "reference" / "reference-results.json"
        path.write_text(json.dumps(result))
        engine = self.evaluate([path], labels)["engines"][0]
        self.assertEqual(engine["labeledAttempts"], 4)
        self.assertEqual(engine["exactAccuracyAllLabeledAttempts"], 0.25)
        self.assertEqual(engine["coverage"], 0.25)
        self.assertEqual([engine["counts"][name] for name in ["exact", "errors", "abstentions", "missing"]], [1] * 4)

    def test_confusions_do_not_inflate_exact_accuracy(self):
        for identifier in ["two", "three", "four"]:
            self.add_candidate(identifier)
        labels, _ = self.labels()
        result = b.read_json(self.mock_run())
        for row, key in zip(result["measurements"], ["C Major", "A Minor", "G Major", "C Minor"]):
            row["key"] = key
        path = self.base / "reference" / "reference-results.json"
        path.write_text(json.dumps(result))
        engine = self.evaluate([path], labels)["engines"][0]
        self.assertEqual(engine["exactAccuracyAllLabeledAttempts"], 0.25)
        for category in ["exact", "relativeMajorMinor", "fifth", "parallelMajorMinor"]:
            self.assertEqual(engine["counts"][category], 1)
        self.assertEqual(b.confusion("A Minor", "C Major"), "relativeMajorMinor")
        self.assertEqual(b.confusion("C Major", "F Major"), "fifth")

    def test_enharmonic_labels_and_predictions_compare_exactly(self):
        labels, rows = self.labels()
        rows[0]["verifiedKey"] = "Db Major"
        self.write_labels(labels, rows)
        path = self.mock_run(("C# Major", 0.8))
        self.assertEqual(self.evaluate([path], labels)["engines"][0]["counts"]["exact"], 1)

    def test_result_duplicate_unknown_ids_hashes_and_provenance_rejected(self):
        path = self.mock_run()
        pristine = b.read_json(path)
        variants = []
        for change in ["duplicate", "unknown", "hash", "source", "selected", "manifest", "baseline", "status"]:
            data = json.loads(json.dumps(pristine))
            if change == "duplicate":
                data["measurements"].append(dict(data["measurements"][0]))
            elif change == "unknown":
                data["measurements"][0]["id"] = "unknown"
            elif change == "hash":
                data["measurements"][0]["audioSHA256"] = "d" * 64
            elif change == "source":
                data["measurements"][0]["sourceUnchanged"] = False
            elif change == "selected":
                data["run"]["selectedIDs"] = []
            elif change == "manifest":
                data["run"]["manifestSHA256"] = "d" * 64
            elif change == "baseline":
                data["run"]["baselineResultsSHA256"] = "d" * 64
            else:
                data["measurements"][0]["status"] = "abstained"
            variants.append((change, data))
        for change, data in variants:
            path.write_text(json.dumps(data))
            with self.subTest(change=change), self.assertRaises(b.BenchmarkError):
                self.evaluate([path])
        self.assertFalse((self.base / "evaluation.json").exists())

    def test_swift_results_are_supported_with_run_provenance(self):
        engine = self.evaluate([self.baseline_path])["engines"][0]
        self.assertEqual(engine["counts"]["exact"], 1)
        self.assertIn("a" * 12, engine["name"])

    def test_nonfinite_reference_score_becomes_error(self):
        row = b.read_json(self.mock_run(("C Major", float("nan"))))["measurements"][0]
        self.assertEqual(row["status"], "error")

    def test_excerpt_parameters_passed_and_preserved(self):
        observed = []
        path = b.analyze(self.manifest_path, self.baseline_path, self.output, "librosa",
                         lambda path, reference, duration: (observed.append(duration) or "C Major", 0.7), duration=12)
        self.assertEqual(observed, [12])
        self.assertEqual(b.read_json(path)["run"]["reference"]["parameters"]["selection"]["maximumDurationSeconds"], 12)
        for duration in [0, -1, float("nan"), float("inf")]:
            with self.subTest(duration=duration), self.assertRaises(b.BenchmarkError):
                b.analyze(self.manifest_path, self.baseline_path, self.base / "other", "librosa", duration=duration)


if __name__ == "__main__":
    unittest.main()
