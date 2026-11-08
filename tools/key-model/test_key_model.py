import json
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from acceptance import wilson  # noqa: E402
import export_weights  # noqa: E402

try:
    import numpy  # noqa: F401
    import reference
except ImportError:  # reference needs numpy; the key-model venv provides it
    reference = None


class AcceptanceTests(unittest.TestCase):
    def test_wilson_interval(self):
        low, high = wilson(61, 85)
        self.assertAlmostEqual(low, 0.614, places=3)
        self.assertAlmostEqual(high, 0.802, places=3)
        self.assertEqual(wilson(0, 0), (0.0, 0.0))


class ExportTests(unittest.TestCase):
    def test_export_keeps_every_weight_exactly(self):
        weights = {"0.weight": [[0.1 * (r + c) for c in range(72)] for r in range(3)], "0.bias": [0.5, -0.25, 1e-17],
                   "3.weight": [[1.0, 2.0, 3.0], [-1.0, -2.0, -3.0]], "3.bias": [0.0, 0.125]}
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            (root / "m.json").write_text(json.dumps({"weights": weights}))
            (root / "p.json").write_text(json.dumps({"majorProfile": [1 / 12] * 12, "minorProfile": [1 / 12] * 12}))
            sys.argv = ["x", "--model", str(root / "m.json"), "--profiles", str(root / "p.json"),
                        "--swift", str(root / "w.swift"), "--cpp", str(root / "w.h")]
            export_weights.main()
            cpp = (root / "w.h").read_text()
            self.assertIn("hiddenUnits = 3", cpp)
            self.assertIn("hiddenWeights[216]", cpp)
            self.assertIn("1e-17", cpp)
            self.assertIn("CC BY-SA 4.0", (root / "w.swift").read_text())


@unittest.skipIf(reference is None, "numpy not available")
class ReferenceTests(unittest.TestCase):
    def test_equivariant_shift_moves_tonic(self):
        import numpy as np
        # One hidden unit that fires on energy at bin 0 (A1 in the feature) and votes major.
        w = {"0.weight": np.zeros((1, 72)), "0.bias": np.zeros(1), "3.weight": np.array([[5.0], [0.0]]),
             "3.bias": np.zeros(2)}
        w["0.weight"][0, 0] = 1.0
        pitch = [0.0] * 72
        pitch[7] = 1.0  # energy 7 semitones above the feature's lowest bin
        probabilities = reference.probabilities(w, [{"pitch": pitch}])
        self.assertEqual(int(np.argmax(probabilities)), 7)  # tonic index 7 (G) wins, major
        self.assertIsNone(reference.probabilities(w, [{"pitch": [0.0] * 72}]))


if __name__ == "__main__":
    unittest.main()
