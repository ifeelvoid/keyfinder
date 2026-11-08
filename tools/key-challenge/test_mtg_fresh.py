import unittest

from mtg_fresh import artist_credits, base_title, canonical_key, exclusion_reasons
from score_modes import relation, sign_test

PRIOR = {"ids": {"1"}, "hashes": {"h-prior"}, "credits": {"aly & fila"}, "titles": {"far away"}}
CLEAN = {"id": "9", "artists": "New Artist", "title": "Fresh Song", "main_key": "Bb minor",
         "confidence": "2", "time1": "", "change1": "", "time2": "", "change2": "", "comments": ""}


class MTGFreshTests(unittest.TestCase):
    def test_canonical_key(self):
        self.assertEqual(canonical_key("Bb minor"), "A# Minor")
        self.assertEqual(canonical_key(" F# major "), "F# Major")
        self.assertIsNone(canonical_key("F minor phrygian"))
        self.assertIsNone(canonical_key("C# minor | E major"))
        self.assertIsNone(canonical_key("X"))

    def test_identity_normalization(self):
        self.assertEqual(artist_credits("Aly & Fila, Someone"), {"aly & fila", "someone"})
        self.assertEqual(base_title("Far Away feat. X (Original Mix)"), "far away")

    def test_clean_row_is_eligible(self):
        self.assertEqual(exclusion_reasons(CLEAN, "A# Minor", "Bb minor", PRIOR, "h-new"), [])

    def test_every_gate_excludes(self):
        cases = [
            ({"confidence": "1"}, "confidence-1"),
            ({"change1": "A minor"}, "key-change-fields"),
            ({"comments": "Confusion with F minor is possible"}, "annotator-comment"),
            ({"id": "1"}, "prior-source-id"),
            ({"artists": "Someone, Aly & Fila"}, "prior-artist-credit"),
            ({"title": "Far Away"}, "prior-base-title"),
        ]
        for change, reason in cases:
            with self.subTest(reason=reason):
                self.assertIn(reason, exclusion_reasons({**CLEAN, **change}, "A# Minor", "Bb minor", PRIOR, "h-new"))
        self.assertIn("prior-audio-hash", exclusion_reasons(CLEAN, "A# Minor", "Bb minor", PRIOR, "h-prior"))
        self.assertIn("no-audio-member", exclusion_reasons(CLEAN, "A# Minor", "Bb minor", PRIOR, None))
        self.assertIn("key-file-disagrees-with-spreadsheet",
                      exclusion_reasons(CLEAN, "A# Minor", "C minor", PRIOR, "h-new"))


class ScoreModesTests(unittest.TestCase):
    def test_relations(self):
        self.assertEqual(relation("A Minor", "C Major"), "relative")
        self.assertEqual(relation("C Major", "A Minor"), "relative")
        self.assertEqual(relation("G Major", "C Major"), "fifth")
        self.assertEqual(relation("C Minor", "C Major"), "parallel")
        self.assertEqual(relation("F Major", "G Minor"), "other")
        self.assertEqual(relation(None, "C Major"), "missing")

    def test_sign_test(self):
        self.assertAlmostEqual(sign_test(6, 0), 0.03125)
        self.assertEqual(sign_test(0, 0), 1.0)


if __name__ == "__main__":
    unittest.main()
