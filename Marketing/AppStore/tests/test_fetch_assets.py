import hashlib
import importlib.util
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

MODULE = Path(__file__).resolve().parents[1] / 'fetch_assets.py'
spec = importlib.util.spec_from_file_location('fetch_assets', MODULE)
f = importlib.util.module_from_spec(spec)
spec.loader.exec_module(f)


class FetchAssetsTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.content = b'approved asset archive fixture'
        self.digest = hashlib.sha256(self.content).hexdigest()
        self.config = self.root / 'asset-bundle.json'
        self.recipe = self.root / 'recipe.json'
        self.output = self.root / 'result'
        self.config.write_text(json.dumps({'schemaVersion': 1, 'releaseTag': 'app-store-assets-v1', 'fileName': 'Approved.zip', 'bytes': len(self.content), 'sha256': self.digest}))
        self.recipe.write_text(json.dumps({'approved_bundle_sha256': self.digest}))
        self.calls = []

    def process(self, arguments, **kwargs):
        self.calls.append(arguments)
        if arguments[0] == 'gh':
            directory = Path(arguments[arguments.index('--dir') + 1])
            (directory / 'Approved.zip').write_bytes(self.content)
        else:
            directory = Path(arguments[arguments.index('--output') + 1])
            directory.mkdir()
            (directory / 'manifest.json').write_text('{}')
        return subprocess.CompletedProcess(arguments, 0, 'https://private.invalid/not-printed', '')

    def test_exact_release_download_verified_then_atomic_unpack(self):
        with patch.object(subprocess, 'run', side_effect=self.process):
            result = f.fetch(self.config, self.recipe, 'owner/currency', self.output)
        command = self.calls[0]
        self.assertEqual(command[:4], ['gh', 'release', 'download', 'app-store-assets-v1'])
        self.assertEqual(command[command.index('--repo') + 1], 'owner/currency')
        self.assertEqual(command[command.index('--pattern') + 1], 'Approved.zip')
        self.assertEqual(len(self.calls), 2)
        self.assertTrue((self.output / 'manifest.json').is_file())
        self.assertEqual(result['sha256'], self.digest)
        self.assertFalse(any(p.name.startswith('currency-asset-download-') for p in self.root.iterdir()))

    def test_wrong_checksum_or_size_never_unpacks(self):
        original = self.content
        for changed in (b'X' * len(original), b'truncated'):
            with self.subTest(length=len(changed)):
                self.content = changed
                self.calls = []
                with patch.object(subprocess, 'run', side_effect=self.process):
                    with self.assertRaises(f.FetchError):
                        f.fetch(self.config, self.recipe, 'owner/currency', self.output)
                self.assertEqual(len(self.calls), 1)
                self.assertFalse(self.output.exists())
                self.assertFalse(any(p.name.startswith('currency-asset-download-') for p in self.root.iterdir()))

    def test_mismatched_recipe_fails_before_download(self):
        self.recipe.write_text(json.dumps({'approved_bundle_sha256': '0' * 64}))
        with patch.object(subprocess, 'run') as run:
            with self.assertRaisesRegex(f.FetchError, 'recipe disagree'):
                f.fetch(self.config, self.recipe, 'owner/currency', self.output)
            run.assert_not_called()

    def test_nonempty_output_refused_before_download(self):
        self.output.mkdir()
        (self.output / 'keep').write_text('existing media')
        with patch.object(subprocess, 'run') as run:
            with self.assertRaisesRegex(f.FetchError, 'empty'):
                f.fetch(self.config, self.recipe, 'owner/currency', self.output)
            run.assert_not_called()
        self.assertEqual((self.output / 'keep').read_text(), 'existing media')

    def test_partial_unpack_failure_rolls_back_and_suppresses_urls(self):
        def fail_unpack(arguments, **kwargs):
            result = self.process(arguments, **kwargs)
            if arguments[0] != 'gh':
                return subprocess.CompletedProcess(arguments, 1, 'https://private.invalid/signed-upload', 'PRIVATE_TOKEN')
            return result
        with patch.object(subprocess, 'run', side_effect=fail_unpack):
            with self.assertRaises(f.FetchError) as error:
                f.fetch(self.config, self.recipe, 'owner/currency', self.output)
        self.assertNotIn('https', str(error.exception))
        self.assertNotIn('PRIVATE', str(error.exception))
        self.assertFalse(self.output.exists())
        self.assertFalse(any(p.name.startswith('currency-asset-download-') for p in self.root.iterdir()))

    def test_config_cannot_select_latest_globs_or_paths(self):
        for key, value in [('releaseTag', 'latest'), ('releaseTag', 'v1.0'), ('fileName', '*.zip'), ('fileName', '../Approved.zip')]:
            with self.subTest(key=key, value=value):
                config = json.loads(self.config.read_text())
                config[key] = value
                invalid = self.root / 'invalid.json'
                invalid.write_text(json.dumps(config))
                with patch.object(subprocess, 'run') as run:
                    with self.assertRaises(f.FetchError):
                        f.fetch(invalid, self.recipe, 'owner/currency', self.output)
                    run.assert_not_called()


if __name__ == '__main__':
    unittest.main()
