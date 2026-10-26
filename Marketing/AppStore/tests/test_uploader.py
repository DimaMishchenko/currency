import hashlib
import io
import importlib.util
import json
from pathlib import Path
import subprocess
import struct
import sys
import tempfile
import threading
from types import SimpleNamespace
import unittest
from unittest.mock import patch

MODULE = Path(__file__).resolve().parents[1] / 'upload.py'
spec = importlib.util.spec_from_file_location('uploader', MODULE)
u = importlib.util.module_from_spec(spec)
spec.loader.exec_module(u)


def row(identifier, **attrs):
    return {'id': identifier, 'attributes': attrs}


def native_reference(duo_limit=12, cpp_limit=None, header_limit=1, split=False):
    groups = ['DUO_OUTER_PROFILE', 'DUO_INNER_PROFILE'] if split else ['IPHONE_DUO_PROFILE']
    attributes = {
        'features': [{'featureId': feature, 'placementPolicies': [
            {'placementType': 'APP_SCREENSHOT', 'groupLimits': [{'groupIds': groups, 'maxCount': duo_limit if feature == 'APP_STORE_VERSIONS' or cpp_limit is None else cpp_limit}]},
            {'placementType': 'PRODUCT_PAGE_HEADER_ASSET', 'groupLimits': [{'groupIds': ['DEFAULT_PROFILE'], 'maxCount': header_limit}]},
        ]} for feature in ('APP_STORE_VERSIONS', 'CUSTOM_PRODUCT_PAGES')],
        'placementProfileGroups': [{'placementProfileGroupId': group, 'platform': 'IPHONE_APP_STORE', 'displayClassId': 'IPHONE_DUO'} for group in groups] + [{'placementProfileGroupId': 'DEFAULT_PROFILE', 'platform': 'ANY', 'displayClassId': 'DEFAULT'}],
        'placementTypes': [
            {'placementTypeId': 'APP_SCREENSHOT', 'acceptsAssetCategories': ['APP_SCREENSHOTS_AND_PREVIEWS'], 'specMappings': ([{'placementGroupId': groups[0], 'specs': ['outer']}, {'placementGroupId': groups[1], 'specs': ['inner']}] if split else [{'placementGroupId': groups[0], 'specs': ['outer', 'inner']}])},
            {'placementTypeId': 'PRODUCT_PAGE_HEADER_ASSET', 'acceptsAssetCategories': ['CREATIVE_ASSETS'], 'specMappings': [{'placementGroupId': 'DEFAULT_PROFILE', 'specs': ['header']}]},
        ],
        'imageSpecs': [{'specId': name, 'compatiblePlacementTypes': ['APP_SCREENSHOT'], 'dimensions': {'minWidth': width, 'maxWidth': width, 'minHeight': height, 'maxHeight': height}} for name, (width, height) in [('outer', u.DIMENSIONS['duo-outer']), ('inner', u.DIMENSIONS['duo-inner'])]],
        'videoSpecs': [{'specId': 'header', 'compatiblePlacementTypes': ['PRODUCT_PAGE_HEADER_ASSET'], 'dimensions': {'minWidth': 3840, 'maxWidth': 3840, 'minHeight': 1646, 'maxHeight': 1646}}],
    }
    legacy = [('iphone', 'IPHONE_DYNAMIC_ISLAND_MEDIUM_PROFILE', 'IPHONE_DYNAMIC_ISLAND_MEDIUM_DISPLAY', 'IPHONE_APP_STORE'), ('ipad', 'IPAD_13_PROFILE', 'IPAD_13_DISPLAY', 'IPAD_APP_STORE'), ('watch', 'WATCH_SERIES_10_PROFILE', 'WATCH_SERIES_10', 'WATCH_APP_STORE')]
    for profile, group, display_class, platform in legacy:
        width, height = u.DIMENSIONS[profile]
        attributes['placementProfileGroups'].append({'placementProfileGroupId': group, 'displayClassId': display_class, 'platform': platform})
        attributes['placementTypes'][0]['specMappings'].append({'placementGroupId': group, 'specs': [profile]})
        attributes['imageSpecs'].append({'specId': profile, 'compatiblePlacementTypes': ['APP_SCREENSHOT'], 'dimensions': {'minWidth': width, 'maxWidth': width, 'minHeight': height, 'maxHeight': height}})
    for feature in attributes['features']:
        feature['placementPolicies'][0]['groupLimits'].append({'groupIds': [group for profile, group, _, _ in legacy if profile != 'watch' or feature['featureId'] == 'APP_STORE_VERSIONS'], 'maxCount': 10})
    return [{'id': 'reference', 'attributes': attributes}]


def live_duo_reference(limit=10):
    reference = native_reference(duo_limit=limit)
    attributes = reference[0]['attributes']
    duo_specs = [
        {'specId': '205e7ab6-a23a-4ee2-b327-0a99ec2a2520', 'dimensions': {'minWidth': 1398, 'maxWidth': 1398, 'minHeight': 2034, 'maxHeight': 2034}, 'aspectRatio': '2:3', 'compatiblePlacementTypes': ['APP_SCREENSHOT', 'IMESSAGE_APP_SCREENSHOT']},
        {'specId': 'b83915b8-5b87-4e63-bba5-ab3a0c439862', 'dimensions': {'minWidth': 2853, 'maxWidth': 2853, 'minHeight': 2007, 'maxHeight': 2007}, 'aspectRatio': '3:2', 'compatiblePlacementTypes': ['APP_SCREENSHOT', 'IMESSAGE_APP_SCREENSHOT']},
    ]
    attributes['imageSpecs'] = [spec for spec in attributes['imageSpecs'] if spec['specId'] not in {'outer', 'inner'}] + duo_specs
    attributes['placementTypes'][0]['specMappings'][0]['specs'] = [spec['specId'] for spec in duo_specs]
    return reference


class FakeCLI:
    def __init__(self, state=None, apply=False):
        self.state, self.apply, self.calls = state or {}, apply, []
        self.command_mutations = []

    def api(self, method, path, body=None):
        self.calls.append((method, path, body))
        if method != 'GET':
            if not self.apply:
                raise AssertionError('Dry-run attempted mutation')
            if method == 'DELETE' and path.startswith('/v1/appScreenshots/'):
                for collection, assets in self.state.items():
                    if collection.endswith('/appScreenshots') and isinstance(assets, list):
                        assets[:] = [asset for asset in assets if asset['id'] != path.rsplit('/', 1)[1]]
                return {}
            if method == 'DELETE' and path.startswith('/v1/appAssetLibraryPlacements/'):
                for collection, assets in self.state.items():
                    if '/placements' in collection and isinstance(assets, list):
                        assets[:] = [asset for asset in assets if asset.get('id') != path.rsplit('/', 1)[1]]
                return {}
            if method == 'PATCH' and path.endswith('/relationships/appScreenshots'):
                self.state[path] = body['data']
                collection = path.replace('/relationships/appScreenshots', '/appScreenshots')
                by_id = {asset['id']: asset for asset in self.state[collection]}
                self.state[collection] = [by_id[asset['id']] for asset in body['data']]
            return {'data': {'id': 'created-' + str(len(self.calls))}}
        if path.endswith('/relationships/appScreenshots') and path not in self.state:
            return {'data': [{'type': 'appScreenshots', 'id': asset['id']} for asset in self.state.get(path.replace('/relationships/appScreenshots', '/appScreenshots'), [])]}
        return json.loads(json.dumps({'data': self.state.get(path, [])}))

    def run(self, args, body=None, mutate=False, cwd=None):
        if mutate and not self.apply:
            raise AssertionError('Dry-run attempted command mutation')
        self.calls.append(('COMMAND', args, body))
        self.command_mutations.append(mutate)
        if args[:2] == ['metadata', 'apply']:
            return {'appId': args[args.index('--app') + 1], 'appInfoId': args[args.index('--app-info') + 1], 'version': args[args.index('--version') + 1], 'versionId': 'version', 'adds': [], 'updates': [], 'deletes': []}
        default = args[:2] == ['screenshots', 'upload']
        if default or args[:5] == ['product-pages', 'custom-pages', 'localizations', 'screenshot-sets', 'upload']:
            allowed = {'--path', '--device-type', '--output', '--version-localization', '--skip-existing'} if default else {'--path', '--device-type', '--output', '--localization-id'}
            if any(value.startswith('--') and value not in allowed for value in args):
                raise AssertionError('Unsupported pinned screenshot upload flag')
            localization = args[args.index('--version-localization' if default else '--localization-id') + 1]
            kind = 'appStoreVersionLocalizations' if default else 'appCustomProductPageLocalizations'
            display = args[args.index('--device-type') + 1]
            sets = self.state.setdefault('/v1/' + kind + '/' + localization + '/appScreenshotSets', [])
            matching = [item for item in sets if item['attributes']['screenshotDisplayType'] == display]
            if not matching:
                matching = [row('set-' + str(len(self.calls)), screenshotDisplayType=display)]
                sets.extend(matching)
            set_id = matching[0]['id']
            actual = self.state.setdefault('/v1/appScreenshotSets/' + set_id + '/appScreenshots', [])
            staged = [(file.name, hashlib.md5(file.read_bytes()).hexdigest()) for file in sorted(Path(args[args.index('--path') + 1]).glob('*.png'))]
            self.staged_screenshots = staged
            for index, (_, checksum) in enumerate(staged):
                if '--skip-existing' not in args or not any(asset['attributes']['sourceFileChecksum'] == checksum for asset in actual):
                    actual.append(row('uploaded-%d-%d' % (len(self.calls), index), sourceFileChecksum=checksum, assetDeliveryState={'state': 'COMPLETE'}))
            if '--skip-existing' in args:
                order = {checksum: index for index, (_, checksum) in enumerate(staged)}
                actual.sort(key=lambda asset: order[asset['attributes']['sourceFileChecksum']])
            return {'setId': set_id, 'results': [{'assetId': asset['id']} for asset in actual]}
        return {'videoId': 'uploaded-video'}


class UploaderTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        self.addCleanup(self.tmp.cleanup)
        self.meta = {'appId': '6816213577', 'locales': {'en-US': {'name': 'Currency', 'description': 'Convert', 'promotionalText': 'Fast', 'contextualPromotionalText': {f: 'About ' + f for f in u.FAMILIES[1:]}}}}
        self.meta['duoPresentation'] = {family: ['duo-outer', 'duo-inner', 'duo-inner', 'duo-outer', 'duo-inner', 'duo-outer'] for family in u.FAMILIES}
        self.slots = {}
        for profile in u.PROFILES:
            for i in range(1, 7):
                file = self.root / (profile + str(i) + '.png')
                file.write_bytes((profile + str(i)).encode())
                self.slots[('en-US', profile, 'default', i)] = {'file': file}
        self.state = {
            '/v1/appAssetLibraryRefData': native_reference(),
            '/v1/apps/6816213577/appStoreVersions': [row('version', platform='IOS', versionString='1.2', appStoreState='PREPARE_FOR_SUBMISSION')],
            '/v1/apps/6816213577/appInfos': [row('info', appStoreState='PREPARE_FOR_SUBMISSION')],
            '/v1/appStoreVersions/version/appStoreVersionLocalizations': [row('locale', locale='en-US', description='Convert', promotionalText='Fast')],
            '/v1/appInfos/info/appInfoLocalizations': [row('info-locale', locale='en-US', name='Currency')],
        }

    def planner(self, cli, scopes, remove_approved_duplicate=None):
        return u.Planner(cli, self.meta, self.slots, {}, 'version', '1.2', 'info', scopes, remove_approved_duplicate=remove_approved_duplicate)

    def screenshot_assets(self, orders):
        return [row('shot-' + str(order), sourceFileChecksum=hashlib.md5(self.slots[('en-US', 'iphone', 'default', order)]['file'].read_bytes()).hexdigest(), assetDeliveryState={'state': 'COMPLETE'}) for order in orders]

    def cpp_screenshot_plan(self, cli, orders):
        for order in range(1, 7):
            self.slots[('en-US', 'iphone', 'travel', order)] = self.slots[('en-US', 'iphone', 'default', order)]
        self.state['/v1/appCustomProductPageLocalizations/locale/appScreenshotSets'] = [row('set', screenshotDisplayType='APP_IPHONE_61')]
        self.state['/v1/appScreenshotSets/set/appScreenshots'] = self.screenshot_assets(orders)
        self.state.pop('/v1/appScreenshotSets/set/relationships/appScreenshots', None)
        plan = self.planner(cli, {'cpp'})
        plan.screenshots('locale', 'travel', 'en-US', 'iphone')
        return plan

    def duplicate_screenshot_plan(self, cli, remove='redundant-copy', scopes=None):
        sets = []
        for profile, display in u.PROFILES.items():
            set_id = 'set' if profile == 'iphone' else 'set-' + profile
            sets.append(row(set_id, screenshotDisplayType=display))
            self.state['/v1/appScreenshotSets/' + set_id + '/appScreenshots'] = [dict(row(profile + '-' + str(order), sourceFileChecksum=hashlib.md5(self.slots[('en-US', profile, 'default', order)]['file'].read_bytes()).hexdigest(), fileSize=self.slots[('en-US', profile, 'default', order)]['file'].stat().st_size, assetDeliveryState={'state': 'COMPLETE'}), type='appScreenshots') for order in range(1, 7)]
        self.state['/v1/appStoreVersionLocalizations/locale/appScreenshotSets'] = sets
        assets = self.state['/v1/appScreenshotSets/set/appScreenshots']
        duplicate = json.loads(json.dumps(assets[0]))
        duplicate['id'] = 'redundant-copy'
        assets.append(duplicate)
        self.state['/v1/appScreenshotSets/set/relationships/appScreenshots'] = [{'type': 'appScreenshots', 'id': asset['id']} for asset in list(reversed(assets[:6])) + [duplicate]]
        direct = json.loads(json.dumps(duplicate))
        direct['relationships'] = {'appScreenshotSet': u.relationship('appScreenshotSets', 'set')}
        self.state['/v1/appScreenshots/redundant-copy?include=appScreenshotSet'] = direct
        self.state['/v1/appScreenshots/iphone-1?include=appScreenshotSet'] = dict(direct, id='iphone-1')
        return self.planner(cli, {'default'} if scopes is None else scopes, remove_approved_duplicate=remove)

    def test_canonical_metadata_exports_all_18_locales_and_selected_fields_only(self):
        metadata = json.loads((MODULE.parent / 'metadata.json').read_text())
        metadata['locales']['en-US']['privateTransportUrl'] = 'https://signed.invalid/PRIVATE_KEY'
        directory = self.root / 'canonical'
        directory.mkdir()
        u.write_canonical_metadata(directory, metadata, '1.0')
        paths = sorted(directory.rglob('*.json'))
        self.assertEqual(len(paths), 36)
        self.assertFalse(any(path.name == 'default.json' for path in paths))
        for locale, fields in metadata['locales'].items():
            info = json.loads((directory / 'app-info' / (locale + '.json')).read_text())
            version = json.loads((directory / 'version' / '1.0' / (locale + '.json')).read_text())
            self.assertEqual(info, {key: value for key, value in fields.items() if key in u.INFO_FIELDS})
            self.assertEqual(version, {key: value for key, value in fields.items() if key in u.VERSION_FIELDS})
            self.assertNotIn('locale', info)
            self.assertNotIn('contextualPromotionalText', version)
            self.assertEqual(info['privacyPolicyUrl'], fields['privacyPolicyUrl'])
            self.assertEqual(version['supportUrl'], fields['supportUrl'])
            self.assertEqual(version['marketingUrl'], fields['marketingUrl'])
        self.assertNotIn('PRIVATE_KEY', ''.join(path.read_text() for path in paths))

    def test_canonical_metadata_rejects_null_empty_and_default_fallback(self):
        for metadata in ({'locales': {'en-US': {'name': None}}}, {'locales': {'en-US': {'promotionalText': ''}}}, {'locales': {'default': {'name': 'Currency'}}}):
            with self.subTest(metadata=metadata):
                with self.assertRaises(u.UploadError):
                    u.write_canonical_metadata(self.root, metadata, '1.0')

    def test_metadata_cli_uses_exact_selectors_and_safe_dryrun_apply_protocol(self):
        class InspectCLI(FakeCLI):
            def run(self, args, body=None, mutate=False, cwd=None):
                directory = Path(args[args.index('--dir') + 1])
                self.snapshots.append((list(args), mutate, Path(cwd), {str(path.relative_to(directory)): json.loads(path.read_text()) for path in directory.rglob('*.json')}))
                return super().run(args, body, mutate, cwd)
        cli = InspectCLI(self.state, apply=True)
        cli.snapshots = []
        plan = self.planner(cli, {'metadata'})
        plan.sync_metadata(dry_run=True)
        plan.sync_metadata(dry_run=False)
        for index, (args, mutate, directory, files) in enumerate(cli.snapshots):
            self.assertEqual(args[:2], ['metadata', 'apply'])
            self.assertEqual(args[args.index('--app') + 1], '6816213577')
            self.assertEqual(args[args.index('--app-info') + 1], 'info')
            self.assertEqual(args[args.index('--version') + 1], '1.2')
            self.assertEqual(args[args.index('--platform') + 1], 'IOS')
            self.assertEqual(args[args.index('--include') + 1], 'localizations')
            self.assertEqual(args[args.index('--if-exists') + 1], 'update')
            self.assertEqual('--dry-run' in args, index == 0)
            self.assertEqual(mutate, index == 1)
            self.assertNotIn('--allow-deletes', args)
            self.assertNotIn('--confirm', args)
            self.assertEqual(set(files), {'app-info/en-US.json', 'version/1.2/en-US.json'})
            self.assertNotIn('supportUrl', files['version/1.2/en-US.json'])
            self.assertFalse(directory.exists())

    def test_metadata_sync_then_lookup_drives_new_default_screenshot_targets(self):
        self.meta['locales']['en-GB'] = dict(self.meta['locales']['en-US'])
        for profile in u.PROFILES:
            for index in range(1, 7):
                self.slots[('en-GB', profile, 'default', index)] = self.slots[('en-US', profile, 'default', index)]
        class CreatingCLI(FakeCLI):
            def run(self, args, body=None, mutate=False, cwd=None):
                result = super().run(args, body, mutate, cwd)
                if args[:2] == ['metadata', 'apply']:
                    result['adds'] = [{'key': 'version:1.2:en-GB:description', 'scope': 'version', 'version': '1.2', 'locale': 'en-GB', 'field': 'description', 'reason': 'field exists locally but not remotely', 'to': 'Convert'}]
                    if mutate:
                        self.state['/v1/appStoreVersions/version/appStoreVersionLocalizations'].append(row('gb-created', locale='en-GB'))
                return result
        cli = CreatingCLI(self.state, apply=True)
        plan = self.planner(cli, {'metadata', 'default'}).preflight()
        self.assertEqual([operation['method'] for operation in plan.ops[:2]], ['METADATA', 'LOOKUP'])
        self.assertFalse(any(cli.command_mutations))
        self.assertFalse(any(operation['method'] in {'POST', 'PATCH'} for operation in plan.ops))
        plan.execute()
        screenshot_commands = [call[1] for call in cli.calls if call[0] == 'COMMAND' and call[1][:2] == ['screenshots', 'upload']]
        self.assertEqual(len(screenshot_commands), 6)
        self.assertEqual(sum(command[command.index('--version-localization') + 1] == 'gb-created' for command in screenshot_commands), 3)
        self.assertTrue(all(call[0] in {'GET', 'COMMAND'} for call in cli.calls))
        metadata_commands = [call[1] for call in cli.calls if call[0] == 'COMMAND' and call[1][:2] == ['metadata', 'apply']]
        self.assertEqual(len(metadata_commands), 2)
        self.assertIn('--dry-run', metadata_commands[0])
        self.assertNotIn('--dry-run', metadata_commands[1])

    def test_metadata_plan_rejects_deletes_and_wrong_resolved_targets(self):
        for override in ({'deletes': [{'locale': 'fr-FR'}]}, {'versionId': 'another-version'}, {'appInfoId': 'another-info'}):
            with self.subTest(override=override):
                class InvalidCLI(FakeCLI):
                    def run(self, args, body=None, mutate=False, cwd=None):
                        result = super().run(args, body, mutate, cwd)
                        result.update(override)
                        return result
                cli = InvalidCLI(self.state, apply=True)
                plan = self.planner(cli, {'metadata'})
                with self.assertRaises(u.UploadError):
                    plan.preflight()
                self.assertEqual(plan.ops, [])
                self.assertFalse(any(cli.command_mutations))

    def test_missing_sparse_version_locale_requires_its_own_explicit_version_addition(self):
        self.meta['locales']['en-GB'] = {'name': 'Currency'}
        unrelated_update = {'scope': 'version', 'version': '1.2', 'locale': 'en-US', 'field': 'description'}
        for additions in (
            [],
            [{'scope': 'app-info', 'locale': 'en-GB', 'field': 'name'}],
            [{'locale': 'en-GB', 'version': '1.2', 'field': 'description'}],
            [{'scope': 'version', 'locale': 'en-GB', 'version': 'another-version', 'field': 'description'}],
            [{'scope': 'version', 'locale': 'en-AU', 'version': '1.2', 'field': 'description'}],
            [{'scope': 'version', 'locale': 'en-GB', 'version': '1.2', 'field': {'private': 'PRIVATE'}}],
        ):
            with self.subTest(additions=additions):
                class SparseCLI(FakeCLI):
                    def run(self, args, body=None, mutate=False, cwd=None):
                        result = super().run(args, body, mutate, cwd)
                        result.update(adds=additions, updates=[unrelated_update])
                        return result
                cli = SparseCLI(self.state, apply=True)
                with self.assertRaisesRegex(u.UploadError, 'did not plan the missing version locale'):
                    self.planner(cli, {'metadata'}).preflight()
                self.assertFalse(any(cli.command_mutations))
                self.assertTrue(all(call[0] in {'GET', 'COMMAND'} for call in cli.calls))

    def test_cpp_create_malformed_json_shapes_preserve_recovery_guidance(self):
        for response in (None, [], 'PRIVATE_RESPONSE', 7, {'data': None}, {'data': []}, {'data': 'PRIVATE_DATA'}):
            with self.subTest(response=response):
                cli = FakeCLI(self.state, apply=True)
                plan = self.planner(cli, {'cpp'})
                plan.queue('CPP_CREATE', '/v1/appCustomProductPages', name='Currency - travel')
                plan.queue('CPP_VERSION_LOOKUP', '/v1/appCustomProductPages/pending/appCustomProductPageVersions')
                with patch.object(cli, 'run', return_value=response) as command:
                    with self.assertRaisesRegex(u.UploadError, 'inspect draft state') as error:
                        plan.execute()
                self.assertEqual(command.call_count, 1)
                self.assertNotIn('PRIVATE', str(error.exception))
                self.assertTrue(all(call[0] == 'GET' for call in cli.calls))

    def test_recovery_lookups_reject_malformed_rows_and_attributes(self):
        for method in ('CPP_VERSION_LOOKUP', 'LOOKUP'):
            valid = row('valid', state='PREPARE_FOR_SUBMISSION') if method == 'CPP_VERSION_LOOKUP' else row('valid', locale='en-GB')
            malformed_rows = [None, 'PRIVATE_ROW', 7, {'id': 'unknown', 'attributes': None}, {'id': 'unknown', 'attributes': 'PRIVATE_ATTRIBUTES'}, {'id': 'unknown', 'attributes': []}]
            if method == 'CPP_VERSION_LOOKUP':
                malformed_rows.extend(row('unknown', state=value) for value in ({'private': 'PRIVATE_STATE'}, ['PRIVATE_STATE'], None))
            for malformed in malformed_rows:
                with self.subTest(method=method, malformed=malformed):
                    cli = FakeCLI({'/lookup': [valid, malformed]}, apply=True)
                    plan = self.planner(cli, set())
                    plan.queue(method, '/lookup', **({'locale': 'en-GB'} if method == 'LOOKUP' else {}))
                    with self.assertRaisesRegex(u.UploadError, 'inspect draft state') as error:
                        plan.execute()
                    self.assertNotIn('PRIVATE', str(error.exception))
                    self.assertTrue(all(call[0] == 'GET' for call in cli.calls))
            for response in (None, [], 'PRIVATE_RESPONSE'):
                cli = FakeCLI(self.state, apply=True)
                plan = self.planner(cli, set())
                plan.queue(method, '/lookup', **({'locale': 'en-GB'} if method == 'LOOKUP' else {}))
                with patch.object(cli, 'api', return_value=response):
                    with self.assertRaisesRegex(u.UploadError, 'inspect draft state') as error:
                        plan.execute()
                self.assertNotIn('PRIVATE', str(error.exception))

    def test_duplicate_candidate_malformed_api_envelope_preserves_recovery_guidance(self):
        for response in (None, [], 'PRIVATE_RESPONSE'):
            with self.subTest(response=response):
                cli = FakeCLI(self.state, apply=True)
                plan = self.duplicate_screenshot_plan(cli)
                original = cli.api
                def malformed(method, path, body=None):
                    return response if path.startswith('/v1/appScreenshots/') else original(method, path, body)
                with patch.object(cli, 'api', side_effect=malformed):
                    with self.assertRaisesRegex(u.UploadError, 'identity or parent does not match') as error:
                        plan.preflight()
                self.assertNotIn('PRIVATE', str(error.exception))
                self.assertTrue(all(call[0] == 'GET' for call in cli.calls))

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

    def test_apply_reuses_version_locale_that_appears_after_preflight(self):
        cli = FakeCLI(self.state, apply=True)
        plan = self.planner(cli, {'default'})
        target = plan.queue('POST', '/v1/appStoreVersionLocalizations', u.resource('appStoreVersionLocalizations', {'locale': 'en-GB', 'description': 'Approved description'}, {'appStoreVersion': u.relationship('appStoreVersions', 'version')}))
        plan.queue('PATCH', '/v1/appStoreVersionLocalizations/' + target, u.resource('appStoreVersionLocalizations', {'keywords': 'widget'}, identifier=target))
        cli.state['/v1/appStoreVersions/version/appStoreVersionLocalizations'] = [row('automatic-locale', locale='en-GB')]
        plan.execute()
        writes = [call for call in cli.calls if call[0] != 'GET']
        self.assertEqual([call[0] for call in writes], ['PATCH', 'PATCH'])
        self.assertEqual(writes[0][1], '/v1/appStoreVersionLocalizations/automatic-locale')
        self.assertEqual(writes[0][2]['data']['attributes'], {'description': 'Approved description'})
        self.assertEqual(writes[1][1], '/v1/appStoreVersionLocalizations/automatic-locale')

    def test_localization_refresh_preserves_unselected_fields_and_rejects_duplicates(self):
        for path, relation, parent_kind in (
            ('appStoreVersionLocalizations', 'appStoreVersion', 'appStoreVersions'),
            ('appCustomProductPageLocalizations', 'appCustomProductPageVersion', 'appCustomProductPageVersions'),
        ):
            with self.subTest(path=path):
                collection = '/v1/' + parent_kind + '/parent/' + path
                cli = FakeCLI({collection: [row('automatic', locale='en-GB', promotionalText='Keep current text')]}, apply=True)
                plan = self.planner(cli, set())
                body = u.resource(path, {'locale': 'en-GB'}, {relation: u.relationship(parent_kind, 'parent')})
                self.assertEqual(plan.apply_resource('POST', '/v1/' + path, body)['data']['id'], 'automatic')
                self.assertTrue(all(call[0] == 'GET' for call in cli.calls))
                cli.state[collection].append(row('duplicate', locale='en-GB'))
                with self.assertRaisesRegex(u.UploadError, 'duplicates'):
                    plan.apply_resource('POST', '/v1/' + path, body)
                self.assertTrue(all(call[0] == 'GET' for call in cli.calls))

    def test_localization_refresh_rejects_malformed_envelopes_and_mixed_attributes(self):
        for kind, relation, parent_kind in (
            ('appStoreVersionLocalizations', 'appStoreVersion', 'appStoreVersions'),
            ('appCustomProductPageLocalizations', 'appCustomProductPageVersion', 'appCustomProductPageVersions'),
        ):
            matching = row('existing', locale='en-GB', promotionalText='Keep')
            responses = [None, [], 'PRIVATE_RESPONSE', {'data': None}, {'data': 'PRIVATE_DATA'}]
            responses.extend({'data': [matching, malformed]} for malformed in (None, 'PRIVATE_ROW', {'id': 'unknown', 'attributes': None}, {'id': 'unknown', 'attributes': []}, {'id': 'unknown', 'attributes': 'PRIVATE_ATTRIBUTES'}))
            for response in responses:
                with self.subTest(kind=kind, response=response):
                    cli = FakeCLI(self.state, apply=True)
                    plan = self.planner(cli, set())
                    body = u.resource(kind, {'locale': 'en-GB', 'promotionalText': 'Approved'}, {relation: u.relationship(parent_kind, 'parent')})
                    with patch.object(cli, 'api', return_value=response) as api:
                        with self.assertRaisesRegex(u.UploadError, 'invalid collection; inspect draft state') as error:
                            plan.apply_resource('POST', '/v1/' + kind, body)
                    api.assert_called_once_with('GET', '/v1/' + parent_kind + '/parent/' + kind)
                    self.assertNotIn('PRIVATE', str(error.exception))

    def test_localization_refresh_preserves_empty_and_omitted_attributes(self):
        collection = '/v1/appStoreVersions/parent/appStoreVersionLocalizations'
        for sparse in ({'id': 'sparse', 'attributes': {}}, {'id': 'sparse'}):
            cli = FakeCLI({collection: [sparse, row('existing', locale='en-GB')]}, apply=True)
            plan = self.planner(cli, set())
            body = u.resource('appStoreVersionLocalizations', {'locale': 'en-GB'}, {'appStoreVersion': u.relationship('appStoreVersions', 'parent')})
            self.assertEqual(plan.apply_resource('POST', '/v1/appStoreVersionLocalizations', body)['data']['id'], 'existing')
            self.assertTrue(all(call[0] == 'GET' for call in cli.calls))

    def test_read_boundary_rejects_malformed_rows_and_preserves_resource_and_linkage_shapes(self):
        cli = FakeCLI(self.state)
        plan = self.planner(cli, set())
        for value in (None, 'PRIVATE_DATA', [None], [{'id': 'valid'}, 'PRIVATE_ROW'], [{'attributes': None}], [{'attributes': []}], [{'attributes': 'PRIVATE_ATTRIBUTES'}]):
            with self.subTest(value=value), patch.object(cli, 'api', return_value={'data': value}):
                with self.assertRaisesRegex(u.UploadError, 'invalid collection; inspect draft state') as error:
                    plan.get('/read')
                self.assertNotIn('PRIVATE', str(error.exception))
        for value in ([], {'id': 'single'}, [{'type': 'appScreenshots', 'id': 'linkage'}], [{'id': 'sparse', 'attributes': {}}], [{'attributes': {'futureField': None}}]):
            with self.subTest(value=value), patch.object(cli, 'api', return_value={'data': value}):
                self.assertEqual(plan.get('/read'), value if isinstance(value, list) else [value])

    def test_screenshot_set_and_asset_reads_reject_malformed_rows_before_mutation(self):
        for malformed in (None, 'PRIVATE_ROW', {'id': 'bad', 'attributes': None}, {'id': 'bad', 'attributes': []}):
            for collection in ('sets', 'assets'):
                with self.subTest(collection=collection, malformed=malformed):
                    self.state['/v1/appStoreVersionLocalizations/locale/appScreenshotSets'] = [row('set', screenshotDisplayType='APP_IPHONE_61')]
                    self.state['/v1/appScreenshotSets/set/appScreenshots'] = self.screenshot_assets([1])
                    path = '/v1/appStoreVersionLocalizations/locale/appScreenshotSets' if collection == 'sets' else '/v1/appScreenshotSets/set/appScreenshots'
                    self.state[path].append(malformed)
                    cli = FakeCLI(self.state, apply=True)
                    with self.assertRaisesRegex(u.UploadError, 'invalid collection; inspect draft state'):
                        self.planner(cli, {'default'}).screenshots('locale', 'default', 'en-US', 'iphone')
                    self.assertTrue(all(call[0] == 'GET' for call in cli.calls))

    def test_malformed_set_or_asset_read_after_delete_or_upload_stops_later_mutations(self):
        for phase in ('delete', 'upload'):
            for collection in ('sets', 'assets'):
                for malformed in (None, {'id': 'bad', 'attributes': None}, {'id': 'bad', 'attributes': []}):
                    with self.subTest(phase=phase, collection=collection, malformed=malformed):
                        cli = FakeCLI(self.state, apply=True)
                        plan = self.duplicate_screenshot_plan(cli).preflight() if phase == 'delete' else self.cpp_screenshot_plan(cli, [3])
                        parent = 'appStoreVersionLocalizations' if phase == 'delete' else 'appCustomProductPageLocalizations'
                        bad_path = '/v1/' + parent + '/locale/appScreenshotSets' if collection == 'sets' else '/v1/appScreenshotSets/set/appScreenshots'
                        active = {'mutated': False}
                        original_api, original_run = cli.api, cli.run
                        def api(method, path, body=None):
                            result = original_api(method, path, body)
                            if method == 'DELETE':
                                active['mutated'] = True
                            elif active['mutated'] and method == 'GET' and path == bad_path:
                                result['data'].append(malformed)
                            return result
                        def upload(args, body=None, mutate=False, cwd=None):
                            result = original_run(args, body, mutate, cwd)
                            active['mutated'] = True
                            return result
                        with patch.object(cli, 'api', side_effect=api), patch.object(cli, 'run', side_effect=upload):
                            with self.assertRaisesRegex(u.UploadError, 'invalid collection; inspect draft state'):
                                plan.execute()
                        self.assertEqual([call[0] for call in cli.calls if call[0] != 'GET'], ['DELETE' if phase == 'delete' else 'COMMAND'])

    def test_cpp_jit_discovery_malformed_attributes_stop_after_prior_mutation(self):
        cli = FakeCLI(self.state, apply=True)
        self.state['/v1/apps/6816213577/appCustomProductPages'] = [row('valid', name='Other'), {'id': 'bad', 'attributes': None}]
        plan = self.planner(cli, {'cpp'})
        plan.queue('POST', '/v1/appAssetLibraryPlacementOrderingRequests', u.resource('appAssetLibraryPlacementOrderingRequests', {}))
        plan.queue('CPP_CREATE', '/v1/appCustomProductPages', name='Currency - travel')
        with patch.object(sys, 'stdout', new=io.StringIO()):
            with self.assertRaisesRegex(u.UploadError, 'invalid collection; inspect draft state'):
                plan.execute()
        self.assertEqual([call[0] for call in cli.calls if call[0] != 'GET'], ['POST'])

    def test_complete_matching_screenshots_are_idempotent(self):
        sets = []
        for profile, display in u.PROFILES.items():
            sets.append(row(profile, screenshotDisplayType=display))
            self.state['/v1/appScreenshotSets/' + profile + '/appScreenshots'] = [row(str(i), sourceFileChecksum=hashlib.md5(self.slots[('en-US', profile, 'default', i)]['file'].read_bytes()).hexdigest(), assetDeliveryState={'state': 'COMPLETE'}) for i in range(1, 7)]
        self.state['/v1/appStoreVersionLocalizations/locale/appScreenshotSets'] = sets
        plan = self.planner(FakeCLI(self.state), {'default'}).preflight()
        self.assertEqual(plan.ops, [])

    def test_explicit_duplicate_repair_has_readonly_proof_then_one_delete_and_verified_order(self):
        cli = FakeCLI(self.state)
        receipts = []
        cli.receipt = lambda event, result=None: receipts.append((event, result))
        plan = self.duplicate_screenshot_plan(cli).preflight()
        self.assertEqual([operation['method'] for operation in plan.ops], ['DELETE_APPROVED_DUPLICATE', 'SCREENSHOTS'])
        summary = plan.summary()[0]
        self.assertEqual({key: summary[key] for key in ('removeId', 'keepId', 'setId', 'family', 'locale', 'profile')}, {'removeId': 'redundant-copy', 'keepId': 'iphone-1', 'setId': 'set', 'family': 'default', 'locale': 'en-US', 'profile': 'iphone'})
        self.assertEqual(summary['bytes'], self.slots[('en-US', 'iphone', 'default', 1)]['file'].stat().st_size)
        self.assertEqual(summary['checksum'], hashlib.md5(self.slots[('en-US', 'iphone', 'default', 1)]['file'].read_bytes()).hexdigest())
        self.assertTrue(all(call[0] == 'GET' for call in cli.calls))
        with self.assertRaisesRegex(u.UploadError, 'Apply mode'):
            plan.execute()
        cli.apply = True
        with patch.object(sys, 'stdout', new=io.StringIO()):
            plan.execute()
        writes = [call for call in cli.calls if call[0] != 'GET']
        self.assertEqual([call[0] for call in writes], ['DELETE', 'PATCH'])
        self.assertEqual(writes[0], ('DELETE', '/v1/appScreenshots/redundant-copy', None))
        self.assertEqual(writes[1][2], {'data': [{'type': 'appScreenshots', 'id': 'iphone-' + str(order)} for order in range(1, 7)]})
        self.assertEqual([asset['id'] for asset in self.state['/v1/appScreenshotSets/set/appScreenshots']], ['iphone-' + str(order) for order in range(1, 7)])
        self.assertEqual(cli.calls[-1][1], '/v1/appScreenshotSets/set/relationships/appScreenshots')
        verified = next(result for event, result in receipts if event == 'approved-duplicate-delete-verified')
        self.assertEqual(verified['screenshotId'], 'redundant-copy')
        self.assertEqual({item['assetId'] for item in verified['retained']}, {'iphone-' + str(order) for order in range(1, 7)})

    def test_stale_canonical_read_after_verified_duplicate_removal_stops_with_snapshot_diagnostics(self):
        class LaggingCLI(FakeCLI):
            removed = False
            reads_after_delete = 0
            def api(self, method, path, body=None):
                if method == 'DELETE':
                    self.before_delete = json.loads(json.dumps(self.state['/v1/appScreenshotSets/set/relationships/appScreenshots']))
                result = super().api(method, path, body)
                if method == 'DELETE':
                    self.removed = True
                elif self.removed and method == 'GET' and path == '/v1/appScreenshotSets/set/relationships/appScreenshots':
                    self.reads_after_delete += 1
                    if self.reads_after_delete == 2:
                        return {'data': json.loads(json.dumps(self.before_delete))}
                return result
        cli = LaggingCLI(self.state, apply=True)
        events = []
        cli.receipt = lambda event, result=None: events.append(event)
        plan = self.duplicate_screenshot_plan(cli).preflight()
        snapshot = plan.get('/v1/appScreenshotSets/set/appScreenshots')
        with patch.object(sys, 'stdout', new=io.StringIO()):
            with self.assertRaisesRegex(u.UploadError, 'membership changed') as error:
                plan.execute()
        diagnostic = json.loads(str(error.exception).split('screenshotConflict=', 1)[1])
        self.assertEqual((diagnostic['assetCount'], diagnostic['uniqueIdCount'], diagnostic['completeCount']), (6, 6, 6))
        self.assertEqual((diagnostic['orderedLinkages']['rowCount'], diagnostic['orderedLinkages']['uniqueIdCount']), (7, 7))
        self.assertIn('redundant-copy', [asset['id'] for asset in diagnostic['orderedLinkages']['assets']])
        self.assertNotIn('redundant-copy', [asset['id'] for asset in diagnostic['assets']])
        self.assertEqual(len(snapshot), 7)
        self.assertEqual(len(self.state['/v1/appScreenshotSets/set/appScreenshots']), 6)
        self.assertEqual(cli.reads_after_delete, 2)
        self.assertIn('operation-1-completed', events)
        self.assertNotIn('operation-2-completed', events)
        self.assertEqual([call[0] for call in cli.calls if call[0] != 'GET'], ['DELETE'])

    def test_explicit_duplicate_repair_supports_selected_cpp_gallery(self):
        cli = FakeCLI(self.state, apply=True)
        plan = self.duplicate_screenshot_plan(cli, scopes={'cpp'})
        for order in range(1, 7):
            self.slots[('en-US', 'iphone', 'travel', order)] = self.slots[('en-US', 'iphone', 'default', order)]
        plan.cpp_profiles = ['iphone', 'ipad']
        self.state['/v1/appCustomProductPageLocalizations/locale/appScreenshotSets'] = [row('set', screenshotDisplayType='APP_IPHONE_61')]
        plan.screenshots('locale', 'travel', 'en-US', 'iphone')
        self.assertEqual(plan.summary()[0]['family'], 'travel')
        with patch.object(sys, 'stdout', new=io.StringIO()):
            plan.execute()
        self.assertEqual(sum(call[0] == 'DELETE' for call in cli.calls), 1)
        self.assertFalse(any(call[0] == 'COMMAND' for call in cli.calls))

    def test_explicit_duplicate_id_in_multiple_galleries_refuses_before_mutations(self):
        cli = FakeCLI(self.state, apply=True)
        plan = self.duplicate_screenshot_plan(cli)
        self.state['/v1/appScreenshotSets/set-ipad/appScreenshots'].append(dict(self.state['/v1/appScreenshotSets/set/appScreenshots'][-1]))
        with self.assertRaisesRegex(u.UploadError, 'multiple galleries'):
            plan.preflight()
        self.assertTrue(all(call[0] == 'GET' for call in cli.calls))

    def test_duplicate_repair_requires_explicit_id_and_full_approved_proof(self):
        for case in ('no-flag', 'absent', 'first-copy', 'nonduplicate', 'partial', 'foreign', 'failed-target', 'failed-keep', 'size-target', 'size-keep', 'wrong-parent', 'missing-parent', 'wrong-direct-id', 'wrong-direct-type', 'wrong-resource-type', 'unknown-checksum', 'canonical-missing', 'canonical-foreign', 'scope'):
            with self.subTest(case=case):
                cli = FakeCLI(self.state, apply=True)
                remove = None if case == 'no-flag' else 'missing' if case == 'absent' else 'iphone-1' if case == 'first-copy' else 'iphone-2' if case == 'nonduplicate' else 'redundant-copy'
                plan = self.duplicate_screenshot_plan(cli, remove=remove, scopes={'metadata'} if case == 'scope' else None)
                assets = self.state['/v1/appScreenshotSets/set/appScreenshots']
                direct = self.state['/v1/appScreenshots/redundant-copy?include=appScreenshotSet']
                if case == 'partial':
                    assets.pop(2)
                elif case == 'foreign':
                    assets[2]['attributes']['sourceFileChecksum'] = 'f' * 32
                elif case.startswith('failed-'):
                    assets[-1 if case == 'failed-target' else 0]['attributes']['assetDeliveryState']['state'] = 'FAILED'
                elif case.startswith('size-'):
                    assets[-1 if case == 'size-target' else 0]['attributes']['fileSize'] += 1
                elif case == 'wrong-parent':
                    direct['relationships']['appScreenshotSet']['data']['id'] = 'foreign-set'
                elif case == 'missing-parent':
                    direct['relationships'] = None
                elif case == 'wrong-direct-id':
                    direct['id'] = 'foreign-id'
                elif case == 'wrong-direct-type':
                    direct['type'] = 'appAssetLibraryImages'
                elif case == 'wrong-resource-type':
                    assets[2]['type'] = 'appAssetLibraryImages'
                elif case == 'unknown-checksum':
                    assets[-1]['attributes']['sourceFileChecksum'] = None
                elif case == 'canonical-missing':
                    self.state['/v1/appScreenshotSets/set/relationships/appScreenshots'].pop()
                elif case == 'canonical-foreign':
                    self.state['/v1/appScreenshotSets/set/relationships/appScreenshots'][0]['id'] = 'foreign'
                with self.assertRaises(u.UploadError):
                    plan.preflight()
                self.assertTrue(all(call[0] in {'GET', 'COMMAND'} for call in cli.calls))
                self.assertFalse(any(cli.command_mutations))

    def test_duplicate_repair_revalidates_proof_before_any_mutation(self):
        for race in ('extra', 'missing', 'changed-keep-id', 'failed', 'size', 'parent', 'order'):
            with self.subTest(race=race):
                cli = FakeCLI(self.state, apply=True)
                plan = self.duplicate_screenshot_plan(cli).preflight()
                assets = self.state['/v1/appScreenshotSets/set/appScreenshots']
                if race == 'extra':
                    assets.append(dict(assets[2], id='unexpected'))
                elif race == 'missing':
                    assets.pop()
                elif race == 'changed-keep-id':
                    assets[0]['id'] = 'changed-keep'
                elif race == 'failed':
                    assets[-1]['attributes']['assetDeliveryState']['state'] = 'FAILED'
                elif race == 'size':
                    assets[-1]['attributes']['fileSize'] += 1
                elif race == 'parent':
                    self.state['/v1/appScreenshots/redundant-copy?include=appScreenshotSet']['relationships']['appScreenshotSet']['data']['id'] = 'foreign'
                else:
                    ordered = self.state['/v1/appScreenshotSets/set/relationships/appScreenshots']
                    ordered[0], ordered[1] = ordered[1], ordered[0]
                cli.calls.clear()
                with self.assertRaises(u.UploadError):
                    plan.execute()
                self.assertTrue(all(call[0] == 'GET' for call in cli.calls))

    def test_duplicate_repair_ambiguous_delete_failure_stops_without_retry_or_reordering(self):
        for removed in (False, True):
            with self.subTest(removed=removed):
                cli = FakeCLI(self.state, apply=True)
                plan = self.duplicate_screenshot_plan(cli).preflight()
                original = cli.api
                attempts = []
                def failing(method, path, body=None):
                    if method == 'DELETE':
                        attempts.append(path)
                        if removed:
                            original(method, path, body)
                        raise u.UploadError('asc command failed; inspect state')
                    return original(method, path, body)
                with patch.object(cli, 'api', side_effect=failing):
                    with self.assertRaises(u.UploadError):
                        plan.execute()
                self.assertEqual(attempts, ['/v1/appScreenshots/redundant-copy'])
                self.assertFalse(any(call[0] in {'PATCH', 'POST', 'COMMAND'} for call in cli.calls))

    def test_duplicate_repair_requires_all_six_retained_identities_after_delete(self):
        cli = FakeCLI(self.state, apply=True)
        plan = self.duplicate_screenshot_plan(cli).preflight()
        original = cli.api
        def changed(method, path, body=None):
            result = original(method, path, body)
            if method == 'DELETE':
                self.state['/v1/appScreenshotSets/set/appScreenshots'][0]['id'] = 'replacement'
            return result
        with patch.object(cli, 'api', side_effect=changed):
            with self.assertRaisesRegex(u.UploadError, 'preserve every retained'):
                plan.execute()
        self.assertEqual(sum(call[0] == 'DELETE' for call in cli.calls), 1)
        self.assertFalse(any(call[0] in {'PATCH', 'POST', 'COMMAND'} for call in cli.calls))

    def test_duplicate_repair_rejects_invalid_explicit_id(self):
        with self.assertRaisesRegex(u.UploadError, 'ID is invalid'):
            self.planner(FakeCLI(self.state), {'default'}, remove_approved_duplicate='https://private.invalid/PRIVATE')

    def test_screenshot_preflight_uses_canonical_order_and_membership(self):
        for family in ('default', 'travel'):
            for case in ('ordered', 'reversed', 'collection-reversed', 'foreign', 'missing', 'duplicate', 'wrong-type'):
                with self.subTest(family=family, case=case):
                    for order in range(1, 7):
                        self.slots[('en-US', 'iphone', family, order)] = self.slots[('en-US', 'iphone', 'default', order)]
                    kind = 'appStoreVersionLocalizations' if family == 'default' else 'appCustomProductPageLocalizations'
                    self.state['/v1/' + kind + '/locale/appScreenshotSets'] = [row('set', screenshotDisplayType='APP_IPHONE_61')]
                    assets = self.screenshot_assets(range(1, 7))
                    self.state['/v1/appScreenshotSets/set/appScreenshots'] = list(reversed(assets)) if case == 'collection-reversed' else assets
                    ordered = [{'type': 'appScreenshots', 'id': asset['id']} for asset in assets]
                    current = [dict(item) for item in ordered]
                    if case == 'reversed':
                        current.reverse()
                    elif case == 'foreign':
                        current[0]['id'] = 'foreign'
                    elif case == 'missing':
                        current.pop()
                    elif case == 'duplicate':
                        current[0]['id'] = current[1]['id']
                    elif case == 'wrong-type':
                        current[0]['type'] = 'appAssetLibraryPlacements'
                    self.state['/v1/appScreenshotSets/set/relationships/appScreenshots'] = current
                    cli = FakeCLI(self.state, apply=True)
                    plan = self.planner(cli, {'default'})
                    if case in {'foreign', 'missing', 'duplicate', 'wrong-type'}:
                        with self.assertRaisesRegex(u.UploadError, 'membership changed'):
                            plan.screenshots('locale', family, 'en-US', 'iphone')
                        self.assertTrue(all(call[0] == 'GET' for call in cli.calls))
                        self.assertEqual(plan.ops, [])
                    else:
                        plan.screenshots('locale', family, 'en-US', 'iphone')
                        self.assertEqual(len(plan.ops), 1 if case == 'reversed' else 0)
                        if plan.ops:
                            with patch.object(sys, 'stdout', new=io.StringIO()):
                                plan.execute()
                            self.assertFalse(any(call[0] == 'COMMAND' for call in cli.calls))
                            patches = [call for call in cli.calls if call[0] == 'PATCH']
                            self.assertEqual(len(patches), 1)
                            self.assertEqual(patches[0][2], {'data': ordered})
                            self.assertEqual(self.state['/v1/appScreenshotSets/set/relationships/appScreenshots'], ordered)

    def test_screenshot_execution_rechecks_canonical_membership_before_upload(self):
        cli = FakeCLI(self.state, apply=True)
        plan = self.cpp_screenshot_plan(cli, [3])
        self.state['/v1/appScreenshotSets/set/relationships/appScreenshots'] = [{'type': 'appScreenshots', 'id': 'foreign'}]
        with self.assertRaisesRegex(u.UploadError, 'membership changed'):
            plan.execute()
        self.assertTrue(all(call[0] == 'GET' for call in cli.calls))

    def test_screenshot_order_patch_acknowledgment_requires_saved_order_readback(self):
        class UnsavedCLI(FakeCLI):
            def api(self, method, path, body=None):
                if method == 'PATCH':
                    self.calls.append((method, path, body))
                    return {}
                return super().api(method, path, body)
        cli = UnsavedCLI(self.state, apply=True)
        plan = self.cpp_screenshot_plan(cli, [6, 5, 4, 3, 2, 1])
        with self.assertRaisesRegex(u.UploadError, 'order was not saved'):
            plan.execute()
        self.assertFalse(any(call[0] == 'COMMAND' for call in cli.calls))
        self.assertEqual(sum(call[0] == 'PATCH' for call in cli.calls), 1)
        self.assertEqual(cli.calls[-1], ('GET', '/v1/appScreenshotSets/set/relationships/appScreenshots', None))

    def test_approved_partial_or_unordered_screenshots_resume_in_full_approved_order(self):
        for family in ('default', 'travel'):
            for orders in ([1, 3, 5], [6, 2], [4, 3, 2, 1, 5, 6]):
                with self.subTest(family=family, orders=orders):
                    for order in range(1, 7):
                        self.slots[('en-US', 'iphone', family, order)] = self.slots[('en-US', 'iphone', 'default', order)]
                    kind = 'appStoreVersionLocalizations' if family == 'default' else 'appCustomProductPageLocalizations'
                    self.state['/v1/' + kind + '/locale/appScreenshotSets'] = [row('set', screenshotDisplayType='APP_IPHONE_61')]
                    self.state['/v1/appScreenshotSets/set/appScreenshots'] = [row('shot-' + str(order), sourceFileChecksum=hashlib.md5(self.slots[('en-US', 'iphone', family, order)]['file'].read_bytes()).hexdigest(), assetDeliveryState={'state': 'COMPLETE'}) for order in orders]
                    self.state.pop('/v1/appScreenshotSets/set/relationships/appScreenshots', None)
                    cli = FakeCLI(self.state, apply=True)
                    plan = self.planner(cli, {'default'})
                    plan.screenshots('locale', family, 'en-US', 'iphone')
                    self.assertEqual(len(plan.ops), 1)
                    self.assertTrue(plan.ops[0]['skip_existing'])
                    self.assertEqual(plan.ops[0]['files'], [str(self.slots[('en-US', 'iphone', family, order)]['file']) for order in range(1, 7)])
                    self.assertTrue(plan.summary()[0]['resumeExisting'])
                    with patch.object(sys, 'stdout', new=io.StringIO()):
                        plan.execute()
                    commands = [call[1] for call in cli.calls if call[0] == 'COMMAND']
                    self.assertEqual(len(commands), 0 if family != 'default' and len(orders) == 6 else 1)
                    for command in commands:
                        self.assertEqual('--skip-existing' in command, family == 'default')
                        self.assertNotIn('--replace', command)
                        self.assertNotIn('--confirm', command)
                        self.assertEqual(command[:2], ['screenshots', 'upload'] if family == 'default' else ['product-pages', 'custom-pages'])
                    if commands:
                        selected = range(1, 7) if family == 'default' else [order for order in range(1, 7) if order not in orders]
                        self.assertEqual(cli.staged_screenshots, [('%02d.png' % order, hashlib.md5(self.slots[('en-US', 'iphone', family, order)]['file'].read_bytes()).hexdigest()) for order in selected])
                    if family != 'default':
                        ordering = [call for call in cli.calls if call[0] == 'PATCH']
                        self.assertEqual(len(ordering), 1)
                        self.assertEqual(ordering[0][1], '/v1/appScreenshotSets/set/relationships/appScreenshots')
                        self.assertEqual([item['id'] for item in ordering[0][2]['data']], [asset['id'] for asset in self.state['/v1/appScreenshotSets/set/appScreenshots']])

    def test_fresh_screenshots_do_not_enable_skip_existing(self):
        for existing_set in (False, True):
            with self.subTest(existing_set=existing_set):
                self.state['/v1/appStoreVersionLocalizations/locale/appScreenshotSets'] = [row('set', screenshotDisplayType='APP_IPHONE_61')] if existing_set else []
                cli = FakeCLI(self.state, apply=True)
                plan = self.planner(cli, {'default'})
                plan.screenshots('locale', 'default', 'en-US', 'iphone')
                self.assertFalse(plan.ops[0]['skip_existing'])
                self.assertFalse(plan.summary()[0]['resumeExisting'])
                with patch.object(sys, 'stdout', new=io.StringIO()):
                    plan.execute()
                command = next(call[1] for call in cli.calls if call[0] == 'COMMAND')
                self.assertNotIn('--skip-existing', command)

    def test_screenshot_execution_rechecks_fresh_plans_before_upload(self):
        for family in ('default', 'travel'):
            for race in ('approved-subset', 'approved-full', 'foreign', 'duplicate', 'failed', 'duplicate-sets'):
                with self.subTest(family=family, race=race):
                    for order in range(1, 7):
                        self.slots[('en-US', 'iphone', family, order)] = self.slots[('en-US', 'iphone', 'default', order)]
                    kind = 'appStoreVersionLocalizations' if family == 'default' else 'appCustomProductPageLocalizations'
                    collection = '/v1/' + kind + '/locale/appScreenshotSets'
                    self.state[collection] = []
                    self.state.pop('/v1/appScreenshotSets/set/relationships/appScreenshots', None)
                    cli = FakeCLI(self.state, apply=True)
                    plan = self.planner(cli, {family})
                    plan.screenshots('locale', family, 'en-US', 'iphone')
                    self.assertFalse(plan.ops[0]['skip_existing'])
                    self.state[collection] = [row('set', screenshotDisplayType='APP_IPHONE_61')]
                    assets = self.screenshot_assets(range(1, 7) if race == 'approved-full' else [1, 3])
                    if race == 'foreign':
                        assets[0]['attributes']['sourceFileChecksum'] = 'f' * 32
                    elif race == 'duplicate':
                        assets.append(dict(assets[0], id='duplicate'))
                    elif race == 'failed':
                        assets[0]['attributes']['assetDeliveryState']['state'] = 'FAILED'
                    elif race == 'duplicate-sets':
                        self.state[collection].append(row('duplicate-set', screenshotDisplayType='APP_IPHONE_61'))
                    self.state['/v1/appScreenshotSets/set/appScreenshots'] = assets
                    if race.startswith('approved'):
                        with patch.object(sys, 'stdout', new=io.StringIO()):
                            plan.execute()
                        commands = [call[1] for call in cli.calls if call[0] == 'COMMAND']
                        self.assertEqual(len(commands), 0 if race == 'approved-full' else 1)
                        if commands:
                            self.assertEqual('--skip-existing' in commands[0], family == 'default')
                            self.assertEqual([name for name, _ in cli.staged_screenshots], ['%02d.png' % order for order in (range(1, 7) if family == 'default' else [2, 4, 5, 6])])
                    else:
                        with self.assertRaises(u.UploadError):
                            plan.execute()
                        self.assertTrue(all(call[0] == 'GET' for call in cli.calls))

    def test_cpp_resume_refuses_changed_set_identity_before_upload(self):
        cli = FakeCLI(self.state, apply=True)
        plan = self.cpp_screenshot_plan(cli, [1])
        self.state['/v1/appCustomProductPageLocalizations/locale/appScreenshotSets'] = [row('replacement', screenshotDisplayType='APP_IPHONE_61')]
        with self.assertRaisesRegex(u.UploadError, 'identity changed'):
            plan.execute()
        self.assertTrue(all(call[0] == 'GET' for call in cli.calls))

    def test_cpp_resume_requires_complete_approved_assets_and_exact_relationship_membership_after_upload(self):
        for race in ('foreign', 'duplicate', 'failed', 'missing', 'changed-existing-id', 'foreign-relationship', 'duplicate-relationship', 'wrong-relationship-type'):
            with self.subTest(race=race):
                cli = FakeCLI(self.state, apply=True)
                plan = self.cpp_screenshot_plan(cli, [3])
                self.state.pop('/v1/appScreenshotSets/set/relationships/appScreenshots', None)
                upload = cli.run
                def changed(args, body=None, mutate=False, cwd=None):
                    result = upload(args, body, mutate, cwd)
                    assets = self.state['/v1/appScreenshotSets/set/appScreenshots']
                    if race == 'foreign':
                        assets[1]['attributes']['sourceFileChecksum'] = 'f' * 32
                    elif race == 'duplicate':
                        assets.append(dict(assets[1], id='duplicate'))
                    elif race == 'failed':
                        assets[1]['attributes']['assetDeliveryState']['state'] = 'FAILED'
                    elif race == 'missing':
                        assets.pop()
                    elif race == 'changed-existing-id':
                        assets[0]['id'] = 'replacement'
                    else:
                        relations = [{'type': 'appScreenshots', 'id': asset['id']} for asset in assets]
                        if race == 'foreign-relationship':
                            relations[0]['id'] = 'foreign'
                        elif race == 'duplicate-relationship':
                            relations[0]['id'] = relations[1]['id']
                        else:
                            relations[0]['type'] = 'appAssetLibraryPlacements'
                        self.state['/v1/appScreenshotSets/set/relationships/appScreenshots'] = relations
                    return result
                with patch.object(cli, 'run', side_effect=changed):
                    with self.assertRaises(u.UploadError):
                        plan.execute()
                self.assertFalse(any(call[0] in {'PATCH', 'POST', 'DELETE'} for call in cli.calls))

    def test_cpp_interrupted_upload_recovers_only_remaining_missing_files(self):
        cli = FakeCLI(self.state, apply=True)
        plan = self.cpp_screenshot_plan(cli, [3])
        def interrupted(args, body=None, mutate=False, cwd=None):
            self.assertNotIn('--skip-existing', args)
            files = sorted(Path(args[args.index('--path') + 1]).glob('*.png'))
            self.assertEqual(files[0].name, '01.png')
            self.state['/v1/appScreenshotSets/set/appScreenshots'].append(row('owned-first-upload', sourceFileChecksum=hashlib.md5(files[0].read_bytes()).hexdigest(), assetDeliveryState={'state': 'COMPLETE'}))
            raise u.UploadError('asc command failed; inspect draft state')
        with patch.object(cli, 'run', side_effect=interrupted):
            with self.assertRaises(u.UploadError):
                plan.execute()
        resumed = self.planner(cli, {'cpp'})
        resumed.screenshots('locale', 'travel', 'en-US', 'iphone')
        with patch.object(sys, 'stdout', new=io.StringIO()):
            resumed.execute()
        self.assertEqual([name for name, _ in cli.staged_screenshots], ['02.png', '04.png', '05.png', '06.png'])
        self.assertEqual(len(self.state['/v1/appScreenshotSets/set/appScreenshots']), 6)
        self.assertEqual(sum(asset['id'] == 'owned-first-upload' for asset in self.state['/v1/appScreenshotSets/set/appScreenshots']), 1)
        self.assertEqual(self.state['/v1/appScreenshotSets/set/appScreenshots'][0]['id'], 'owned-first-upload')

    def test_unsafe_partial_screenshot_sets_refuse_before_upload(self):
        checksum = hashlib.md5(self.slots[('en-US', 'iphone', 'default', 1)]['file'].read_bytes()).hexdigest()
        approved = row('approved', sourceFileChecksum=checksum, assetDeliveryState={'state': 'COMPLETE'})
        cases = [
            [approved, row('foreign', sourceFileChecksum='f' * 32, assetDeliveryState={'state': 'COMPLETE'})],
            [approved, row('duplicate', sourceFileChecksum=checksum, assetDeliveryState={'state': 'COMPLETE'})],
            [approved, approved],
            *[[row('unknown', sourceFileChecksum=value, assetDeliveryState={'state': 'COMPLETE'})] for value in (None, '', {'private': 'PRIVATE_VALUE'})],
            *[[row('pending', sourceFileChecksum=checksum, assetDeliveryState={'state': state})] for state in ('FAILED', 'UPLOAD_COMPLETE', 'AWAITING_UPLOAD', 'PRIVATE_STATE')],
            [row('unknown-state', sourceFileChecksum=checksum)],
            [row('unknown-state', sourceFileChecksum=checksum, assetDeliveryState=None)],
            *[[row(identifier, sourceFileChecksum=checksum, assetDeliveryState={'state': 'COMPLETE'})] for identifier in (None, '', 'https://private.invalid/PRIVATE_VALUE')],
        ]
        self.state['/v1/appStoreVersionLocalizations/locale/appScreenshotSets'] = [row('set', screenshotDisplayType='APP_IPHONE_61')]
        for actual in cases:
            with self.subTest(actual=actual):
                self.state['/v1/appScreenshotSets/set/appScreenshots'] = actual
                cli = FakeCLI(self.state, apply=True)
                plan = self.planner(cli, {'default'})
                with self.assertRaisesRegex(u.UploadError, 'en-US/iphone') as error:
                    plan.screenshots('locale', 'default', 'en-US', 'iphone')
                self.assertNotIn('PRIVATE', str(error.exception))
                self.assertNotIn('https', str(error.exception))
                self.assertEqual(plan.ops, [])
                self.assertTrue(all(call[0] == 'GET' for call in cli.calls))

    def test_conflicting_screenshot_refuses_before_writes(self):
        self.state['/v1/appStoreVersionLocalizations/locale/appScreenshotSets'] = [row('set', screenshotDisplayType='APP_IPHONE_61')]
        self.state['/v1/appScreenshotSets/set/appScreenshots'] = [row('old', sourceFileChecksum='different')]
        cli = FakeCLI(self.state, apply=True)
        with self.assertRaisesRegex(u.UploadError, 'differs'):
            self.planner(cli, {'metadata', 'default'}).preflight()
        self.assertTrue(all(c[0] in {'GET', 'COMMAND'} for c in cli.calls))
        self.assertFalse(any(cli.command_mutations))

    def test_screenshot_conflict_diagnostics_distinguish_repeated_rows_duplicates_and_foreign_assets(self):
        expected = [hashlib.md5(self.slots[('en-US', 'iphone', 'default', order)]['file'].read_bytes()).hexdigest() for order in range(1, 7)]
        approved = [dict(row('shot-' + str(order), sourceFileChecksum=checksum, fileSize=100 + order, assetDeliveryState={'state': 'COMPLETE'}), type='appScreenshots') for order, checksum in enumerate(expected, 1)]
        cases = [
            (approved + [approved[0]], 6),
            (approved + [dict(approved[0], id='second-copy')], 7),
            (approved + [dict(row('foreign', sourceFileChecksum='f' * 32, fileSize=999, assetDeliveryState={'state': 'COMPLETE'}), type='appScreenshots')], 7),
        ]
        self.state['/v1/appStoreVersionLocalizations/locale/appScreenshotSets'] = [row('set', screenshotDisplayType='APP_IPHONE_61')]
        ordered = [{'id': asset['id'], 'type': 'appScreenshots'} for asset in approved]
        self.state['/v1/appScreenshotSets/set/relationships/appScreenshots'] = ordered
        for actual, unique_count in cases:
            with self.subTest(unique_count=unique_count, last_id=actual[-1]['id']):
                for asset in actual:
                    asset['attributes'].update(fileName='PRIVATE_FILE_NAME', assetToken='PRIVATE_TOKEN', imageAsset={'url': 'https://private.invalid/IMAGE'}, uploadOperations=[{'url': 'https://private.invalid/UPLOAD'}])
                    asset['attributes']['assetDeliveryState']['errors'] = [{'description': 'PRIVATE_PROVIDER_ERROR'}]
                self.state['/v1/appScreenshotSets/set/appScreenshots'] = actual
                cli = FakeCLI(self.state, apply=True)
                plan = self.planner(cli, {'default'})
                with self.assertRaises(u.UploadError) as error:
                    plan.screenshots('locale', 'default', 'en-US', 'iphone')
                message = str(error.exception)
                diagnostic = json.loads(message.split('screenshotConflict=', 1)[1])
                self.assertEqual({key: diagnostic[key] for key in ('setId', 'assetCount', 'uniqueIdCount', 'completeCount')}, {'setId': 'set', 'assetCount': 7, 'uniqueIdCount': unique_count, 'completeCount': 7})
                self.assertEqual(diagnostic['approvedChecksums'], [{'order': order, 'checksum': checksum} for order, checksum in enumerate(expected, 1)])
                self.assertEqual(diagnostic['assets'], [{'id': asset['id'], 'type': 'appScreenshots', 'checksum': asset['attributes']['sourceFileChecksum'], 'fileSize': asset['attributes']['fileSize'], 'state': 'COMPLETE'} for asset in actual])
                self.assertEqual(diagnostic['orderedLinkages'], {'rowCount': 6, 'uniqueIdCount': 6, 'assets': ordered})
                for private in ('PRIVATE', 'https', 'assetToken', 'imageAsset', 'uploadOperations', 'fileName', 'errors'):
                    self.assertNotIn(private, message)
                self.assertEqual(plan.ops, [])
                self.assertTrue(all(call[0] == 'GET' for call in cli.calls))

    def test_screenshot_conflict_reads_bounded_sanitized_ordered_linkages(self):
        path = '/v1/appScreenshotSets/set/relationships/appScreenshots'
        self.state['/v1/appStoreVersionLocalizations/locale/appScreenshotSets'] = [row('set', screenshotDisplayType='APP_IPHONE_61')]
        self.state['/v1/appScreenshotSets/set/appScreenshots'] = [row('foreign', sourceFileChecksum='f' * 32, assetDeliveryState={'state': 'COMPLETE'})]
        self.state[path] = [
            {'id': 'known', 'type': 'appScreenshots', 'url': 'https://private.invalid/PRIVATE_TOKEN'},
            {'id': 'https://private.invalid/PRIVATE_ID', 'type': 'PRIVATE_TYPE'},
            {'id': {'private': 'PRIVATE_ID'}, 'type': ['PRIVATE_TYPE']},
            {},
        ] * 6
        cli = FakeCLI(self.state, apply=True)
        plan = self.planner(cli, {'default'})
        with self.assertRaises(u.UploadError) as error:
            plan.screenshots('locale', 'default', 'en-US', 'iphone')
        message = str(error.exception)
        diagnostic = json.loads(message.split('screenshotConflict=', 1)[1])
        self.assertEqual(diagnostic['orderedLinkages']['rowCount'], 24)
        self.assertEqual(diagnostic['orderedLinkages']['uniqueIdCount'], 1)
        self.assertEqual(diagnostic['orderedLinkages']['assets'], [{'id': 'known', 'type': 'appScreenshots'}, {'id': None, 'type': None}, {'id': None, 'type': None}, {'id': None, 'type': None}] * 5)
        self.assertNotIn('PRIVATE', message)
        self.assertNotIn('https', message)
        self.assertEqual(plan.ops, [])
        self.assertTrue(all(call[0] == 'GET' for call in cli.calls))
        self.assertIn(('GET', path, None), cli.calls)
        with patch.object(plan, 'screenshot_linkages', side_effect=u.UploadError('PRIVATE_PROVIDER_ERROR')):
            with self.assertRaises(u.UploadError) as unavailable:
                plan.screenshots('locale', 'default', 'en-US', 'iphone')
        self.assertNotIn('PRIVATE', str(unavailable.exception))
        self.assertIsNone(json.loads(str(unavailable.exception).split('screenshotConflict=', 1)[1])['orderedLinkages'])

    def test_screenshot_conflict_diagnostics_bound_rows_and_sanitize_invalid_fields(self):
        invalid = dict(row('https://private.invalid/PRIVATE_ID', sourceFileChecksum='PRIVATE_CHECKSUM', fileSize=True, assetDeliveryState={'state': 'PRIVATE_STATE', 'errors': ['PRIVATE_ERROR']}), type='https://private.invalid/PRIVATE_TYPE')
        diagnostic = u.safe_screenshot_conflict('https://private.invalid/PRIVATE_SET', [invalid] * 25, ['a' * 32] * 6)
        self.assertEqual(diagnostic['assetCount'], 25)
        self.assertEqual(diagnostic['uniqueIdCount'], 0)
        self.assertEqual(diagnostic['completeCount'], 0)
        self.assertIsNone(diagnostic['setId'])
        self.assertEqual(diagnostic['assets'], [dict.fromkeys(('id', 'type', 'checksum', 'fileSize', 'state'))] * 20)
        self.assertNotIn('PRIVATE', json.dumps(diagnostic))
        self.assertNotIn('https', json.dumps(diagnostic))
        invalid['type'] = 'PrivateProviderToken'
        self.assertIsNone(u.safe_screenshot_conflict('set', [invalid], [])['assets'][0]['type'])
        self.assertEqual(u.safe_screenshot_conflict('set', [], [], ['PRIVATE_ROW'])['orderedLinkages'], {'rowCount': 1, 'uniqueIdCount': 0, 'assets': [{'id': None, 'type': None}]})

    def test_live_or_wrong_version_refuses_before_mutation(self):
        for field, value in [('appStoreState', 'READY_FOR_SALE'), ('versionString', '8.0')]:
            with self.subTest(field=field):
                self.state['/v1/apps/6816213577/appStoreVersions'][0]['attributes'][field] = value
                cli = FakeCLI(self.state, apply=True)
                with self.assertRaises(u.UploadError):
                    self.planner(cli, {'metadata'}).preflight()
                self.assertTrue(all(c[0] == 'GET' for c in cli.calls))

    def test_cpp_policy_excludes_watch_without_losing_default_watch_sets(self):
        locales = json.loads((MODULE.parent / 'metadata.json').read_text())['locales']
        self.meta['locales'] = locales
        self.state['/v1/apps/6816213577/appStoreVersions'].append(row('released', platform='IOS', appStoreState='READY_FOR_SALE'))
        source = dict(self.slots)
        for locale in locales:
            for family in u.FAMILIES:
                for profile in u.PROFILES:
                    for order in range(1, 7):
                        self.slots[(locale, profile, family, order)] = source[('en-US', profile, 'default', order)]
        self.state['/v1/appStoreVersions/version/appStoreVersionLocalizations'] = [row('locale-' + locale, locale=locale) for locale in locales]
        cli = FakeCLI(self.state, apply=True)
        plan = self.planner(cli, {'default', 'cpp'}).preflight()
        screenshots = [operation for operation in plan.ops if operation['method'] == 'SCREENSHOTS']
        self.assertEqual(plan.cpp_profiles, ['iphone', 'ipad'])
        self.assertEqual(len(screenshots), 234)
        self.assertEqual(sum(len(operation['files']) for operation in screenshots), 1404)
        self.assertEqual(len([operation for operation in screenshots if operation['profile'] == 'watch']), 18)
        self.assertTrue(all(operation['family'] == 'default' for operation in screenshots if operation['profile'] == 'watch'))
        self.assertTrue(any('Watch screenshots omitted' in note for note in plan.notes))
        self.assertTrue(all(call[0] == 'GET' for call in cli.calls))

    def test_cpp_core_profile_missing_or_insufficient_policy_fails_before_planning(self):
        for group, maximum in [('IPHONE_DYNAMIC_ISLAND_MEDIUM_PROFILE', None), ('IPAD_13_PROFILE', None), ('IPAD_13_PROFILE', 5)]:
            with self.subTest(group=group, maximum=maximum):
                reference = native_reference()
                policy = reference[0]['attributes']['features'][1]['placementPolicies'][0]
                policy['groupLimits'][1]['groupIds'].remove(group)
                if maximum is not None:
                    policy['groupLimits'].append({'groupIds': [group], 'maxCount': maximum})
                self.state['/v1/appAssetLibraryRefData'] = reference
                cli = FakeCLI(self.state, apply=True)
                plan = self.planner(cli, {'metadata', 'cpp'})
                with self.assertRaises(u.UploadError):
                    plan.preflight()
                self.assertEqual(plan.ops, [])
                self.assertTrue(all(call[0] == 'GET' for call in cli.calls))

    def test_cpp_missing_placement_policy_does_not_treat_watch_as_optional(self):
        reference = native_reference()
        reference[0]['attributes']['features'][1]['placementPolicies'] = []
        self.state['/v1/appAssetLibraryRefData'] = reference
        plan = self.planner(FakeCLI(self.state), {'cpp'})
        with self.assertRaisesRegex(u.UploadError, 'policy is unavailable'):
            plan.native_policy_preflight()
        self.assertEqual(plan.ops, [])

    def test_duo_queues_native_images_and_exact_order_without_legacy_enum(self):
        cli = FakeCLI(self.state)
        plan = self.planner(cli, {'duo'})
        plan.library = 'library'
        plan.native_policy_preflight()
        for profile in ('duo-outer', 'duo-inner'):
            for order in range(1, 7):
                file = self.root / (profile + str(order) + '.png')
                file.write_bytes((profile + str(order)).encode())
                self.slots[('en-US', profile, 'default', order)] = {'file': file, 'sha256': u.sha256(file)}
        plan.duo_screenshots('locale', 'default', 'en-US')
        uploads = [op for op in plan.ops if op['method'] == 'LIBRARY']
        placements = [op for op in plan.ops if op['path'] == '/v1/appAssetLibraryPlacements']
        self.assertEqual(len(uploads), 6)
        self.assertEqual(len(placements), 6)
        expected_files = [str(self.slots[('en-US', profile, 'default', order)]['file']) for order, profile in enumerate(self.meta['duoPresentation']['default'], 1)]
        self.assertEqual([operation['file'] for operation in uploads], expected_files)
        self.assertTrue(all(op['body']['data']['attributes']['placementGroup'] == 'IPHONE_DUO_PROFILE' for op in placements))
        ordering = plan.ops[-1]['body']['data']
        self.assertEqual(ordering['relationships']['orderedPlacements']['data'], [{'type': 'appAssetLibraryPlacements', 'id': op['ref']} for op in placements])
        self.assertNotIn('APP_IPHONE_DUO', json.dumps(plan.summary()))
        self.assertTrue(all(call[0] == 'GET' for call in cli.calls))

    def test_native_capacity_insufficient_for_shared_duo_group_stops_before_any_plan(self):
        self.state['/v1/appAssetLibraryRefData'] = native_reference(duo_limit=5)
        cli = FakeCLI(self.state, apply=True)
        plan = self.planner(cli, {'metadata', 'duo', 'header'})
        with self.assertRaisesRegex(u.UploadError, 'requires 6, maximum 5'):
            plan.preflight()
        self.assertEqual(plan.ops, [])
        self.assertTrue(all(call[0] == 'GET' for call in cli.calls))

    def test_invalid_duo_selection_cannot_plan_placements(self):
        for profiles in (None, [], ['duo-inner'] * 6, ['duo-outer', 'duo-inner'] * 2, [{}] * 6):
            with self.subTest(profiles=profiles):
                self.meta['duoPresentation']['default'] = profiles
                cli = FakeCLI(self.state, apply=True)
                plan = self.planner(cli, {'duo'})
                with self.assertRaisesRegex(u.UploadError, 'Duo presentation'):
                    plan.native_policy_preflight()
                self.assertEqual(plan.ops, [])
                self.assertTrue(all(call[0] == 'GET' for call in cli.calls))

    def test_live_exact_duo_dimensions_accept_approved_six_image_mix(self):
        self.state['/v1/appAssetLibraryRefData'] = live_duo_reference()
        cli = FakeCLI(self.state, apply=True)
        plan = self.planner(cli, {'metadata', 'duo'})
        plan.native_policy_preflight()
        self.assertEqual(plan.duo_groups, {'duo-outer': 'IPHONE_DUO_PROFILE', 'duo-inner': 'IPHONE_DUO_PROFILE'})
        self.assertTrue(all('requires 6, maximum 10' in note for note in plan.notes))
        self.assertEqual(plan.ops, [])
        self.assertTrue(all(call[0] == 'GET' for call in cli.calls))

    def test_live_exact_duo_dimensions_pass_nominal_ratio_with_sufficient_capacity(self):
        self.state['/v1/appAssetLibraryRefData'] = live_duo_reference(limit=12)
        cli = FakeCLI(self.state)
        plan = self.planner(cli, {'duo'})
        plan.native_policy_preflight()
        self.assertEqual(plan.duo_groups, {'duo-outer': 'IPHONE_DUO_PROFILE', 'duo-inner': 'IPHONE_DUO_PROFILE'})
        self.assertEqual(len(plan.notes), 2)
        self.assertTrue(all('requires 6, maximum 12' in note for note in plan.notes))
        self.assertTrue(all(call[0] == 'GET' for call in cli.calls))

    def test_native_capacity_checks_cpp_feature_independently(self):
        self.state['/v1/appAssetLibraryRefData'] = native_reference(duo_limit=10, cpp_limit=5)
        cli = FakeCLI(self.state, apply=True)
        plan = self.planner(cli, {'duo'})
        with self.assertRaisesRegex(u.UploadError, 'CUSTOM_PRODUCT_PAGES/APP_SCREENSHOT'):
            plan.preflight()
        self.assertEqual(plan.ops, [])
        self.assertTrue(all(call[0] == 'GET' for call in cli.calls))

    def test_header_capacity_zero_stops_before_any_metadata_changes(self):
        self.state['/v1/appAssetLibraryRefData'] = native_reference(header_limit=0)
        cli = FakeCLI(self.state, apply=True)
        plan = self.planner(cli, {'metadata', 'header'})
        with self.assertRaisesRegex(u.UploadError, 'PRODUCT_PAGE_HEADER_ASSET/DEFAULT_PROFILE: requires 1, maximum 0'):
            plan.preflight()
        self.assertEqual(plan.ops, [])
        self.assertTrue(all(call[0] == 'GET' for call in cli.calls))

    def test_native_unknown_policy_or_spec_fails_closed(self):
        for missing in ('features', 'placementProfileGroups', 'placementTypes', 'imageSpecs'):
            with self.subTest(missing=missing):
                reference = native_reference()
                reference[0]['attributes'].pop(missing)
                self.state['/v1/appAssetLibraryRefData'] = reference
                cli = FakeCLI(self.state, apply=True)
                plan = self.planner(cli, {'metadata', 'duo'})
                with self.assertRaises(u.UploadError):
                    plan.preflight()
                self.assertEqual(plan.ops, [])
                self.assertTrue(all(call[0] == 'GET' for call in cli.calls))

    def test_split_duo_groups_use_live_limits_and_order_each_group(self):
        self.state['/v1/appAssetLibraryRefData'] = native_reference(duo_limit=6, split=True)
        cli = FakeCLI(self.state)
        plan = self.planner(cli, {'duo', 'header'})
        plan.library = 'library'
        plan.native_policy_preflight()
        self.assertEqual(plan.duo_groups, {'duo-outer': 'DUO_OUTER_PROFILE', 'duo-inner': 'DUO_INNER_PROFILE'})
        self.assertEqual(plan.header_group, 'DEFAULT_PROFILE')
        self.assertEqual(len(plan.notes), 6)
        for profile in ('duo-outer', 'duo-inner'):
            for order in range(1, 7):
                file = self.root / (profile + str(order) + '.png')
                file.write_bytes((profile + str(order)).encode())
                self.slots[('en-US', profile, 'default', order)] = {'file': file, 'sha256': u.sha256(file)}
        plan.duo_screenshots('locale', 'default', 'en-US')
        orders = [op for op in plan.ops if op['path'] == '/v1/appAssetLibraryPlacementOrderingRequests']
        self.assertEqual(len(orders), 2)
        self.assertTrue(all(len(op['body']['data']['relationships']['orderedPlacements']['data']) == 3 for op in orders))
        self.assertTrue(all(call[0] == 'GET' for call in cli.calls))

    def test_header_reconciliation_requests_video_linkage_for_default_and_cpp(self):
        for family in ('default', 'travel'):
            with self.subTest(family=family):
                kind = 'appStoreVersionLocalizations' if family == 'default' else 'appCustomProductPageLocalizations'
                path = '/v1/' + kind + '/locale/placements'
                bare = row('header', placementType='PRODUCT_PAGE_HEADER_ASSET', placementGroup='DEFAULT_PROFILE', state='PARENT_PREPARE_FOR_SUBMISSION')
                linked = dict(bare, relationships={'video': u.relationship('appAssetLibraryVideos', 'approved-video')})
                self.state[path] = [bare]
                self.state[path + '?include=video'] = [linked]
                cli = FakeCLI(self.state)
                plan = self.planner(cli, {'header'})
                plan.header_group = 'DEFAULT_PROFILE'
                plan.place_header('locale', family, 'approved-video')
                self.assertEqual(plan.ops, [])
                self.assertEqual(cli.calls, [('GET', path + '?include=video', None)])
                for video in ('different-video', None):
                    self.state[path + '?include=video'] = [dict(bare, relationships={'video': u.relationship('appAssetLibraryVideos', video)}) if video else bare]
                    with self.assertRaisesRegex(u.UploadError, 'header differs'):
                        plan.place_header('locale', family, 'approved-video')
                    self.assertEqual(plan.ops, [])

    def approved_header_replacement(self, state='PREPARE_FOR_SUBMISSION'):
        checksum = 'a' * 64
        videos = [row('old-video', referenceName='currency-approved-' + checksum, state='APPROVED', category='CREATIVE_ASSETS', videoAsset={'templateUrl':'old'}), row('new-video', referenceName='currency-approved-' + 'b' * 64, state=state, category='CREATIVE_ASSETS', videoAsset={'templateUrl':'new'})]
        path = '/v1/appStoreVersionLocalizations/locale/placements?include=video'
        placement = dict(row('old-header', placementType='PRODUCT_PAGE_HEADER_ASSET', placementGroup='DEFAULT_PROFILE'), relationships={'video':u.relationship('appAssetLibraryVideos','old-video')})
        self.state[path] = [placement]
        self.state['/v1/appAssetLibraries/library/videos'] = videos
        cli = FakeCLI(self.state, apply=True)
        plan = u.Planner(cli,self.meta,self.slots,{},'version','1.2','info',{'header'},replace_header_sha256=checksum)
        plan.library,plan.header_group = 'library','DEFAULT_PROFILE'
        plan.library_rows['video'] = videos
        plan.media['currency-approved-' + 'b' * 64] = 'new-video'
        return plan,cli,path

    def test_explicit_header_replacement_keeps_old_library_asset_and_queues_new_video(self):
        plan,cli,path = self.approved_header_replacement()
        plan.place_header('locale','default','new-video')
        self.assertEqual([op['method'] for op in plan.ops],['REPLACE_APPROVED_HEADER','POST'])
        self.assertTrue(all(call[0]=='GET' for call in cli.calls))
        plan.execute()
        deletes = [call for call in cli.calls if call[0]=='DELETE']
        self.assertEqual(deletes,[('DELETE','/v1/appAssetLibraryPlacements/old-header',None)])
        self.assertEqual([item['id'] for item in self.state['/v1/appAssetLibraries/library/videos']],['old-video','new-video'])
        post = next(call for call in cli.calls if call[:2]==('POST','/v1/appAssetLibraryPlacements'))
        self.assertEqual(post[2]['data']['relationships']['video']['data']['id'],'new-video')

    def test_header_replacement_refuses_wrong_hash_ambiguity_and_changed_slot(self):
        for conflict in ['hash','duplicates','group','changed-after-plan','new-checksum']:
            with self.subTest(conflict=conflict):
                plan,cli,path = self.approved_header_replacement()
                if conflict=='hash': plan.replace_header_sha256='b'*64
                if conflict=='duplicates': self.state[path].append(dict(self.state[path][0],id='extra-header'))
                if conflict=='group': self.state[path][0]['attributes']['placementGroup']='OTHER_PROFILE'
                if conflict in {'changed-after-plan','new-checksum'}:
                    plan.place_header('locale','default','new-video')
                    if conflict=='changed-after-plan': self.state[path][0]['id']='different-header'
                    else: self.state['/v1/appAssetLibraries/library/videos'][1]['attributes']['referenceName']='unreviewed-video'
                    with self.assertRaises(u.UploadError): plan.execute()
                else:
                    with self.assertRaisesRegex(u.UploadError,'header differs'): plan.place_header('locale','default','new-video')
                self.assertFalse(any(call[0] in {'DELETE','POST'} for call in cli.calls))

    def test_localized_header_update_accepts_only_explicit_previous_checksum_set(self):
        plan, cli, path = self.approved_header_replacement()
        plan.replace_header_sha256 = 'c' * 64 + ',' + 'a' * 64
        plan.place_header('locale', 'default', 'new-video')
        self.assertEqual(plan.ops[0]['old_reference'], 'currency-approved-' + 'a' * 64)
        self.assertEqual(plan.summary()[0]['previousApprovedSha256'], 'a' * 64)
        plan.execute()
        self.assertEqual([call[1] for call in cli.calls if call[0] == 'DELETE'], ['/v1/appAssetLibraryPlacements/old-header'])
        plan, cli, path = self.approved_header_replacement()
        plan.replace_header_sha256 = 'c' * 64 + ',' + 'd' * 64
        with self.assertRaisesRegex(u.UploadError, 'header differs'):
            plan.place_header('locale', 'default', 'new-video')
        self.assertTrue(all(call[0] == 'GET' for call in cli.calls))

    def test_previous_header_checksum_lists_reject_empty_or_invalid_entries(self):
        for checksum in ('', ',' + 'a' * 64, 'a' * 64 + ',', 'a' * 64 + ',*', 'a' * 64 + ', ' + 'b' * 64, 'A' * 64):
            with self.subTest(checksum=checksum):
                with self.assertRaisesRegex(u.UploadError, 'exact previous approved SHA'):
                    u.Planner(FakeCLI(self.state), self.meta, self.slots, {}, 'version', '1.2', 'info', {'header'}, replace_header_sha256=checksum)

    def test_header_replacement_refuses_unprocessed_video_before_deleting(self):
        plan,cli,path = self.approved_header_replacement(state='UPLOAD_COMPLETE')
        plan.place_header('locale','default','new-video')
        with self.assertRaisesRegex(u.UploadError,'ready before swapping'): plan.execute()
        self.assertEqual(self.state[path][0]['id'],'old-header')
        self.assertFalse(any(call[0] in {'DELETE','POST'} for call in cli.calls))

    def test_header_replacement_requires_exact_hash_and_header_scope(self):
        for checksum,scopes in [('not-a-checksum',{'header'}),('a'*64,{'metadata'})]:
            with self.assertRaisesRegex(u.UploadError,'exact previous approved SHA'):
                u.Planner(FakeCLI(self.state),self.meta,self.slots,{},'version','1.2','info',scopes,replace_header_sha256=checksum)

    def test_duo_reconciliation_requests_image_linkage_and_retains_approved_placements(self):
        for family in ('default', 'travel'):
            with self.subTest(family=family):
                kind = 'appStoreVersionLocalizations' if family == 'default' else 'appCustomProductPageLocalizations'
                path = '/v1/' + kind + '/locale/placements'
                linked = []
                for order, profile in enumerate(self.meta['duoPresentation'][family], 1):
                    self.slots[('en-US', profile, family, order)] = {'image': 'approved-' + str(order)}
                    placement = row('placement-' + str(order), placementType='APP_SCREENSHOT', placementGroup='IPHONE_DUO_PROFILE', state='PARENT_PREPARE_FOR_SUBMISSION')
                    linked.append(dict(placement, relationships={'image': u.relationship('appAssetLibraryImages', 'approved-' + str(order))}))
                self.state[path] = [{key: value for key, value in placement.items() if key != 'relationships'} for placement in linked]
                self.state[path + '?include=image'] = list(reversed(linked))
                self.state[path + '?include=image&sort=placementGroupPosition'] = linked
                cli = FakeCLI(self.state)
                plan = self.planner(cli, {'duo'})
                plan.duo_groups = {profile: 'IPHONE_DUO_PROFILE' for profile in ('duo-outer', 'duo-inner')}
                with patch.object(plan, 'library_media', side_effect=lambda item, media_type: item['image']):
                    plan.duo_screenshots('locale', family, 'en-US')
                self.assertEqual(plan.ops, [])
                self.assertEqual(cli.calls, [('GET', path + '?include=image&sort=placementGroupPosition', None)])
                for image in ('different-image', None):
                    self.state[path + '?include=image&sort=placementGroupPosition'] = [dict(linked[0], relationships={'image': u.relationship('appAssetLibraryImages', image)}) if image else self.state[path][0]] + linked[1:]
                    with patch.object(plan, 'library_media', side_effect=lambda item, media_type: item['image']):
                        with self.assertRaisesRegex(u.UploadError, 'placements differ'):
                            plan.duo_screenshots('locale', family, 'en-US')
                    self.assertTrue(all(call[0] == 'GET' for call in cli.calls))
                for actual, message in (
                    (linked + [linked[0]], 'Duplicate Duo image placements'),
                    ([dict(linked[0], attributes=dict(linked[0]['attributes'], state='FAILED'))] + linked[1:], 'Existing Duo placement failed'),
                    ([dict(linked[0], attributes=dict(linked[0]['attributes'], placementType='APP_PREVIEW'))] + linked[1:], 'app previews'),
                ):
                    self.state[path + '?include=image&sort=placementGroupPosition'] = actual
                    guarded = self.planner(cli, {'duo'})
                    guarded.duo_groups = plan.duo_groups
                    with patch.object(guarded, 'library_media', side_effect=lambda item, media_type: item['image']):
                        with self.assertRaisesRegex(u.UploadError, message):
                            guarded.duo_screenshots('locale', family, 'en-US')
                    self.assertEqual(guarded.ops, [])

    def test_duo_reorders_only_groups_with_mismatched_display_order(self):
        for family in ('default', 'travel'):
            for split in (False, True):
                with self.subTest(family=family, split=split):
                    kind = 'appStoreVersionLocalizations' if family == 'default' else 'appCustomProductPageLocalizations'
                    relation = 'appStoreVersionLocalization' if family == 'default' else 'appCustomProductPageLocalization'
                    path = '/v1/' + kind + '/locale/placements?include=image&sort=placementGroupPosition'
                    groups = {profile: profile if split else 'IPHONE_DUO_PROFILE' for profile in ('duo-outer', 'duo-inner')}
                    linked = []
                    for order, profile in enumerate(self.meta['duoPresentation'][family], 1):
                        self.slots[('en-US', profile, family, order)] = {'image': 'approved-' + str(order)}
                        placement = row('placement-' + str(order), placementType='APP_SCREENSHOT', placementGroup=groups[profile], state='PARENT_PREPARE_FOR_SUBMISSION')
                        linked.append(dict(placement, relationships={'image': u.relationship('appAssetLibraryImages', 'approved-' + str(order))}))
                    changed_group = groups['duo-outer']
                    reversed_group = iter(reversed([placement for placement in linked if placement['attributes']['placementGroup'] == changed_group]))
                    self.state[path] = [next(reversed_group) if placement['attributes']['placementGroup'] == changed_group else placement for placement in linked]
                    cli = FakeCLI(self.state)
                    plan = self.planner(cli, {'duo'})
                    plan.duo_groups = groups
                    with patch.object(plan, 'library_media', side_effect=lambda item, media_type: item['image']):
                        plan.duo_screenshots('locale', family, 'en-US')
                    self.assertEqual(len(plan.ops), 1)
                    operation = plan.ops[0]
                    self.assertEqual(operation['path'], '/v1/appAssetLibraryPlacementOrderingRequests')
                    self.assertEqual(operation['body']['data']['attributes'], {'placementGroup': changed_group})
                    self.assertEqual(operation['body']['data']['relationships'][relation], u.relationship(kind, 'locale'))
                    self.assertEqual(operation['body']['data']['relationships']['orderedPlacements']['data'], [{'type': 'appAssetLibraryPlacements', 'id': placement['id']} for placement in linked if placement['attributes']['placementGroup'] == changed_group])
                    self.assertEqual(cli.calls, [('GET', path, None)])

    def test_localized_header_routing_selects_language_for_default_and_cpp_and_deduplicates(self):
        self.meta['locales']['de-DE'] = dict(self.meta['locales']['en-US'])
        files = {}
        for locale in ['en-US','de-DE']:
            path = self.root / (locale + '.mp4')
            path.write_bytes(locale.encode())
            files[locale] = {'file':path,'sha256':u.sha256(path),'video':{'fps':60,'duration':15,'audio':False}}
        cli = FakeCLI(self.state)
        plan = u.Planner(cli,self.meta,self.slots,{'locales':files},'version','1.2','info',{'header'})
        plan.library,plan.header_group = 'library','DEFAULT_PROFILE'
        targets = {('default','en-US'):'en',('default','de-DE'):'de',('travel','en-US'):'cpp-en',('travel','de-DE'):'cpp-de'}
        plan.place_headers(targets)
        uploads = [op for op in plan.ops if op['method']=='LIBRARY']
        self.assertEqual(len(uploads),2)
        references = {op['file']:op['ref'] for op in uploads}
        placements = [op['body']['data']['relationships'] for op in plan.ops if op['path']=='/v1/appAssetLibraryPlacements']
        self.assertEqual([item['video']['data']['id'] for item in placements],[references[str(files[locale]['file'])] for family,locale in targets])
        self.assertEqual([next(item[key]['data']['id'] for key in ['appStoreVersionLocalization','appCustomProductPageLocalization'] if key in item) for item in placements],list(targets.values()))
        files['de-DE'] = files['en-US']
        shared = u.Planner(FakeCLI(self.state),self.meta,self.slots,{'locales':files},'version','1.2','info',{'header'})
        shared.library,shared.header_group = 'library','DEFAULT_PROFILE'
        shared.place_headers(targets)
        self.assertEqual(len([op for op in shared.ops if op['method']=='LIBRARY']),1)
        self.assertTrue(all(call[0]=='GET' for call in cli.calls))

    def test_localized_header_missing_locale_fails_before_remote_calls(self):
        self.meta['locales']['de-DE'] = dict(self.meta['locales']['en-US'])
        cli = FakeCLI(self.state)
        with self.assertRaisesRegex(u.UploadError,'cover every metadata locale'):
            u.Planner(cli,self.meta,self.slots,{'locales':{'en-US':{}}},'version','1.2','info',{'header'})
        self.assertEqual(cli.calls,[])

    def test_localized_media_validation_requires_complete_map_and_checks_each_header(self):
        metadata, manifest, _ = self.approved_media_fixture()
        generic = manifest.pop('header')
        other = self.root / 'german.mp4'
        other.write_bytes(b'german-video')
        manifest['headers'] = {locale:dict(generic) for locale in metadata['locales']}
        manifest['headers']['de-DE'] = {'path':other.name,'sha256':u.sha256(other)}
        with patch.object(u,'validate_video',return_value={'fps':60,'duration':15,'audio':False}) as probe:
            slots, headers = u.validate_media(self.root,manifest,metadata)
            self.assertEqual(probe.call_count,2)
            self.assertEqual(headers['locales']['de-DE']['file'],other.resolve())
            self.assertEqual(headers['locales']['en-US']['file'],(self.root/'header.mp4').resolve())
        (self.root/'manifest.json').write_text(json.dumps(manifest))
        arguments = ['upload.py','--validate-only','--metadata',str(self.root/'metadata.json'),'--media-dir',str(self.root)]
        with patch.object(sys,'argv',arguments), patch.object(u,'validate_video',return_value={'fps':60,'duration':15,'audio':False}), patch.object(u,'CLI') as client, patch.object(sys,'stdout',new_callable=io.StringIO) as output:
            self.assertEqual(u.main(),0)
            self.assertTrue(json.loads(output.getvalue())['verifiedHeader'])
            client.assert_not_called()
        del manifest['headers']['de-DE']
        manifest['header'] = generic
        with self.assertRaisesRegex(u.UploadError,'without a global fallback'):
            u.validate_media(self.root,manifest,metadata,probe_header=False)
        del manifest['header']
        with self.assertRaisesRegex(u.UploadError,'every metadata locale'):
            u.validate_media(self.root,manifest,metadata,probe_header=False)

    def test_header_uses_runtime_group_and_optional_video_constraints(self):
        reference = native_reference()
        attributes = reference[0]['attributes']
        next(group for group in attributes['placementProfileGroups'] if group['placementProfileGroupId'] == 'DEFAULT_PROFILE')['placementProfileGroupId'] = 'CREATIVE_DEFAULT_V2'
        attributes['placementTypes'][-1]['specMappings'][0]['placementGroupId'] = 'CREATIVE_DEFAULT_V2'
        for feature in attributes['features']:
            feature['placementPolicies'][-1]['groupLimits'][0]['groupIds'] = ['CREATIVE_DEFAULT_V2']
        attributes['videoSpecs'][0].update(aspectRatio='21:9', frameRates=[{'minFps': 30, 'maxFps': 30}], duration={'min': 'PT5S', 'max': 'PT30S'}, audioRequired=False)
        self.state['/v1/appAssetLibraryRefData'] = reference
        plan = self.planner(FakeCLI(self.state), {'header'})
        plan.header = {'video': {'fps': 30, 'duration': 15, 'audio': False}}
        plan.native_policy_preflight()
        plan.place_header('locale', 'default', 'video-id')
        self.assertEqual(plan.ops[-1]['body']['data']['attributes']['placementGroup'], 'CREATIVE_DEFAULT_V2')

    def test_optional_native_spec_constraints_fail_before_changes(self):
        for change in ({'aspectRatio': '1:1'}, {'frameRates': [{'minFps': 60, 'maxFps': 60}]}, {'duration': {'min': 'PT5S', 'max': 'PT10S'}}, {'audioRequired': True}):
            with self.subTest(change=change):
                reference = native_reference()
                reference[0]['attributes']['videoSpecs'][0].update(change)
                if 'aspectRatio' in change:
                    reference[0]['attributes']['videoSpecs'][0]['dimensions'].update(maxWidth=4000, maxHeight=2000)
                self.state['/v1/appAssetLibraryRefData'] = reference
                cli = FakeCLI(self.state, apply=True)
                plan = self.planner(cli, {'metadata', 'header'})
                plan.header = {'video': {'fps': 30, 'duration': 15, 'audio': False}}
                with self.assertRaisesRegex(u.UploadError, 'specification is missing or ambiguous'):
                    plan.preflight()
                self.assertEqual(plan.ops, [])
                self.assertTrue(all(call[0] == 'GET' for call in cli.calls))

    def test_first_release_plans_all_cpp_families_and_default_duo(self):
        self.state['/v1/apps/6816213577/assetLibrary'] = [row('library')]
        for family in u.FAMILIES:
            for profile in u.PROFILES:
                for order in range(1, 7):
                    self.slots[('en-US', profile, family, order)] = self.slots[('en-US', profile, 'default', order)]
            for order, profile in enumerate(self.meta['duoPresentation'][family], 1):
                file = self.root / (family + '-duo' + str(order) + '.png')
                file.write_bytes((family + str(order)).encode())
                self.slots[('en-US', profile, family, order)] = {'file': file, 'sha256': u.sha256(file)}
        cli = FakeCLI(self.state, apply=True)
        plan = self.planner(cli, {'cpp', 'duo'}).preflight()
        self.assertEqual(plan.cpp_status, {'preparedFamilyCount': 5, 'targetedFamilies': u.FAMILIES[1:]})
        self.assertEqual(len([operation for operation in plan.ops if operation['method'] == 'CPP_CREATE']), 5)
        self.assertEqual(len([operation for operation in plan.ops if operation['method'] == 'CPP_VERSION_LOOKUP']), 5)
        self.assertFalse(any(operation['method'] == 'POST' and operation['path'] in {'/v1/appCustomProductPages', '/v1/appCustomProductPageVersions'} for operation in plan.ops))
        placements = [operation for operation in plan.ops if operation['path'] == '/v1/appAssetLibraryPlacements']
        self.assertEqual(len(placements), 36)
        self.assertEqual(len([operation for operation in placements if 'appStoreVersionLocalization' in operation['body']['data']['relationships']]), 6)
        self.assertTrue(all(call[0] == 'GET' for call in cli.calls))

    def test_cpp_creation_uses_pinned_command_and_reuses_initial_version_and_locale(self):
        cli = FakeCLI(self.state, apply=True)
        plan = self.planner(cli, {'cpp'})
        plan.cpp_targets({})
        commands = []
        def create(args, body=None, mutate=False, cwd=None):
            commands.append((args, mutate))
            name = args[args.index('--name') + 1]
            family = name.split(' - ')[1]
            page = 'page-' + family
            self.state['/v1/appCustomProductPages/' + page + '/appCustomProductPageVersions'] = [row('version-' + family, state='PREPARE_FOR_SUBMISSION')]
            self.state['/v1/appCustomProductPageVersions/version-' + family + '/appCustomProductPageLocalizations'] = [row('locale-' + family, locale='en-US', promotionalText='')]
            return {'data': {'type': 'appCustomProductPages', 'id': page}}
        with patch.object(cli, 'run', side_effect=create):
            plan.execute()
        self.assertEqual(len(commands), 5)
        for (args, mutate), family in zip(commands, u.FAMILIES[1:]):
            self.assertEqual(args, ['product-pages', 'custom-pages', 'create', '--app', self.meta['appId'], '--name', 'Currency - ' + family, '--output', 'json'])
            self.assertTrue(mutate)
        writes = [call for call in cli.calls if call[0] != 'GET']
        self.assertEqual(len(writes), 5)
        self.assertTrue(all(call[0] == 'PATCH' and call[1].startswith('/v1/appCustomProductPageLocalizations/locale-') for call in writes))

    def test_cpp_page_appearing_after_preflight_is_reused_without_create(self):
        cli = FakeCLI(self.state, apply=True)
        plan = self.planner(cli, {'duo'})
        page_ref = plan.queue('CPP_CREATE', '/v1/appCustomProductPages', name='Currency - offline')
        plan.queue('CPP_VERSION_LOOKUP', '/v1/appCustomProductPages/' + page_ref + '/appCustomProductPageVersions')
        self.state['/v1/apps/6816213577/appCustomProductPages'] = [row('ui-created-page', name='Currency - offline')]
        self.state['/v1/appCustomProductPages/ui-created-page/appCustomProductPageVersions'] = [row('ui-created-version', state='PREPARE_FOR_SUBMISSION')]
        plan.execute()
        self.assertTrue(all(call[0] == 'GET' for call in cli.calls))

    def test_cpp_creation_or_initial_version_failure_never_falls_back_to_bare_post(self):
        cli = FakeCLI(self.state, apply=True)
        plan = self.planner(cli, {'cpp'})
        page = plan.queue('CPP_CREATE', '/v1/appCustomProductPages', name='Currency - offline')
        plan.queue('CPP_VERSION_LOOKUP', '/v1/appCustomProductPages/' + page + '/appCustomProductPageVersions')
        with patch.object(cli, 'run', side_effect=u.UploadError('asc command failed (HTTP 409)')):
            with self.assertRaisesRegex(u.UploadError, 'HTTP 409') as error:
                plan.execute()
        self.assertNotIn('first release', str(error.exception))
        with patch.object(cli, 'run', return_value={'data': {'id': 'created-page'}}):
            with self.assertRaisesRegex(u.UploadError, 'one editable initial version'):
                plan.execute()
        self.assertTrue(all(call[0] == 'GET' for call in cli.calls))

    def test_existing_cpp_still_updates_without_creating_a_duplicate(self):
        self.state['/v1/apps/6816213577/appCustomProductPages'] = [row('page', name='Currency - travel')]
        self.state['/v1/appCustomProductPages/page/appCustomProductPageVersions'] = [row('cpp-version', state='PREPARE_FOR_SUBMISSION')]
        self.state['/v1/appCustomProductPageVersions/cpp-version/appCustomProductPageLocalizations'] = [row('cpp-locale', locale='en-US', promotionalText='Old text')]
        plan = self.planner(FakeCLI(self.state), {'cpp'})
        targets = {}
        plan.cpp_targets(targets)
        self.assertEqual(len([operation for operation in plan.ops if operation['method'] == 'CPP_CREATE']), 4)
        self.assertEqual(targets[('travel', 'en-US')], 'cpp-locale')
        self.assertEqual(len([operation for operation in plan.ops if operation['method'] == 'PATCH' and operation['path'] == '/v1/appCustomProductPageLocalizations/cpp-locale']), 1)

    def test_duo_only_cpp_targets_do_not_change_text_or_keywords(self):
        self.meta['locales']['en-US'].pop('contextualPromotionalText')
        self.meta['keywordRouting'] = {family: {'en-US': ['travel']} for family in u.FAMILIES[1:]}
        self.state['/v1/apps/6816213577/appCustomProductPages'] = [row('page-' + family, name='Currency - ' + family) for family in u.FAMILIES[1:]]
        for family in u.FAMILIES[1:]:
            self.state['/v1/appCustomProductPages/page-' + family + '/appCustomProductPageVersions'] = [row('version-' + family, state='PREPARE_FOR_SUBMISSION')]
            self.state['/v1/appCustomProductPageVersions/version-' + family + '/appCustomProductPageLocalizations'] = [row('locale-' + family, locale='en-US', promotionalText='Keep current text')]
        cli = FakeCLI(self.state, apply=True)
        plan = self.planner(cli, {'duo'})
        targets = {}
        plan.cpp_targets(targets)
        self.assertEqual(plan.ops, [])
        self.assertEqual(len(targets), 5)
        self.assertEqual(plan.notes, [])
        self.assertTrue(all(call[0] == 'GET' and 'searchKeywords' not in call[1] for call in cli.calls))
        for family in u.FAMILIES[1:]:
            self.state['/v1/appCustomProductPageVersions/version-' + family + '/appCustomProductPageLocalizations'] = []
        missing = self.planner(FakeCLI(self.state, apply=True), {'duo'})
        missing.cpp_targets({})
        self.assertEqual(len(missing.ops), 5)
        self.assertTrue(all(op['method'] == 'POST' and op['body']['data']['type'] == 'appCustomProductPageLocalizations' and op['body']['data']['attributes'] == {'locale': 'en-US'} for op in missing.ops))

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
        response = subprocess.CompletedProcess([], 1, json.dumps({'videoId': 'reserved-video', 'results': [{'assetId': 'reserved-screenshot', 'filePath': '/private/local/path'}], 'uploadOperations': [{'url': 'https://private.invalid/signed-token'}]}), 'private')
        with patch.object(subprocess, 'run', return_value=response):
            with self.assertRaises(u.UploadError):
                cli.run(['asset-library', 'videos', 'upload'], mutate=True)
        text = receipt.read_text()
        self.assertIn('reserved-video', text)
        self.assertIn('reserved-screenshot', text)
        self.assertNotIn('/private/local/path', text)
        self.assertNotIn('https', text)
        self.assertNotIn('signed-token', text)
        self.assertEqual(receipt.stat().st_mode & 0o777, 0o600)

    def test_header_videos_prepare_concurrently_before_any_placement(self):
        cli = FakeCLI(apply=True)
        plan = self.planner(cli, set())
        refs = [plan.queue('LIBRARY', '', media_type='video', library='library', file='approved-file', reference='approved-' + str(i)) for i in range(3)]
        plan.queue('POST', '/v1/appAssetLibraryPlacements', u.resource('appAssetLibraryPlacements', {}, {'video': u.relationship('appAssetLibraryVideos', refs[0])}))
        barrier = threading.Barrier(3)
        def prepare(op):
            barrier.wait(timeout=3)
            self.assertFalse(cli.calls)
            return 'video-' + op['reference']
        with patch.object(plan, 'prepare_video', side_effect=prepare), patch.object(sys, 'stdout', new=io.StringIO()):
            plan.execute()
        self.assertEqual(len(cli.calls), 1)
        self.assertEqual(cli.calls[0][2]['data']['relationships']['video']['data']['id'], 'video-approved-0')

    def test_header_preparation_failure_preserves_every_existing_placement(self):
        plan, cli, path = self.approved_header_replacement()
        plan.queue('LIBRARY', '', media_type='video', library='library', file='approved-file', reference='approved-video')
        plan.place_header('locale', 'default', 'new-video')
        with patch.object(plan, 'prepare_video', side_effect=u.UploadError('processing incomplete')):
            with self.assertRaisesRegex(u.UploadError, 'processing incomplete'):
                plan.execute()
        self.assertEqual(self.state[path][0]['id'], 'old-header')
        self.assertTrue(all(call[0] == 'GET' for call in cli.calls))

    def test_pending_approved_video_reuses_identity_without_duplicate_upload(self):
        file = self.root / 'approved-header.mp4'
        file.write_bytes(b'approved')
        checksum = hashlib.sha256(file.read_bytes()).hexdigest()
        video = dict(row('pending-video', referenceName='currency-approved-' + checksum, category='CREATIVE_ASSETS', fileSize=file.stat().st_size, state='PREPARE_FOR_SUBMISSION', specId='header', videoAsset=None), type='appAssetLibraryVideos')
        cli = FakeCLI({'/v1/appAssetLibraries/library/videos': [video]}, apply=True)
        plan = self.planner(cli, {'header'})
        plan.library = 'library'
        ref = plan.library_media({'sha256': checksum, 'file': file}, 'video')
        self.assertEqual([op['method'] for op in plan.ops], ['WAIT_VIDEO'])
        self.assertEqual(plan.summary()[0]['approvedReference'], 'currency-approved-' + checksum)
        plan.queue('POST', '/v1/appAssetLibraryPlacements', u.resource('appAssetLibraryPlacements', {}, {'video': u.relationship('appAssetLibraryVideos', ref)}))
        ready = json.loads(json.dumps(video))
        ready['attributes']['videoAsset'] = 'https://example.invalid/processed'
        with patch.object(cli, 'run', side_effect=[{'data': video}, {'data': ready}]) as command, patch.object(u.time, 'sleep'), patch.object(sys, 'stdout', new=io.StringIO()):
            plan.execute()
        self.assertEqual(command.call_count, 2)
        self.assertTrue(all(call.args[0][:2] == ['api', 'GET'] for call in command.call_args_list))
        post = next(call for call in cli.calls if call[0] == 'POST')
        self.assertEqual(post[2]['data']['relationships']['video']['data']['id'], 'pending-video')

    def test_pending_video_wait_rejects_changed_identity_failure_and_timeout(self):
        original = dict(row('pending-video', referenceName='approved-reference', category='CREATIVE_ASSETS', fileSize=8, state='PREPARE_FOR_SUBMISSION', specId='header', videoAsset=None), type='appAssetLibraryVideos')
        for change in ('referenceName', 'fileSize', 'category', 'id', 'type', 'attributes', 'failed', 'timeout'):
            with self.subTest(change=change):
                video = json.loads(json.dumps(original))
                if change in ('referenceName', 'category'): video['attributes'][change] = 'different'
                if change == 'fileSize': video['attributes'][change] = 9
                if change in ('id', 'type'): video[change] = 'different'
                if change == 'attributes': video['attributes'] = None
                if change == 'failed': video['attributes']['state'] = 'FAILED'
                cli = FakeCLI(apply=True)
                plan = self.planner(cli, set())
                op = {'method': 'WAIT_VIDEO', 'video_id': 'pending-video', 'reference': 'approved-reference', 'bytes': 8}
                with patch.object(cli, 'run', return_value={'data': video}) as command, patch.object(u.time, 'monotonic', side_effect=[0, 1801]), patch.object(u.time, 'sleep') as sleep:
                    with self.assertRaises(u.UploadError): plan.prepare_video(op)
                sleep.assert_not_called()
                self.assertEqual(command.call_args.args[0][:2], ['api', 'GET'])
                self.assertFalse(command.call_args.kwargs.get('mutate', False))

    def test_pending_ids_resolve_in_order(self):
        cli = FakeCLI(apply=True)
        plan = self.planner(cli, set())
        parent = plan.queue('POST', '/v1/appCustomProductPages', u.resource('appCustomProductPages', {'name': 'offline'}))
        plan.queue('POST', '/v1/appCustomProductPageVersions', u.resource('appCustomProductPageVersions', {}, {'appCustomProductPage': u.relationship('appCustomProductPages', parent)}))
        plan.execute()
        self.assertEqual(cli.calls[1][2]['data']['relationships']['appCustomProductPage']['data']['id'], 'created-1')

    def test_library_upload_rejects_malformed_responses_and_preserves_valid_asset_identity(self):
        for media_type in ('image', 'video'):
            key = media_type + 'Id'
            for response in (None, [], 'PRIVATE_RESPONSE', 7, {}, {key: None}, {key: []}, {key: {'private': 'PRIVATE_ID'}}, {key: 'https://private.invalid/PRIVATE_ID'}):
                with self.subTest(media_type=media_type, response=response):
                    cli = FakeCLI(self.state, apply=True)
                    plan = self.planner(cli, set())
                    plan.queue('LIBRARY', '', media_type=media_type, library='library', file='approved-file', reference='approved-reference')
                    plan.queue('POST', '/next', u.resource('appAssetLibraryPlacements', {}))
                    with patch.object(cli, 'run', return_value=response) as upload:
                        with self.assertRaisesRegex(u.UploadError, 'inspect remote library') as error:
                            plan.execute()
                    self.assertEqual(upload.call_count, 1)
                    self.assertTrue(upload.call_args.kwargs['mutate'])
                    self.assertEqual(cli.calls, [])
                    self.assertNotIn('PRIVATE', str(error.exception))
                    self.assertNotIn('https', str(error.exception))
            cli = FakeCLI(self.state, apply=True)
            plan = self.planner(cli, set())
            asset = plan.queue('LIBRARY', '', media_type=media_type, library='library', file='approved-file', reference='approved-reference')
            plan.queue('POST', '/v1/appAssetLibraryPlacements', u.resource('appAssetLibraryPlacements', {}, {media_type: u.relationship('appAssetLibraryImages' if media_type == 'image' else 'appAssetLibraryVideos', asset)}))
            with patch.object(cli, 'run', return_value={key: 'uploaded-' + media_type}), patch.object(sys, 'stdout', new=io.StringIO()):
                plan.execute()
            self.assertEqual(cli.calls[0][2]['data']['relationships'][media_type]['data']['id'], 'uploaded-' + media_type)

    def test_generic_resource_mutations_reject_malformed_response_envelopes_and_identities(self):
        for method in ('POST', 'PATCH'):
            responses = [None, [], 'PRIVATE_RESPONSE', {'data': None}, {'data': []}, {'data': 'PRIVATE_DATA'}, {'data': {'id': None}}, {'data': {'id': []}}, {'data': {'id': 'https://private.invalid/PRIVATE_ID'}}]
            if method == 'POST':
                responses.extend([{}, {'data': {}}])
            for response in responses:
                with self.subTest(method=method, response=response):
                    plan = self.planner(FakeCLI(self.state, apply=True), set())
                    body = u.resource('appAssetLibraryPlacements', {'placementType': 'APP_SCREENSHOT'})
                    plan.queue(method, '/mutation', body)
                    plan.queue('POST', '/next', u.resource('appAssetLibraryPlacements', {}))
                    with patch.object(plan, 'apply_resource', return_value=response) as mutation:
                        with self.assertRaisesRegex(u.UploadError, 'inspect') as error:
                            plan.execute()
                    mutation.assert_called_once_with(method, '/mutation', body)
                    self.assertNotIn('PRIVATE', str(error.exception))
                    self.assertNotIn('https', str(error.exception))

    def test_generic_mutations_preserve_empty_patch_and_relationship_success_responses(self):
        resource_body = u.resource('appAssetLibraryPlacements', {'placementType': 'APP_SCREENSHOT'})
        relationship_body = {'data': [{'type': 'appScreenshots', 'id': 'screenshot'}]}
        cases = [('PATCH', resource_body, {}), ('PATCH', resource_body, {'data': {}})]
        cases.extend((method, relationship_body, response) for method in ('POST', 'PATCH') for response in ({}, {'data': []}))
        for method, body, response in cases:
            with self.subTest(method=method, body=body, response=response):
                plan = self.planner(FakeCLI(self.state, apply=True), set())
                plan.queue(method, '/mutation', body)
                with patch.object(plan, 'apply_resource', return_value=response) as mutation, patch.object(sys, 'stdout', new=io.StringIO()):
                    plan.execute()
                mutation.assert_called_once_with(method, '/mutation', body)

    def test_target_discovery_rejects_non_mapping_read_envelopes(self):
        for response in (None, [], 'PRIVATE_RESPONSE'):
            with patch.object(FakeCLI, 'api', return_value=response) as api:
                with self.assertRaisesRegex(u.UploadError, 'invalid collection; inspect App Store Connect') as error:
                    u.resolve_targets(FakeCLI(self.state), '6816213577')
            self.assertEqual(api.call_count, 1)
            self.assertNotIn('PRIVATE', str(error.exception))

    def test_cli_paginates_placement_includes_but_not_single_asset_library(self):
        paths = [
            ('/v1/appStoreVersionLocalizations/locale/placements?include=video', True),
            ('/v1/appCustomProductPageLocalizations/locale/placements?include=image', True),
            ('/v1/appStoreVersionLocalizations/locale/placements?include=image&sort=placementGroupPosition', True),
            ('/v1/appCustomProductPageLocalizations/locale/placements?include=image&sort=placementGroupPosition', True),
            ('/v1/apps/app/appStoreVersions', True),
            ('/v1/apps/app/assetLibrary', False),
            ('/v1/apps/app/assetLibrary?fields%5BappAssetLibraries%5D=images', False),
            ('/v1/appScreenshots/screenshot?include=appScreenshotSet', False),
        ]
        cli = u.CLI()
        for path, paginated in paths:
            with self.subTest(path=path), patch.object(cli, 'run', return_value={}) as run:
                cli.api('GET', path)
                expected = ['api', 'GET', path, '--output', 'json'] + (['--paginate'] if paginated else [])
                run.assert_called_once_with(expected, None, mutate=False)

    def test_cli_delete_without_body_omits_body_file(self):
        cli = u.CLI(apply=True)
        with patch.object(cli, 'run', return_value={}) as run:
            cli.api('DELETE', '/v1/appScreenshots/screenshot')
            run.assert_called_once_with(['api', 'DELETE', '/v1/appScreenshots/screenshot', '--output', 'json', '--confirm'], None, mutate=True)

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

    def test_cli_reports_only_allowlisted_structured_http_status(self):
        for stream in ('stdout', 'stderr'):
            for status in ('401', '403', '404', '409', '422', '429', '500', 503):
                with self.subTest(stream=stream, status=status):
                    payload = json.dumps({'errors': [{'status': status, 'title': 'PRIVATE_KEY', 'detail': 'https://private.invalid/signed-token'}]})
                    output = {'stdout': '', 'stderr': ''}
                    output[stream] = payload
                    result = subprocess.CompletedProcess([], 1, output['stdout'], output['stderr'])
                    with patch.object(subprocess, 'run', return_value=result):
                        with self.assertRaises(u.UploadError) as error:
                            u.CLI().api('GET', '/v1/apps')
                    message = str(error.exception)
                    self.assertIn('HTTP ' + str(status), message)
                    self.assertNotIn('PRIVATE_KEY', message)
                    self.assertNotIn('https', message)
                    self.assertNotIn('signed-token', message)

    def test_cli_keeps_unknown_or_missing_error_status_generic(self):
        for payload in ({'errors': [{'title': 'PRIVATE_KEY', 'detail': 'https://private.invalid'}]}, {'errors': [{'status': '403 https://private.invalid'}]}, {'errors': [{'status': '400'}]}, {'errors': 'PRIVATE_KEY'}, ['PRIVATE_KEY']):
            with self.subTest(payload=payload):
                result = subprocess.CompletedProcess([], 1, json.dumps(payload), 'PRIVATE_KEY')
                with patch.object(subprocess, 'run', return_value=result):
                    with self.assertRaises(u.UploadError) as error:
                        u.CLI().api('GET', '/v1/apps')
                self.assertNotIn('HTTP', str(error.exception))
                self.assertNotIn('PRIVATE_KEY', str(error.exception))
                self.assertNotIn('https', str(error.exception))

    def test_prefixed_json_error_reports_only_validated_status_code_pointer(self):
        payload = {'errors': [{'status': '409', 'code': 'ENTITY_ERROR.ATTRIBUTE.INVALID', 'source': {'pointer': '/data/attributes/locale', 'parameter': 'PRIVATE_KEY'}, 'title': 'PRIVATE_KEY', 'detail': 'https://signed.invalid/PRIVATE_KEY', 'privateKey': 'PRIVATE_KEY'}]}
        for stream in ('stdout', 'stderr'):
            with self.subTest(stream=stream):
                text = 'Error: api POST failed PRIVATE_KEY https://signed.invalid/token\n' + json.dumps(payload) + '\nPrivate suffix'
                result = subprocess.CompletedProcess([], 1, text if stream == 'stdout' else '', text if stream == 'stderr' else '')
                with patch.object(subprocess, 'run', return_value=result):
                    with self.assertRaises(u.UploadError) as error:
                        u.CLI(apply=True).api('POST', '/v1/appStoreVersionLocalizations', {})
                message = str(error.exception)
                self.assertIn('HTTP 409', message)
                self.assertIn('ENTITY_ERROR.ATTRIBUTE.INVALID', message)
                self.assertIn('/data/attributes/locale', message)
                for secret in ('PRIVATE_KEY', 'https', 'signed.invalid', 'Private suffix', 'title', 'detail', 'parameter', 'privateKey'):
                    self.assertNotIn(secret, message)

    def test_invalid_structured_code_and_pointer_are_suppressed(self):
        payload = {'errors': [{'status': '422', 'code': 'https://PRIVATE_KEY.invalid', 'source': {'pointer': '/data/attributes/https://PRIVATE_KEY.invalid'}, 'detail': 'PRIVATE_KEY'}]}
        message = u.safe_error_diagnostics('', 'prefix ' + json.dumps(payload))
        self.assertEqual(message, ' (HTTP 422)')
        self.assertEqual(u.safe_error_diagnostics('', 'Error: flag provided but not defined: -PRIVATE_KEY'), '')
        late = 'x' * 262144 + json.dumps({'errors': [{'status': '403'}]})
        self.assertEqual(u.safe_error_diagnostics('', late), '')

    def test_api_debug_is_captured_and_only_response_status_is_exposed(self):
        trace = 'level=INFO msg="→ HTTP Request" method=POST url=https://signed.invalid/PRIVATE_KEY authorization="Bearer PRIVATE_KEY"\nlevel=INFO msg="← HTTP Response" status=409 elapsed=1ms content-type=application/json\nError: PRIVATE_KEY https://signed.invalid\n'
        result = subprocess.CompletedProcess([], 1, '', trace)
        with patch.object(subprocess, 'run', return_value=result) as process:
            with self.assertRaises(u.UploadError) as error:
                u.CLI(apply=True).api('POST', '/v1/appStoreVersionLocalizations', {})
        self.assertIn('HTTP 409', str(error.exception))
        self.assertNotIn('PRIVATE_KEY', str(error.exception))
        self.assertNotIn('signed.invalid', str(error.exception))
        self.assertEqual(process.call_args.kwargs['env']['ASC_DEBUG'], 'api')
        self.assertNotIn('ASC_DEBUG_HTTP', process.call_args.kwargs['env'])
        self.assertTrue(process.call_args.kwargs['capture_output'])
        self.assertEqual(u.safe_error_diagnostics('', 'prefix level=INFO msg="← HTTP Response" status=403', http_trace=True), '')

    def test_api_failure_reports_bounded_route_without_ids_query_or_provider_text(self):
        trace = 'level=INFO msg="← HTTP Response" status=500 private=PRIVATE_BODY\nError: https://signed.invalid/PRIVATE_TOKEN\n'
        result = subprocess.CompletedProcess([], 1, 'PRIVATE_BODY', trace)
        path = '/v1/appScreenshotSets/PRIVATE_SET_ID/appScreenshots?url=https://signed.invalid/PRIVATE_TOKEN'
        with patch.object(subprocess, 'run', return_value=result) as process:
            with self.assertRaises(u.UploadError) as error:
                u.CLI().api('GET', path)
        self.assertEqual(str(error.exception), 'asc command failed (HTTP 500) (API GET /v1/appScreenshotSets/:id/appScreenshots); inspect App Store Connect draft state before retrying (raw output suppressed)')
        self.assertIn(path, process.call_args.args[0])
        for private in ('PRIVATE', 'signed.invalid', 'https', '?', 'url='):
            self.assertNotIn(private, str(error.exception))

    def test_api_route_redacts_unknown_segments_and_ids_matching_resource_names(self):
        self.assertEqual(u.safe_api_route('PATCH', '/v1/appScreenshotSets/apps/relationships/appScreenshots'), ' (API PATCH /v1/appScreenshotSets/:id/relationships/appScreenshots)')
        path = '/v1/PRIVATE_RESOURCE/PRIVATE_ID/PRIVATE_CHILD/' + '/'.join(['PRIVATE_' + 'x' * 1000] * 100) + '?PRIVATE_QUERY'
        label = u.safe_api_route('GET', path)
        self.assertEqual(label, ' (API GET /v1/:id/:id/:id/:id/:id)')
        self.assertLess(len(label), 300)

    def test_metadata_failure_reports_only_validated_action_summary_and_http_status(self):
        actions = [{'scope': 'app-info', 'locale': 'en-US', 'action': 'update', 'status': 'succeeded', 'localizationId': 'id'} for _ in range(31)]
        actions.append({'scope': 'version', 'locale': 'fr-FR', 'action': 'create', 'status': 'failed', 'desiredFields': {'description': 'PRIVATE_COPY', 'keywords': 'PRIVATE_TERMS', 'privateKey': 'PRIVATE_KEY', 'supportUrl': 'https://signed.invalid/TOKEN'}, 'error': 'PRIVATE_ERROR https://signed.invalid/TOKEN', 'version': 'PRIVATE_VERSION'})
        actions.extend([{'scope': 'PRIVATE_SCOPE', 'locale': 'en-US', 'action': 'update', 'status': 'failed'}, {'scope': 'version', 'locale': 'PRIVATE_LOCALE', 'action': 'update', 'status': 'failed'}, {'scope': 'version', 'locale': 'en-US', 'action': 'PRIVATE_ACTION', 'status': 'failed'}, {'scope': 'version', 'locale': 'en-US', 'action': 'update', 'status': 'PRIVATE_STATUS'}])
        output = json.dumps({'actions': actions, 'failed': 999, 'failureArtifactPath': 'PRIVATE_PATH', 'dir': 'PRIVATE_DIR'})
        trace = 'level=INFO msg="→ HTTP Request" url=https://signed.invalid/TOKEN authorization="Bearer PRIVATE_KEY"\nlevel=INFO msg="← HTTP Response" status=409 elapsed=1ms\n'
        result = subprocess.CompletedProcess([], 1, output, trace)
        with patch.object(subprocess, 'run', return_value=result) as process:
            with self.assertRaises(u.UploadError) as error:
                u.CLI(apply=True).run(['metadata', 'apply', '--output', 'json'], mutate=True)
        message = str(error.exception)
        self.assertIn('HTTP 409', message)
        self.assertIn('"counts":{"succeeded":31,"failed":1,"skipped":0}', message)
        self.assertIn('"locale":"fr-FR"', message)
        self.assertIn('"attemptedFields":["description","keywords","supportUrl"]', message)
        for secret in ('PRIVATE', 'https', 'signed.invalid', 'TOKEN', '999', 'localizationId'):
            self.assertNotIn(secret, message)
        self.assertEqual(process.call_args.kwargs['env']['ASC_DEBUG'], 'api')
        self.assertTrue(process.call_args.kwargs['capture_output'])

    def test_metadata_name_conflict_reports_only_fixed_exact_phrase_classification(self):
        action = {'scope': 'app-info', 'locale': 'de-DE', 'action': 'update', 'status': 'failed', 'desiredFields': {'name': 'PRIVATE_NAME', 'subtitle': 'PRIVATE_SUBTITLE'}}
        for phrase in ('The app name you entered is already being used', 'THE APP NAME YOU ENTERED IS ALREADY BEING USED'):
            with self.subTest(phrase=phrase):
                output = json.dumps({'actions': [dict(action, error='PRIVATE_PREFIX https://signed.invalid/TOKEN ' + phrase + ' PRIVATE_SUFFIX')]})
                summary = u.safe_metadata_failure_summary(output)
                self.assertIn('"reason":"app-name-already-used"', summary)
                for private in ('PRIVATE', 'https', 'TOKEN', 'signed.invalid', phrase):
                    self.assertNotIn(private, summary)
        for error in ('PRIVATE unrelated validation error', 'app name is unavailable', 'x' * 16385 + 'the app name you entered is already being used', None):
            summary = u.safe_metadata_failure_summary(json.dumps({'actions': [dict(action, error=error)]}))
            self.assertNotIn('reason', summary)
        summary = u.safe_metadata_failure_summary(json.dumps({'actions': [dict(action, status='succeeded', error='the app name you entered is already being used')]}))
        self.assertNotIn('reason', summary)

    def test_metadata_failure_summary_rejects_invalid_unbounded_or_non_json_results(self):
        for output in ('PRIVATE_ERROR', json.dumps({'actions': 'PRIVATE'}), json.dumps({'actions': [{'scope': {}}]}), json.dumps({'actions': [{}] * 201}), 'x' * 1048577, json.dumps({'actions': [{'scope': 'version', 'locale': 'en-US', 'action': 'update', 'status': 'PRIVATE'}]})):
            self.assertEqual(u.safe_metadata_failure_summary(output), '')

    def test_long_http_trace_preserves_late_failure_without_private_output(self):
        output = 'level=INFO msg="← HTTP Response" status=429\n' + 'PRIVATE_BODY https://signed.invalid/TOKEN\n' * 10000
        output += 'level=INFO msg="← HTTP Response" status=503 private=PRIVATE_BODY\n'
        self.assertEqual(u.safe_error_diagnostics('', output, http_trace=True), ' (HTTP 429, 503)')
        self.assertEqual(u.safe_error_diagnostics('', output), '')

    def test_cpp_screenshot_upload_captures_trace_and_reports_only_allowed_http_status(self):
        command = ['product-pages', 'custom-pages', 'localizations', 'screenshot-sets', 'upload', '--localization-id', 'locale', '--path', '/private/approved']
        trace = 'level=INFO msg="→ HTTP Request" url=https://signed.invalid/PRIVATE_KEY authorization="Bearer PRIVATE_KEY"\nlevel=INFO msg="← HTTP Response" status=409 elapsed=1ms private=PRIVATE_BODY\nlevel=INFO msg="← HTTP Response" status=400\nprefix level=INFO msg="← HTTP Response" status=503\nError: PRIVATE_ERROR https://signed.invalid/TOKEN\n'
        result = subprocess.CompletedProcess([], 1, 'PRIVATE_BODY https://signed.invalid/TOKEN', trace)
        with patch.dict(u.os.environ, {'ASC_DEBUG_HTTP': 'true'}), patch.object(subprocess, 'run', return_value=result) as process:
            with self.assertRaises(u.UploadError) as error:
                u.CLI(apply=True).run(command, mutate=True)
        self.assertEqual(str(error.exception), 'asc command failed (HTTP 409); inspect App Store Connect draft state before retrying (raw output suppressed)')
        self.assertEqual(process.call_args.kwargs['env']['ASC_DEBUG'], 'api')
        self.assertNotIn('ASC_DEBUG_HTTP', process.call_args.kwargs['env'])
        self.assertTrue(process.call_args.kwargs['capture_output'])
        self.assertEqual(process.call_args.args[0][1:], command)

    def test_library_and_other_screenshot_helpers_never_inherit_http_debug(self):
        trace = 'level=INFO msg="← HTTP Response" status=409 PRIVATE_KEY\n'
        for command in (
            ['asset-library', 'videos', 'upload'],
            ['screenshots', 'upload'],
            ['product-pages', 'custom-pages', 'localizations', 'screenshot-sets'],
            ['product-pages', 'custom-pages', 'localizations', 'screenshot-sets', 'uploads'],
            ['product-pages', 'custom-pages', 'localizations', 'screenshots', 'upload'],
            ['product-pages', 'custom-pages', 'screenshot-sets', 'localizations', 'upload'],
        ):
            with self.subTest(command=command):
                result = subprocess.CompletedProcess([], 1, '', trace)
                with patch.dict(u.os.environ, {'ASC_DEBUG': 'api', 'ASC_DEBUG_HTTP': 'true'}), patch.object(subprocess, 'run', return_value=result) as process:
                    with self.assertRaises(u.UploadError) as error:
                        u.CLI(apply=True).run(command, mutate=True)
                self.assertEqual(process.call_args.kwargs['env']['ASC_DEBUG'], 'false')
                self.assertNotIn('ASC_DEBUG_HTTP', process.call_args.kwargs['env'])
                self.assertNotIn('HTTP', str(error.exception))
                self.assertNotIn('PRIVATE_KEY', str(error.exception))

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

    def approved_media_fixture(self):
        metadata = json.loads((MODULE.parent / 'metadata.json').read_text())
        placements = []
        for profile, (width, height) in u.DIMENSIONS.items():
            path = self.root / (profile + '.png')
            path.write_bytes(b'\x89PNG\r\n\x1a\n' + struct.pack('>I4sIIBBBBBI', 13, b'IHDR', width, height, 8, 2, 0, 0, 0, 0) + struct.pack('>I4sI', 0, b'IEND', 0))
            placements.extend({'locale': locale, 'profile': profile, 'family': family, 'order': order, 'path': path.name, 'sha256': u.sha256(path)} for locale in metadata['locales'] for family in u.FAMILIES for order in range(1, 7))
        header = self.root / 'header.mp4'
        header.write_bytes(b'PRIVATE_APPROVED_VIDEO')
        manifest = {'schemaVersion': 1, 'placements': placements, 'header': {'path': header.name, 'sha256': u.sha256(header)}}
        metadata_path = self.root / 'metadata.json'
        metadata_path.write_text(json.dumps(metadata))
        (self.root / 'manifest.json').write_text(json.dumps(manifest))
        return metadata, manifest, metadata_path

    def test_cpp_validation_checks_all_media_hashes_without_video_dependency(self):
        metadata, manifest, metadata_path = self.approved_media_fixture()
        arguments = ['upload.py', '--validate-only', '--scope', 'cpp', '--metadata', str(metadata_path), '--media-dir', str(self.root)]
        with patch.object(sys, 'argv', arguments), patch.object(subprocess, 'run') as process, patch.object(u, 'CLI') as client, patch.object(sys, 'stdout', new_callable=io.StringIO) as output:
            self.assertEqual(u.main(), 0)
            process.assert_not_called()
            client.assert_not_called()
        self.assertEqual(json.loads(output.getvalue()), {'mode': 'validate-only', 'verifiedPlacements': 3240, 'verifiedHeader': False, 'verifiedHeaderHash': True, 'appStoreRequests': 0})
        with patch.object(subprocess, 'run') as process:
            (self.root / 'header.mp4').write_bytes(b'PRIVATE_CHANGED_VIDEO')
            with self.assertRaisesRegex(u.UploadError, '^Approved header video is missing or has the wrong hash$'):
                u.validate_media(self.root, manifest, metadata, probe_header=False)
            process.assert_not_called()

    def test_cpp_validation_still_rejects_changed_png(self):
        metadata, manifest, _ = self.approved_media_fixture()
        (self.root / manifest['placements'][0]['path']).write_bytes(b'PRIVATE_CHANGED_PNG')
        with patch.object(subprocess, 'run') as process:
            with self.assertRaisesRegex(u.UploadError, '^Screenshot PNG dimensions do not match its device profile$'):
                u.validate_media(self.root, manifest, metadata, probe_header=False)
            process.assert_not_called()

    def test_header_and_default_validation_require_probe_and_reject_invalid_format(self):
        metadata, manifest, metadata_path = self.approved_media_fixture()
        with patch.object(subprocess, 'run', side_effect=FileNotFoundError()) as process:
            with self.assertRaisesRegex(u.UploadError, 'install ffprobe'):
                u.validate_media(self.root, manifest, metadata)
            self.assertEqual(process.call_args.args[0][0], 'ffprobe')
        for scope in ([], ['--scope', 'header']):
            with self.subTest(scope=scope):
                arguments = ['upload.py', '--validate-only', '--metadata', str(metadata_path), '--media-dir', str(self.root), *scope]
                result = subprocess.CompletedProcess([], 0, json.dumps({'streams': [], 'format': {'duration': '15'}}), '')
                with patch.object(sys, 'argv', arguments), patch.object(subprocess, 'run', return_value=result) as process, patch.object(u, 'CLI') as client:
                    with self.assertRaisesRegex(u.UploadError, 'Header must be the approved'):
                        u.main()
                    self.assertEqual(process.call_args.args[0][0], 'ffprobe')
                    client.assert_not_called()
        result = subprocess.CompletedProcess([], 0, json.dumps({'streams': [{'codec_type': 'video', 'width': 3840, 'height': 1646, 'avg_frame_rate': '30/1'}], 'format': {'duration': '15'}}), '')
        arguments = ['upload.py', '--validate-only', '--metadata', str(metadata_path), '--media-dir', str(self.root)]
        with patch.object(sys, 'argv', arguments), patch.object(subprocess, 'run', return_value=result), patch.object(sys, 'stdout', new_callable=io.StringIO) as output:
            self.assertEqual(u.main(), 0)
        self.assertEqual(json.loads(output.getvalue()), {'mode': 'validate-only', 'verifiedPlacements': 3240, 'verifiedHeader': True, 'verifiedHeaderHash': True, 'appStoreRequests': 0})

    def test_main_accepts_previous_header_hash_sets(self):
        metadata = self.root / 'metadata.json'
        metadata.write_text(json.dumps(self.meta))
        (self.root / 'manifest.json').write_text('{}')
        for hashes in ('a' * 64, ','.join(character * 64 for character in '01234567')):
            with self.subTest(hashes=hashes):
                cli = FakeCLI(self.state)
                args = ['upload.py', '--metadata', str(metadata), '--media-dir', str(self.root), '--receipts', str(self.root / 'receipt.jsonl'), '--scope', 'header', '--replace-header-sha256', hashes]
                with patch.object(sys, 'argv', args), patch.object(u, 'validate_media', return_value=({}, {})), patch.object(u, 'CLI', return_value=cli), patch.object(u, 'Planner') as planner, patch.object(sys, 'stdout', new_callable=io.StringIO):
                    planner.return_value.preflight.return_value = SimpleNamespace(ops=[], blockers=[], notes=[], cpp_status=None, summary=lambda: [])
                    self.assertEqual(u.main(), 0)
                    self.assertEqual(planner.call_args.kwargs['replace_header_sha256'], hashes)
                self.assertTrue(all(call[0] == 'GET' for call in cli.calls))

    def test_main_rejects_invalid_previous_header_hash_sets_before_remote_access(self):
        valid = 'a' * 64
        for hashes in ('', '*', valid + ',', ',' + valid, valid + ', ' + valid, valid + ',' + 'A' * 64, valid + ',short'):
            with self.subTest(hashes=hashes):
                args = ['upload.py', '--scope', 'header', '--replace-header-sha256', hashes]
                with patch.object(sys, 'argv', args), patch.object(u, 'CLI') as client, patch.object(sys, 'stderr', new_callable=io.StringIO):
                    with self.assertRaises(SystemExit) as error:
                        u.main()
                    self.assertEqual(error.exception.code, 2)
                    client.assert_not_called()

    def test_remote_plan_requires_receipts(self):
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

    def test_target_discovery_selects_only_unique_editable_ios_and_info(self):
        self.state['/v1/apps/6816213577/appStoreVersions'] += [row('live', platform='IOS', versionString='1.0', appStoreState='READY_FOR_SALE'), row('mac', platform='MAC_OS', versionString='1.2', appStoreState='PREPARE_FOR_SUBMISSION')]
        self.state['/v1/apps/6816213577/appInfos'].append(row('live-info', appStoreState='READY_FOR_SALE'))
        cli = FakeCLI(self.state, apply=True)
        target = u.resolve_targets(cli, '6816213577')
        self.assertEqual(target, {'versionId': 'version', 'versionString': '1.2', 'appInfoId': 'info'})
        self.assertEqual([call[0] for call in cli.calls], ['GET', 'GET'])

    def test_target_discovery_rejects_ambiguous_version_without_mutation(self):
        self.state['/v1/apps/6816213577/appStoreVersions'].append(row('another', platform='IOS', versionString='1.3', appStoreState='PREPARE_FOR_SUBMISSION'))
        cli = FakeCLI(self.state, apply=True)
        with self.assertRaisesRegex(u.UploadError, 'Multiple editable iOS'):
            u.resolve_targets(cli, '6816213577')
        self.assertTrue(all(call[0] == 'GET' for call in cli.calls))
        self.assertEqual(u.resolve_targets(cli, '6816213577', version_string='1.3')['versionId'], 'another')
        self.assertEqual(u.resolve_targets(cli, '6816213577', version_id='version')['versionString'], '1.2')

    def test_target_discovery_filters_never_fall_back_to_another_draft(self):
        for filters in ({'version_id': 'wrong'}, {'version_string': '9.0'}, {'version_id': 'version', 'version_string': '9.0'}, {'info_id': 'wrong'}):
            with self.subTest(filters=filters):
                cli = FakeCLI(self.state, apply=True)
                with self.assertRaisesRegex(u.UploadError, 'No editable'):
                    u.resolve_targets(cli, '6816213577', **filters)
                self.assertTrue(all(call[0] == 'GET' for call in cli.calls))

    def test_target_discovery_rejects_zero_or_live_only_candidates(self):
        for collection, replacement in [('appStoreVersions', []), ('appStoreVersions', [row('live', platform='IOS', versionString='1.0', appStoreState='READY_FOR_SALE')]), ('appInfos', []), ('appInfos', [row('live', appStoreState='READY_FOR_SALE')])]:
            with self.subTest(collection=collection, replacement=replacement):
                state = dict(self.state)
                state['/v1/apps/6816213577/' + collection] = replacement
                cli = FakeCLI(state, apply=True)
                with self.assertRaisesRegex(u.UploadError, 'No editable'):
                    u.resolve_targets(cli, '6816213577')
                self.assertTrue(all(call[0] == 'GET' for call in cli.calls))

    def test_target_discovery_ambiguous_info_requires_exact_filter(self):
        self.state['/v1/apps/6816213577/appInfos'].append(row('second-info', appStoreState='REJECTED'))
        cli = FakeCLI(self.state, apply=True)
        with self.assertRaisesRegex(u.UploadError, 'Multiple editable app-info'):
            u.resolve_targets(cli, '6816213577')
        self.assertEqual(u.resolve_targets(cli, '6816213577', info_id='second-info')['appInfoId'], 'second-info')
        self.assertTrue(all(call[0] == 'GET' for call in cli.calls))

    def test_main_blank_filters_resolve_then_pass_exact_target_to_planner(self):
        metadata = self.root / 'metadata.json'
        metadata.write_text(json.dumps(self.meta))
        (self.root / 'manifest.json').write_text('{}')
        cli = FakeCLI(self.state)
        args = ['upload.py', '--metadata', str(metadata), '--media-dir', str(self.root), '--receipts', str(self.root / 'receipt.jsonl'), '--version-id', '', '--version-string', '', '--app-info-id', '']
        with patch.object(sys, 'argv', args), patch.object(u, 'validate_media', return_value=({}, {})), patch.object(u, 'CLI', return_value=cli), patch.object(u, 'Planner') as planner, patch.object(sys, 'stdout', new_callable=io.StringIO) as output:
            planner.return_value.preflight.return_value = SimpleNamespace(ops=[], blockers=[], notes=[], cpp_status=None, summary=lambda: [])
            self.assertEqual(u.main(), 0)
            self.assertEqual(planner.call_args.args[4:7], ('version', '1.2', 'info'))
            resolved = json.loads(output.getvalue().splitlines()[0])
            self.assertEqual(resolved, {'resolvedTarget': {'versionId': 'version', 'versionString': '1.2', 'appInfoId': 'info'}})
        self.assertTrue(all(call[0] == 'GET' for call in cli.calls))

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
