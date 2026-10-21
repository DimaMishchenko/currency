import hashlib
import importlib.util
import json
from pathlib import Path
import subprocess
import struct
import sys
import tempfile
import unittest
from unittest.mock import patch

MODULE = Path(__file__).resolve().parents[1] / 'upload.py'
spec = importlib.util.spec_from_file_location('uploader', MODULE)
u = importlib.util.module_from_spec(spec)
spec.loader.exec_module(u)


def row(identifier, **attrs):
    return {'id': identifier, 'attributes': attrs}


class FakeCLI:
    def __init__(self, state=None, apply=False):
        self.state, self.apply, self.calls = state or {}, apply, []

    def api(self, method, path, body=None):
        self.calls.append((method, path, body))
        if method != 'GET':
            if not self.apply:
                raise AssertionError('Dry-run attempted mutation')
            return {'data': {'id': 'created-' + str(len(self.calls))}}
        return {'data': self.state.get(path, [])}

    def run(self, args, body=None, mutate=False):
        if mutate and not self.apply:
            raise AssertionError('Dry-run attempted command mutation')
        self.calls.append(('COMMAND', args, body))
        return {'videoId': 'uploaded-video'}


class UploaderTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        self.addCleanup(self.tmp.cleanup)
        self.meta = {'appId': '6816213577', 'locales': {'en-US': {'name': 'Currency', 'description': 'Convert', 'promotionalText': 'Fast', 'contextualPromotionalText': {f: 'About ' + f for f in u.FAMILIES[1:]}}}}
        self.slots = {}
        for profile in u.PROFILES:
            for i in range(1, 7):
                file = self.root / (profile + str(i) + '.png')
                file.write_bytes((profile + str(i)).encode())
                self.slots[('en-US', profile, 'default', i)] = {'file': file}
        self.state = {
            '/v1/apps/6816213577/appStoreVersions': [row('version', platform='IOS', versionString='1.2', appStoreState='PREPARE_FOR_SUBMISSION')],
            '/v1/apps/6816213577/appInfos': [row('info', appStoreState='PREPARE_FOR_SUBMISSION')],
            '/v1/appStoreVersions/version/appStoreVersionLocalizations': [row('locale', locale='en-US', description='Convert', promotionalText='Fast')],
            '/v1/appInfos/info/appInfoLocalizations': [row('info-locale', locale='en-US', name='Currency')],
        }

    def planner(self, cli, scopes):
        return u.Planner(cli, self.meta, self.slots, {}, 'version', '1.2', 'info', scopes)

    def test_dry_run_only_reads_and_plans_uploads(self):
        cli = FakeCLI(self.state)
        plan = self.planner(cli, {'default'}).preflight()
        self.assertEqual([o['method'] for o in plan.ops], ['SCREENSHOTS'] * 3)
        self.assertTrue(all(c[0] == 'GET' for c in cli.calls))
        with self.assertRaisesRegex(u.UploadError, 'Apply mode'):
            plan.execute()
        self.assertTrue(all(c[0] == 'GET' for c in cli.calls))

    def test_unchanged_metadata_is_idempotent(self):
        cli = FakeCLI(self.state)
        plan = self.planner(cli, {'metadata'}).preflight()
        self.assertEqual(plan.ops, [])

    def test_complete_matching_screenshots_are_idempotent(self):
        sets = []
        for profile, display in u.PROFILES.items():
            sets.append(row(profile, screenshotDisplayType=display))
            self.state['/v1/appScreenshotSets/' + profile + '/appScreenshots'] = [row(str(i), sourceFileChecksum=hashlib.md5(self.slots[('en-US', profile, 'default', i)]['file'].read_bytes()).hexdigest(), assetDeliveryState={'state': 'COMPLETE'}) for i in range(1, 7)]
        self.state['/v1/appStoreVersionLocalizations/locale/appScreenshotSets'] = sets
        plan = self.planner(FakeCLI(self.state), {'default'}).preflight()
        self.assertEqual(plan.ops, [])

    def test_conflicting_screenshot_refuses_before_writes(self):
        self.state['/v1/appStoreVersionLocalizations/locale/appScreenshotSets'] = [row('set', screenshotDisplayType='APP_IPHONE_61')]
        self.state['/v1/appScreenshotSets/set/appScreenshots'] = [row('old', sourceFileChecksum='different')]
        cli = FakeCLI(self.state, apply=True)
        with self.assertRaisesRegex(u.UploadError, 'differs'):
            self.planner(cli, {'metadata', 'default'}).preflight()
        self.assertTrue(all(c[0] == 'GET' for c in cli.calls))

    def test_live_or_wrong_version_refuses_before_mutation(self):
        for field, value in [('appStoreState', 'READY_FOR_SALE'), ('versionString', '8.0')]:
            with self.subTest(field=field):
                self.state['/v1/apps/6816213577/appStoreVersions'][0]['attributes'][field] = value
                cli = FakeCLI(self.state, apply=True)
                with self.assertRaises(u.UploadError):
                    self.planner(cli, {'metadata'}).preflight()
                self.assertTrue(all(c[0] == 'GET' for c in cli.calls))

    def test_duo_queues_native_images_and_exact_order_without_legacy_enum(self):
        cli = FakeCLI(self.state)
        plan = self.planner(cli, {'duo'})
        plan.library = 'library'
        for profile in ('duo-outer', 'duo-inner'):
            for order in range(1, 7):
                file = self.root / (profile + str(order) + '.png')
                file.write_bytes((profile + str(order)).encode())
                self.slots[('en-US', profile, 'default', order)] = {'file': file, 'sha256': u.sha256(file)}
        plan.duo_screenshots('locale', 'default', 'en-US')
        uploads = [op for op in plan.ops if op['method'] == 'LIBRARY']
        placements = [op for op in plan.ops if op['path'] == '/v1/appAssetLibraryPlacements']
        self.assertEqual(len(uploads), 12)
        self.assertEqual(len(placements), 12)
        self.assertTrue(all(op['body']['data']['attributes']['placementGroup'] == 'IPHONE_DUO_PROFILE' for op in placements))
        ordering = plan.ops[-1]['body']['data']
        self.assertEqual(ordering['relationships']['orderedPlacements']['data'], [{'type': 'appAssetLibraryPlacements', 'id': op['ref']} for op in placements])
        self.assertNotIn('APP_IPHONE_DUO', json.dumps(plan.summary()))
        self.assertTrue(all(call[0] == 'GET' for call in cli.calls))

    def test_profile_mapping_matches_approved_recipe_dimensions(self):
        recipe = json.loads((MODULE.parent / 'design' / 'recipe.json').read_text())
        for placement in recipe['placements']:
            self.assertEqual(u.DIMENSIONS[placement['profile']], (placement['width'], placement['height']))
        self.assertEqual(u.PROFILES['watch'], 'APP_WATCH_SERIES_10')

    def test_png_preflight_rejects_alpha_transparency_and_wrong_size(self):
        def png(color=2, extra=b''):
            return b'\x89PNG\r\n\x1a\n' + struct.pack('>I4sIIBBBBBI', 13, b'IHDR', 2, 3, 8, color, 0, 0, 0, 0) + extra + struct.pack('>I4sI', 0, b'IEND', 0)
        image = self.root / 'test.png'
        image.write_bytes(png())
        u.validate_png(image, (2, 3))
        with self.assertRaisesRegex(u.UploadError, 'dimensions'):
            u.validate_png(image, (3, 2))
        image.write_bytes(png(color=6))
        with self.assertRaisesRegex(u.UploadError, 'alpha'):
            u.validate_png(image, (2, 3))
        image.write_bytes(png(extra=struct.pack('>I4sI', 0, b'tRNS', 0)))
        with self.assertRaisesRegex(u.UploadError, 'transparency'):
            u.validate_png(image, (2, 3))

    def test_partial_failure_receipt_contains_ids_without_urls(self):
        receipt = self.root / 'receipts.jsonl'
        cli = u.CLI(apply=True, receipts=receipt)
        response = subprocess.CompletedProcess([], 1, json.dumps({'videoId': 'reserved-video', 'uploadOperations': [{'url': 'https://private.invalid/signed-token'}]}), 'private')
        with patch.object(subprocess, 'run', return_value=response):
            with self.assertRaises(u.UploadError):
                cli.run(['asset-library', 'videos', 'upload'], mutate=True)
        text = receipt.read_text()
        self.assertIn('reserved-video', text)
        self.assertNotIn('https', text)
        self.assertNotIn('signed-token', text)
        self.assertEqual(receipt.stat().st_mode & 0o777, 0o600)

    def test_pending_ids_resolve_in_order(self):
        cli = FakeCLI(apply=True)
        plan = self.planner(cli, set())
        parent = plan.queue('POST', '/v1/appCustomProductPages', u.resource('appCustomProductPages', {'name': 'offline'}))
        plan.queue('POST', '/v1/appCustomProductPageVersions', u.resource('appCustomProductPageVersions', {}, {'appCustomProductPage': u.relationship('appCustomProductPages', parent)}))
        plan.execute()
        self.assertEqual(cli.calls[1][2]['data']['relationships']['appCustomProductPage']['data']['id'], 'created-1')

    def test_cli_suppresses_sensitive_failure_output(self):
        cli = u.CLI(apply=True)
        result = subprocess.CompletedProcess([], 1, 'https://private-upload.invalid/token', 'PRIVATE_KEY_AND_URL')
        with patch.object(subprocess, 'run', return_value=result) as run:
            with self.assertRaises(u.UploadError) as error:
                cli.api('POST', '/v1/appInfos', {'data': {}})
        self.assertNotIn('PRIVATE', str(error.exception))
        self.assertNotIn('private-upload', str(error.exception))
        self.assertEqual(run.call_args.kwargs['input'], '{"data": {}}')
        self.assertNotIn('shell', run.call_args.kwargs)

    def test_cli_mutation_guard_runs_before_subprocess(self):
        with patch.object(subprocess, 'run') as run:
            with self.assertRaisesRegex(u.UploadError, 'dry-run'):
                u.CLI().api('POST', '/v1/appInfos', {})
            run.assert_not_called()

    def test_media_path_traversal_and_symlinks_are_refused(self):
        for name in ('../escape', '/absolute', 'same/../escape'):
            with self.subTest(name=name):
                with self.assertRaisesRegex(u.UploadError, 'path'):
                    u.confined(self.root, name)
        actual = self.root / 'actual.png'
        actual.write_bytes(b'image')
        (self.root / 'link.png').symlink_to(actual)
        with self.assertRaisesRegex(u.UploadError, 'symlink'):
            u.confined(self.root, 'link.png')

    def test_validate_only_never_constructs_remote_client(self):
        metadata = self.root / 'metadata.json'
        metadata.write_text('{}')
        (self.root / 'manifest.json').write_text('{}')
        with patch.object(sys, 'argv', ['upload.py', '--validate-only', '--metadata', str(metadata), '--media-dir', str(self.root)]), patch.object(u, 'validate_media', return_value=({'placement': {}}, {})), patch.object(u, 'CLI') as client:
            self.assertEqual(u.main(), 0)
            client.assert_not_called()

    def test_remote_plan_requires_explicit_ids_and_receipts(self):
        with patch.object(sys, 'argv', ['upload.py']), patch.object(u, 'validate_media') as validate:
            with self.assertRaises(SystemExit) as error:
                u.main()
            self.assertEqual(error.exception.code, 2)
            validate.assert_not_called()

    def test_validate_only_rejects_apply(self):
        with patch.object(sys, 'argv', ['upload.py', '--validate-only', '--apply']), patch.object(u, 'CLI') as client:
            with self.assertRaises(SystemExit) as error:
                u.main()
            self.assertEqual(error.exception.code, 2)
            client.assert_not_called()

    def test_failed_first_mutation_stops_plan(self):
        class Failing(FakeCLI):
            def api(self, method, path, body=None):
                self.calls.append((method, path, body))
                raise u.UploadError('asc command failed')
        cli = Failing(apply=True)
        plan = self.planner(cli, set())
        plan.queue('POST', '/v1/appInfos', {})
        plan.queue('POST', '/v1/appInfos', {})
        with self.assertRaises(u.UploadError):
            plan.execute()
        self.assertEqual(len(cli.calls), 1)


if __name__ == '__main__':
    unittest.main()
