import csv
import json
from pathlib import Path
import stat
import tempfile
import unittest
import zipfile

import challenge as c


class ChallengeTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name).resolve()
        self.audio_zip = self.root / "audio.zip"
        self.annotations_zip = self.root / "annotations.zip"
        self.output = self.root / "prepared"
        self.annotations = {
            "3271514": {"id": "3271514", "confidence": 2, "key": ["A minor aeolian"],
                        "start_times": [0], "end_times": [120], "comments": "verbatim original"},
            "2": {"id": "2", "confidence": 0, "key": ["Db major ionian"], "start_times": [0], "end_times": [120]},
            "3": {"id": "3", "confidence": 3, "key": ["C minor dorian"], "start_times": [0], "end_times": [120]},
        }
        self.audio_entries = {"audio/3271514 Mario & Vidis - Track.mp3": b"mock mp3 A",
                              "audio/2 Mario & Vidis - Second.mp3": b"mock mp3 B",
                              "audio/3 Other Artist - Track.mp3": b"mock mp3 C"}
        self.make_archives()

    def tearDown(self):
        self.temporary.cleanup()

    def make_archives(self):
        with zipfile.ZipFile(self.audio_zip, "w", zipfile.ZIP_STORED) as archive:
            for name, content in self.audio_entries.items():
                archive.writestr(name, content)
        with zipfile.ZipFile(self.annotations_zip, "w", zipfile.ZIP_STORED) as archive:
            for identifier, data in self.annotations.items():
                archive.writestr(f"new_annotations/{identifier}.json", json.dumps(data, indent=2))
        self.audio_spec = c.ArchiveSpec(c.digest(self.audio_zip, "md5"), self.audio_zip.stat().st_size)
        self.annotation_spec = c.ArchiveSpec(c.digest(self.annotations_zip, "md5"))

    def prepare(self, output=None):
        return c.prepare(self.audio_zip, self.annotations_zip, output or self.output,
                         audio_spec=self.audio_spec, annotation_spec=self.annotation_spec, expected_count=3)

    def policy(self):
        return c.load_json(self.prepare())

    def test_fixture_checksum_gate_preserves_exact_audio_raw_annotation_and_metadata(self):
        policy = self.policy()
        self.assertEqual(policy["counts"]["all"], 3)
        self.assertEqual(policy["counts"]["eligible"], 2)
        self.assertEqual(policy["counts"]["excluded"], 1)
        records = {record["id"]: record for record in policy["records"]}
        for identifier, annotation in self.annotations.items():
            raw_path = self.output / "raw-annotations" / (identifier + ".json")
            with zipfile.ZipFile(self.annotations_zip) as archive:
                raw = archive.read(f"new_annotations/{identifier}.json")
            self.assertEqual(raw_path.read_bytes(), raw)
            self.assertEqual(records[identifier]["rawAnnotation"], annotation)
            self.assertEqual(records[identifier]["rawAnnotationSHA256"], c.digest(raw_path))
            self.assertEqual(records[identifier]["audioSHA256"], c.digest(self.output / "audio" / records[identifier]["relativePath"]))
        self.assertEqual(records["2"]["eligibleKey"], "C# Major")
        self.assertEqual(records["2"]["rawAnnotation"]["confidence"], 0)
        self.assertEqual(policy["archives"]["audio"]["sha256"], c.digest(self.audio_zip))

    def test_production_checksum_and_size_cannot_accept_fixture(self):
        with self.assertRaisesRegex(c.ChallengeError, "size mismatch"):
            c.prepare(self.audio_zip, self.annotations_zip, self.output)
        with self.assertRaisesRegex(c.ChallengeError, "MD5 mismatch"):
            c.verify_archive(self.annotations_zip, c.ANNOTATION_SPEC)
        self.assertFalse(self.output.exists())

    def test_checksum_change_rejected_before_any_output(self):
        with self.audio_zip.open("ab") as handle:
            handle.write(b"unexpected")
        with self.assertRaises(c.ChallengeError):
            self.prepare()
        self.assertFalse(self.output.exists())

    def test_safe_inventory_rejects_traversal_absolute_windows_and_symlink(self):
        for name in ["../track.mp3", "/track.mp3", "C:/track.mp3", "folder\\track.mp3"]:
            path = self.root / "bad.zip"
            with zipfile.ZipFile(path, "w") as archive:
                archive.writestr(name, b"a")
            with zipfile.ZipFile(path) as archive, self.subTest(name=name), self.assertRaises(c.ChallengeError):
                c.safe_inventory(archive, 1000, 1000)
        path = self.root / "link.zip"
        entry = zipfile.ZipInfo("audio/track.mp3")
        entry.create_system = 3
        entry.external_attr = (stat.S_IFLNK | 0o777) << 16
        with zipfile.ZipFile(path, "w") as archive:
            archive.writestr(entry, "/outside")
        with zipfile.ZipFile(path) as archive, self.assertRaises(c.ChallengeError):
            c.safe_inventory(archive, 1000, 1000)

    def test_safe_inventory_bounds_entry_total_and_compression_ratio(self):
        path = self.root / "bounds.zip"
        with zipfile.ZipFile(path, "w") as archive:
            archive.writestr("one.mp3", b"a" * 100)
            archive.writestr("two.mp3", b"b" * 100)
        with zipfile.ZipFile(path) as archive:
            with self.assertRaises(c.ChallengeError):
                c.safe_inventory(archive, 99, 1000)
            with self.assertRaises(c.ChallengeError):
                c.safe_inventory(archive, 200, 199)
        with zipfile.ZipFile(path, "w", zipfile.ZIP_DEFLATED) as archive:
            archive.writestr("bomb.mp3", b"a" * 100000)
        with zipfile.ZipFile(path) as archive, self.assertRaisesRegex(c.ChallengeError, "ratio"):
            c.safe_inventory(archive, 200000, 200000)

    def test_only_regular_mp3_extracts_and_ids_match_annotations(self):
        self.audio_entries["audio/4 Unexpected - Track.wav"] = b"wav"
        self.make_archives()
        with self.assertRaises(c.ChallengeError):
            self.prepare()
        self.audio_entries.pop("audio/4 Unexpected - Track.wav")
        self.audio_entries["audio/99 Different - Track.mp3"] = self.audio_entries.pop("audio/3 Other Artist - Track.mp3")
        self.make_archives()
        with self.assertRaisesRegex(c.ChallengeError, "IDs do not match"):
            self.prepare()
        self.assertFalse(self.output.exists())

    def test_annotation_id_and_count_mismatches_rejected(self):
        self.annotations["3"]["id"] = "999"
        self.make_archives()
        with self.assertRaisesRegex(c.ChallengeError, "ID mismatch"):
            self.prepare()
        self.annotations.pop("3")
        self.make_archives()
        with self.assertRaisesRegex(c.ChallengeError, "count mismatch"):
            self.prepare()

    def test_major_minor_qualifiers_and_enharmonics_normalize_consistently(self):
        for label, expected in [("Db major", "C# Major"), ("Gb minor harmonic", "F# Minor"),
                                ("E minor melodic", "E Minor"), ("C major ionian", "C Major"),
                                ("A minor aeolian", "A Minor")]:
            value, reasons = c.annotation_policy({"key": [label], "start_times": [0], "end_times": [120]})
            self.assertEqual((value, reasons), (expected, []))
        value, reasons = c.annotation_policy({"key": ["Db major", "C# major ionian"], "start_times": [0, 60], "end_times": [60, 120]})
        self.assertEqual((value, reasons), ("C# Major", []))

    def test_ambiguous_modal_unknown_and_cross_region_keys_excluded(self):
        for label in ["C major | A minor", "C minor dorian", "G major mixolydian", "X", "C major aeolian",
                      "E other", "B minor ionian", "D minor phygian", "Eb^ minor"]:
            with self.subTest(label=label):
                key, reasons = c.annotation_policy({"key": [label], "start_times": [0], "end_times": [120]})
                self.assertIsNone(key)
                self.assertTrue(reasons)
        key, reasons = c.annotation_policy({"key": ["C major", "A minor"], "start_times": [0, 60], "end_times": [60, 120]})
        self.assertIsNone(key)
        self.assertIn("different normalized keys across annotated regions", reasons)

    def test_invalid_intervals_excluded_without_repair(self):
        for starts, ends in [([0], [121]), ([80], [20]), ([-1], [10]), ([0], [0]),
                             ([float("nan")], [120]), ([True], [120]), ([0, 30], [60, 120]), ([0], [60, 120])]:
            keys = ["C major"] * len(starts)
            with self.subTest(starts=starts, ends=ends):
                key, reasons = c.annotation_policy({"key": keys, "start_times": starts, "end_times": ends})
                self.assertIsNone(key)
                self.assertTrue(reasons)

    def test_artist_partition_and_previously_inspected_groupmates_forced_development(self):
        records = self.policy()["records"]
        by_id = {record["id"]: record for record in records}
        self.assertEqual(by_id["3271514"]["split"], "development")
        self.assertEqual(by_id["2"]["split"], "development")
        self.assertTrue(by_id["2"]["forcedDevelopment"])
        self.assertEqual(by_id["3271514"]["partitionGroupID"], by_id["2"]["partitionGroupID"])
        self.assertNotEqual(by_id["3271514"]["familyID"], by_id["2"]["familyID"])
        copied = json.loads(json.dumps(records))
        c.assign_groups(copied)
        self.assertEqual([(r["split"], r["familyID"]) for r in records], [(r["split"], r["familyID"]) for r in copied])
        self.assertEqual(c.audio_identity("9  MÁRIO   & VIDIS - Song.mp3")[2], "mário & vidis")

    def test_identical_recordings_connect_artist_partitions_and_conflicts_exclude(self):
        self.audio_entries["audio/3 Other Artist - Track.mp3"] = self.audio_entries["audio/3271514 Mario & Vidis - Track.mp3"]
        self.annotations["3"]["key"] = ["C major"]
        self.make_archives()
        by_id = {record["id"]: record for record in self.policy()["records"]}
        self.assertEqual(by_id["3271514"]["familyID"], by_id["3"]["familyID"])
        self.assertEqual(by_id["3"]["split"], "development")
        self.assertIsNone(by_id["3271514"]["eligibleKey"])
        self.assertIsNone(by_id["3"]["eligibleKey"])

    def test_primary_artist_collaboration_and_solo_share_partition_with_ampersand_names_preserved(self):
        self.audio_entries["audio/3 Mario & Vidis, Other Artist - Collaboration.mp3"] = self.audio_entries.pop("audio/3 Other Artist - Track.mp3")
        self.make_archives()
        by_id = {record["id"]: record for record in self.policy()["records"]}
        self.assertEqual(by_id["3"]["artistRaw"], "Mario & Vidis, Other Artist")
        self.assertEqual(by_id["3"]["artistGroup"], "mario & vidis")
        self.assertEqual(by_id["3"]["partitionGroupID"], by_id["3271514"]["partitionGroupID"])
        self.assertEqual(by_id["3"]["split"], "development")
        self.assertEqual(c.audio_identity("9 Aly & Fila, Someone - Track.mp3")[2], "aly & fila")

    def test_manifests_keep_all_including_excluded_and_freeze_hashes(self):
        policy = self.policy()
        combined = c.load_json(self.output / "manifest.json")
        self.assertEqual(len(combined["candidates"]), 3)
        self.assertTrue(all(row["provisionalKey"] is None for row in combined["candidates"]))
        assigned = []
        for split in ["development", "validation", "test"]:
            data = c.load_json(self.output / "manifests" / (split + ".json"))
            assigned.extend(row["id"] for row in data["candidates"])
            self.assertEqual(c.digest(self.output / "manifests" / (split + ".json")), policy["manifests"][split]["sha256"])
        self.assertEqual(set(assigned), {"3271514", "2", "3"})
        self.assertEqual(len(assigned), 3)
        freeze = c.load_json(self.output / "freeze.json")
        self.assertEqual(freeze["policySHA256"], c.digest(self.output / "policy.json"))
        with (self.output / "label-policy.csv").open(newline="", encoding="utf-8") as handle:
            self.assertEqual(len(list(csv.DictReader(handle))), 3)

    def make_baseline(self):
        policy_path = self.prepare()
        policy = c.load_json(policy_path)
        manifest_path = self.output / "manifest.json"
        baseline_root = self.root / "baseline"
        baseline_root.mkdir()
        baseline_path = baseline_root / "results.json"
        rows = [{"id": record["id"], "relativePath": record["relativePath"], "audioSHA256": record["audioSHA256"],
                 "sourceUnchanged": True, "key": None, "error": "mock decode error"} for record in policy["records"]]
        baseline_path.write_text(json.dumps(rows))
        run = {"manifestSHA256": c.digest(manifest_path), "selectedIDs": [row["id"] for row in rows]}
        (baseline_root / "run.json").write_text(json.dumps(run))
        return policy_path, manifest_path, baseline_path, rows

    def test_emit_labels_preserves_published_labels_even_when_detector_fails(self):
        policy, manifest, baseline, _ = self.make_baseline()
        output = self.root / "labels.csv"
        self.assertEqual(c.emit_labels(manifest, baseline, policy, output), 2)
        with output.open(newline="", encoding="utf-8") as handle:
            rows = list(csv.DictReader(handle))
        self.assertTrue(all(row["verifiedKey"] == row["reviewedKey"] and not row["keyfinderKey"] for row in rows))
        self.assertTrue(all("Published human" in row["evidence"] for row in rows))
        self.assertTrue(all(row["split"] == "development" for row in rows))

    def test_emit_labels_rejects_hash_mismatch_changed_policy_unknown_ids_and_existing_output(self):
        policy, manifest, baseline, rows = self.make_baseline()
        output = self.root / "labels.csv"
        bad = json.loads(json.dumps(rows))
        bad[0]["audioSHA256"] = "f" * 64
        baseline.write_text(json.dumps(bad))
        with self.assertRaises(c.ChallengeError):
            c.emit_labels(manifest, baseline, policy, output)
        bad[0]["audioSHA256"] = rows[0]["audioSHA256"]
        bad[0]["id"] = "unknown"
        baseline.write_text(json.dumps(bad))
        with self.assertRaises(c.ChallengeError):
            c.emit_labels(manifest, baseline, policy, output)
        baseline.write_text(json.dumps(rows))
        c.emit_labels(manifest, baseline, policy, output)
        with self.assertRaises(c.ChallengeError):
            c.emit_labels(manifest, baseline, policy, output)
        policy.write_text(policy.read_text() + " ")
        with self.assertRaisesRegex(c.ChallengeError, "policy hash"):
            c.emit_labels(manifest, baseline, policy, self.root / "other.csv")

    def test_outputs_and_input_archives_cannot_be_symlinks(self):
        link = self.root / "link"
        link.symlink_to(self.root, target_is_directory=True)
        with self.assertRaises(c.ChallengeError):
            self.prepare(link / "prepared")
        archive_alias = self.root / "alias.zip"
        archive_alias.symlink_to(self.audio_zip)
        with self.assertRaises(c.ChallengeError):
            c.verify_archive(archive_alias, self.audio_spec)

    def test_cli_has_no_checksum_count_or_partition_override(self):
        with self.assertRaises(SystemExit):
            c.main(["prepare", "--audio-zip", str(self.audio_zip), "--annotations-zip", str(self.annotations_zip),
                    "--output", str(self.output), "--skip-checksum"])


if __name__ == "__main__":
    unittest.main()
