"""Report integrity checks use synthetic result files, never catalog audio."""
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

SCRIPT = Path(__file__).with_name('catalog-agreement.py')


class CatalogAgreementTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.candidates = [dict(id='a', relativePath='120 Am.wav', provisionalKey='A Minor', provisionalBPM=120),
                           dict(id='b', relativePath='120 C.wav', provisionalKey='C Major', provisionalBPM=120)]
        self.rows = [dict(id=c['id'], key=c['provisionalKey'], bpm=120, sourceUnchanged=True)
                     for c in self.candidates]

    def report(self, current=None, baseline=None, plugin=None):
        (self.root / 'manifest.json').write_text(json.dumps(dict(root='/private/audio', candidates=self.candidates)))
        for name, rows in [('current-full', self.rows if current is None else current),
                           ('baseline-key', self.rows if baseline is None else baseline)]:
            folder = self.root / name
            folder.mkdir(exist_ok=True)
            (folder / 'results.json').write_text(json.dumps(rows))
        args = [sys.executable, str(SCRIPT), str(self.root)]
        if plugin is not None:
            path = self.root / 'plugin.tsv'
            path.write_text(plugin)
            args += ['--plugin', str(path)]
        return subprocess.run(args, capture_output=True, text=True)

    def test_complete_report_preserves_label_agreement(self):
        result = self.report()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('**2/2** (100.0%)', result.stdout)
        self.assertIn('Source files unchanged: True', result.stdout)

    def test_missing_results_cannot_claim_all_sources_unchanged(self):
        result = self.report(current=self.rows[:1])
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('missing current results: 1', result.stdout)
        self.assertNotIn('Source files unchanged: True', result.stdout)
        self.assertIn('**1/2** (50.0%)', result.stdout)

    def test_empty_results_are_unverified(self):
        result = self.report(current=[])
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn('Source files unchanged: True', result.stdout)

    def test_changed_or_unverified_sources_cannot_claim_success(self):
        for value in [False, None, 'true']:
            with self.subTest(value=value):
                rows = [dict(r) for r in self.rows]
                rows[0]['sourceUnchanged'] = value
                self.assertNotIn('Source files unchanged: True', self.report(current=rows).stdout)

    def test_duplicate_current_and_baseline_ids_rejected(self):
        for keyword in ['current', 'baseline']:
            with self.subTest(keyword=keyword):
                result = self.report(**{keyword: self.rows + self.rows[:1]})
                self.assertNotEqual(result.returncode, 0)
                self.assertIn('duplicate', result.stderr.lower())

    def test_unknown_result_ids_rejected(self):
        result = self.report(current=self.rows + [dict(id='unknown')])
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('unknown', result.stderr.lower())

    def test_duplicate_manifest_ids_rejected(self):
        self.candidates.append(self.candidates[0])
        result = self.report()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('duplicate', result.stderr.lower())

    def test_plugin_missing_and_error_rows_are_reported(self):
        result = self.report(plugin='/private/audio/120 Am.wav\tAm\t8A\t120\t\n')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('missing plugin results: 1', result.stdout)
        result = self.report(plugin='/private/audio/120 Am.wav\t\t\t\tdecode failed\n')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('plugin errors: 1', result.stdout)

    def test_duplicate_plugin_paths_rejected(self):
        row = '/private/audio/120 Am.wav\tAm\t8A\t120\t\n'
        result = self.report(plugin=row + row)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('duplicate', result.stderr.lower())


if __name__ == '__main__':
    unittest.main()
