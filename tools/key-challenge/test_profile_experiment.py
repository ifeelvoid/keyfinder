import copy
import json
import math
from pathlib import Path
import tempfile
import unittest

import challenge as c
import profile_experiment as p


class ProfileExperimentTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name).resolve()
        self.prepared = self.root / "prepared"
        self.prepared.mkdir()
        self.audio = self.prepared / "audio"
        self.audio.mkdir()
        self.policy_path = self.prepared / "policy.json"
        self.records = []
        descriptions = [("major", "development", "C Major", p.MAJOR),
                        ("minor", "development", "C Minor", p.MINOR),
                        ("validation", "validation", "G Major", p.rotate_left(p.MAJOR, -7)),
                        ("reserved", "test", "D Minor", p.rotate_left(p.MINOR, -2))]
        self.rows = {}
        for index, (identifier, split, key, chroma) in enumerate(descriptions):
            recording_hash = str(index + 1) * 64
            record = {"id": identifier, "sourceID": identifier, "relativePath": identifier + ".mp3",
                      "audioSHA256": recording_hash, "artistGroup": identifier, "partitionGroupID": "group-" + identifier,
                      "familyID": "source-" + identifier, "split": split, "eligibleKey": key,
                      "annotationMember": "annotations/" + identifier + ".json", "rawAnnotationSHA256": "a" * 64}
            self.records.append(record)
            segments = [{"chroma": p.unit_sum(chroma), "rms": 0.5, "timestamp": 0.0},
                        {"chroma": p.unit_sum(chroma), "rms": 0.25, "timestamp": 30.0}]
            self.rows[identifier] = {"id": identifier, "relativePath": record["relativePath"],
                                    "audioSHA256": recording_hash, "sourceUnchanged": True,
                                    "key": p.classify(segments), "error": None, "duration": 120,
                                    "tonalEvidence": segments}
        self.manifests, self.baselines = {}, {}
        self.save_inputs()

    def tearDown(self):
        self.temporary.cleanup()

    def save_inputs(self):
        manifest_records = {}
        for split in ["development", "validation", "test"]:
            path = self.prepared / (split + ".json")
            selected = [record for record in self.records if record["split"] == split]
            path.write_text(json.dumps({"schemaVersion": 1, "root": str(self.audio), "candidates": [
                {"id": record["id"], "relativePath": record["relativePath"]} for record in selected]}))
            self.manifests[split] = path
            manifest_records[split] = {"sha256": c.digest(path)}
            baseline_root = self.root / ("baseline-" + split)
            baseline_root.mkdir(exist_ok=True)
            baseline_path = baseline_root / "results.json"
            baseline_path.write_text(json.dumps([self.rows[record["id"]] for record in selected]))
            (baseline_root / "run.json").write_text(json.dumps({"manifestSHA256": c.digest(path),
                "selectedIDs": [record["id"] for record in selected], "engineSHA256": "b" * 64,
                "executableSHA256": "c" * 64, "analysisMode": "tonal-features"}))
            self.baselines[split] = baseline_path
        self.policy = {"schema": "giantsteps-plus-v2-frozen-policy-v1", "audioRoot": str(self.audio),
                       "manifests": manifest_records, "records": self.records}
        self.policy_path.write_text(json.dumps(self.policy))
        (self.prepared / "freeze.json").write_text(json.dumps({"policySHA256": c.digest(self.policy_path)}))

    def fit(self):
        return p.fit(self.manifests["development"], self.baselines["development"], self.policy_path, self.root / "fit")

    def predict(self, parameters, split="validation", output=None):
        return p.predict(self.manifests[split], self.baselines[split], self.policy_path, parameters,
                         output or self.root / "predictions")

    def test_baseline_profiles_recognize_tonic_rotation_and_mode(self):
        for mode, profile in [("Major", p.MAJOR), ("Minor", p.MINOR)]:
            for tonic in range(12):
                chroma = p.rotate_left(profile, -tonic)
                self.assertEqual(p.classify([{"chroma": chroma, "rms": 1, "timestamp": 0}]), f"{c.NOTES[tonic]} {mode}")

    def test_adaptive_compression_exact_sparsity_rule(self):
        sparse = [1, 0.5, 0.3, 0.2] + [0] * 8
        dense = sparse[:4] + [0.2] + [0] * 7
        for vector, exponent in [(sparse, 0.7), (dense, 0.5)]:
            original = p.unit_sum(vector)
            expected = p.unit_sum([math.pow(value, exponent) for value in original])
            self.assertEqual(p.normalize(vector), expected)
        self.assertEqual(p.normalize(dense, "fixed-0.7"), p.unit_sum([math.pow(value, 0.7) for value in p.unit_sum(dense)]))

    def test_pearson_zero_variance_and_signed_correlation(self):
        values = list(range(1, 13))
        self.assertEqual(p.pearson(values, values), 1)
        self.assertEqual(p.pearson(values, list(reversed(values))), -1)
        self.assertEqual(p.pearson([1] * 12, values), 0)

    def test_scores_and_aggregate_use_lexicographic_tie_order(self):
        scores = p.key_scores(p.MAJOR, major=p.MAJOR, minor=p.MAJOR)
        self.assertEqual([key for key, _ in scores[:2]], ["C Major", "C Minor"])
        self.assertEqual(p.classify([{"chroma": p.MAJOR, "rms": 1, "timestamp": 0}], major=p.MAJOR, minor=p.MAJOR), "C Major")

    def test_silence_and_zero_rms_abstain(self):
        self.assertIsNone(p.classify([]))
        self.assertIsNone(p.classify([{"chroma": [0] * 12, "rms": 1, "timestamp": 0}]))
        self.assertIsNone(p.classify([{"chroma": p.MAJOR, "rms": 1e-8, "timestamp": 0}]))
        self.assertIsNone(p.classify([{"chroma": [1] * 12, "rms": 1, "timestamp": 0}]))

    def test_louder_rms_segment_increases_its_weight(self):
        c_major = {"chroma": p.MAJOR, "rms": 0.0001, "timestamp": 0}
        g_major = {"chroma": p.rotate_left(p.MAJOR, -7), "rms": 1, "timestamp": 30}
        self.assertEqual(p.classify([c_major, g_major]), "G Major")

    def test_evidence_shape_finiteness_timestamp_and_vector_names_validated(self):
        good = {"chroma": p.MAJOR, "rms": 0.5, "timestamp": 0}
        invalid = [dict(good, chroma=[0] * 11), dict(good, chroma=[float("nan")] + [0] * 11),
                   dict(good, rms=-1), dict(good, timestamp=float("inf")), dict(good, chroma12=p.MAJOR)]
        for segment in invalid:
            with self.subTest(segment=segment), self.assertRaises(c.ChallengeError):
                p.validate_evidence([segment])
        with self.assertRaises(c.ChallengeError):
            p.validate_evidence([dict(good, timestamp=20), good])
        legacy = dict(good)
        legacy["chroma12"] = legacy.pop("chroma")
        self.assertEqual(p.validate_evidence([legacy])[0]["chroma"], p.MAJOR)

    def test_fit_requires_baseline_replay_equality_before_fitting(self):
        self.rows["major"]["key"] = "F# Minor"
        self.save_inputs()
        with self.assertRaisesRegex(c.ChallengeError, "replay does not reproduce"):
            self.fit()
        self.assertFalse((self.root / "fit").exists())

    def test_fit_rejects_validation_test_and_partial_partition(self):
        for split in ["validation", "test"]:
            with self.subTest(split=split), self.assertRaises(c.ChallengeError):
                p.fit(self.manifests[split], self.baselines[split], self.policy_path, self.root / "fit")
        self.baselines["development"].write_text(json.dumps([self.rows["major"]]))
        with self.assertRaisesRegex(c.ChallengeError, "Missing"):
            self.fit()

    def test_feature_hash_integrity_policy_and_ids_must_match(self):
        pristine = copy.deepcopy(self.rows["major"])
        for field, value in [("audioSHA256", "e" * 64), ("sourceUnchanged", False), ("id", "unknown"),
                             ("relativePath", "other.mp3")]:
            self.rows["major"] = dict(pristine, **{field: value})
            self.save_inputs()
            with self.subTest(field=field), self.assertRaises(c.ChallengeError):
                self.fit()
        self.rows["major"] = pristine
        self.save_inputs()
        self.policy_path.write_text(self.policy_path.read_text() + " ")
        with self.assertRaisesRegex(c.ChallengeError, "policy hash"):
            self.fit()

    def test_fitting_tonic_alignment_record_average_median_and_half_prior(self):
        self.rows["major"]["tonalEvidence"] = [{"chroma": p.rotate_left(p.MAJOR, -7), "rms": 0.5, "timestamp": 0}]
        self.rows["major"]["key"] = "G Major"
        self.records[0]["eligibleKey"] = "G Major"
        self.save_inputs()
        parameters = c.load_json(self.fit())
        major_profile = parameters["profiles"]["Major"]
        expected = p.normalize(p.MAJOR)
        for observed, reference in zip(major_profile["medianProfile"], expected):
            self.assertAlmostEqual(observed, reference, places=14)
        prior = p.unit_sum(p.MAJOR)
        for observed, sample, baseline in zip(major_profile["learned50Profile"], expected, prior):
            self.assertAlmostEqual(observed, 0.5 * sample + 0.5 * baseline, places=14)
        self.assertEqual(parameters["profiles"]["Minor"]["recordCount"], 1)
        self.assertTrue(all(record["split"] == "development" for record in parameters["trainingRecords"]))

    def test_candidate_results_preserve_ids_hashes_failures_and_no_confidence(self):
        # Keep both fit modes; add an eligible failed record that must never disappear.
        failed = copy.deepcopy(self.records[0])
        failed.update(id="failed", sourceID="failed", relativePath="failed.mp3", audioSHA256="f" * 64)
        self.records.append(failed)
        self.rows["failed"] = {"id": "failed", "relativePath": "failed.mp3", "audioSHA256": "f" * 64,
                               "sourceUnchanged": True, "key": None, "error": "decoder failed"}
        self.save_inputs()
        parameters_path = self.fit()
        for candidate in p.CANDIDATES:
            results = c.load_json(parameters_path.parent / candidate / "results.json")
            self.assertEqual({row["id"] for row in results}, {"major", "minor", "failed"})
            self.assertTrue(all(row["heuristicConfidence"] is None for row in results))
            bad = next(row for row in results if row["id"] == "failed")
            self.assertEqual(bad["error"], "decoder failed")
            run = c.load_json(parameters_path.parent / candidate / "run.json")
            self.assertTrue(run["experimental"])
            self.assertEqual(run["parametersSHA256"], c.digest(parameters_path))
            self.assertIn("not Swift source", run["engineDigestMeaning"])

    def test_validation_accepts_only_frozen_development_parameters_and_rejects_test(self):
        parameters = self.fit()
        self.predict(parameters)
        self.assertTrue((self.root / "predictions" / p.CANDIDATES[0] / "results.json").is_file())
        with self.assertRaises(c.ChallengeError):
            self.predict(parameters, "test", self.root / "test-output")
        parameters.write_text(parameters.read_text() + " ")
        with self.assertRaisesRegex(c.ChallengeError, "freeze hash"):
            self.predict(parameters, output=self.root / "changed-output")

    def test_re_frozen_parameters_cannot_claim_validation_training(self):
        parameters_path = self.fit()
        parameters = c.load_json(parameters_path)
        parameters["trainingRecords"][0]["id"] = "validation"
        parameters["trainingRecords"][0]["split"] = "validation"
        parameters_path.write_text(json.dumps(parameters))
        (parameters_path.parent / "freeze.json").write_text(json.dumps({"parametersSHA256": c.digest(parameters_path)}))
        with self.assertRaisesRegex(c.ChallengeError, "non-development"):
            self.predict(parameters_path)

    def test_no_usable_mode_raises_instead_of_inventing_a_trained_profile(self):
        self.records[1]["eligibleKey"] = None
        self.save_inputs()
        with self.assertRaisesRegex(c.ChallengeError, "eligible Minor"):
            self.fit()

    def test_no_existing_output_or_audio_output_or_symlink(self):
        output = self.root / "existing"
        output.mkdir()
        for destination in [output, self.audio / "results"]:
            with self.subTest(destination=destination), self.assertRaises(c.ChallengeError):
                p.fit(self.manifests["development"], self.baselines["development"], self.policy_path, destination)
        link = self.root / "alias"
        link.symlink_to(self.root, target_is_directory=True)
        with self.assertRaises(c.ChallengeError):
            p.fit(self.manifests["development"], self.baselines["development"], self.policy_path, link / "fit")


if __name__ == "__main__":
    unittest.main()
