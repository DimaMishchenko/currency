import ast
import contextlib
import io
import json
from pathlib import Path
import unittest
import textwrap

workflow = Path(__file__).resolve().parents[3] / '.github/workflows/app-store-assets.yml'
body = workflow.read_text().split("python3 - <<'PY'\n", 1)[1].split('\n          PY', 1)[0]
program = ast.parse(textwrap.dedent(body))

class NativeInspectionTests(unittest.TestCase):
    def run_inspector(self, response):
        namespace = {}
        exec(compile(ast.Module(body=program.body[:-1], type_ignores=[]), '<workflow-inspector>', 'exec'), namespace)
        calls = []
        class FakeCLI:
            def __init__(self, apply=False):
                if apply:
                    raise AssertionError('Inspector enabled writes')
            def api(self, method, path):
                calls.append((method, path))
                if method != 'GET' or path != '/v1/appAssetLibraryRefData':
                    raise AssertionError('Unexpected API call')
                return response
        namespace['module'].CLI = FakeCLI
        def no_media_or_targets(*args, **kwargs):
            raise AssertionError('Inspector touched media or app targets')
        namespace['module'].validate_media = no_media_or_targets
        namespace['module'].resolve_targets = no_media_or_targets
        output = io.StringIO()
        with contextlib.redirect_stdout(output):
            exec(compile(ast.Module(body=[program.body[-1]], type_ignores=[]), '<workflow-inspector>', 'exec'), namespace)
        return json.loads(output.getvalue()), calls

    def test_structural_fields_only_and_one_global_get(self):
        attrs = {
            'features': [{'featureId': 'APP_STORE_VERSIONS', 'placementPolicies': [{'placementType': 'APP_SCREENSHOT', 'groupLimits': [{'groupIds': ['IPHONE_DUO_PROFILE'], 'maxCount': 10, 'privateKey': 'PRIVATE'}]}]}],
            'placementProfileGroups': [{'placementProfileGroupId': 'IPHONE_DUO_PROFILE', 'platform': 'IPHONE_APP_STORE', 'displayClassId': 'IPHONE_DUO', 'url': 'https://PRIVATE.invalid'}],
            'placementTypes': [{'placementTypeId': 'APP_SCREENSHOT', 'acceptsAssetCategories': ['APP_SCREENSHOTS_AND_PREVIEWS'], 'specMappings': [{'placementGroupId': 'IPHONE_DUO_PROFILE', 'specs': ['spec-1']}]}],
            'imageSpecs': [{'specId': 'spec-1', 'dimensions': {'minWidth': 1398, 'maxWidth': 1398, 'minHeight': 2034, 'maxHeight': 2034, 'private': 'PRIVATE'}, 'aspectRatio': '3:4', 'compatiblePlacementTypes': ['APP_SCREENSHOT'], 'templateUrl': 'https://PRIVATE.invalid'}],
            'videoSpecs': [{'specId': 'video-1', 'frameRates': [{'minFps': 30, 'maxFps': 60}], 'duration': {'min': 'PT5S', 'max': 'PT30S'}, 'audioRequired': False}],
            'unknownField': 'PRIVATE', 'users': [{'email': 'PRIVATE'}], 'videoAsset': 'https://PRIVATE.invalid',
        }
        result, calls = self.run_inspector({'data': [{'id': 'PRIVATE-user-asset', 'attributes': attrs}], 'unknown': 'PRIVATE'})
        text = json.dumps(result)
        self.assertEqual(calls, [('GET', '/v1/appAssetLibraryRefData')])
        self.assertEqual(result['mode'], 'inspect-native-policy')
        self.assertEqual(result['referenceData'][0]['features'][0]['placementPolicies'][0]['groupLimits'][0]['maxCount'], 10)
        self.assertEqual(result['referenceData'][0]['videoSpecs'][0]['duration'], {'min': 'PT5S', 'max': 'PT30S'})
        self.assertNotIn('PRIVATE', text)
        self.assertNotIn('https', text)
        self.assertNotIn('unknown', text)
        self.assertNotIn('users', text)

    def test_malformed_present_values_fail_without_leaking_payload(self):
        cases = [
            {'features': 'PRIVATE'}, {'features': ['PRIVATE']},
            {'features': [{'placementPolicies': [{'groupLimits': [{'groupIds': ['https://PRIVATE.invalid']}]}]}]},
            {'imageSpecs': [{'specId': 'https://PRIVATE.invalid'}]},
            {'imageSpecs': [{'dimensions': {'minWidth': 'PRIVATE'}}]},
            {'imageSpecs': [{'dimensions': {'maxWidth': True}}]},
            {'imageSpecs': [{'dimensions': {'maxWidth': -1}}]},
            {'imageSpecs': [{'compatiblePlacementTypes': ['PRIVATE/URL']}]},
            {'videoSpecs': [{'duration': {'min': 'PT'}}]},
            {'videoSpecs': [{'duration': {'min': 'P1D2H'}}]},
            {'videoSpecs': [{'audioRequired': 'PRIVATE'}]},
            {'videoSpecs': [{'frameRates': [None]}]},
        ]
        cases += [{'imageSpecs': [{'aspectRatio': value}]} for value in (True, float('inf'), float('nan'), 10 ** 400, '0:3', '3:0', 'https://PRIVATE.invalid')]
        for attrs in cases:
            with self.subTest(attrs=attrs):
                with self.assertRaises(SystemExit) as error:
                    self.run_inspector({'data': [{'attributes': attrs}]})
                self.assertNotIn('PRIVATE', str(error.exception))
                self.assertNotIn('https', str(error.exception))

    def test_absent_optional_fields_and_unknown_fields_remain_safe(self):
        result, calls = self.run_inspector({'data': [{'attributes': {'unknown': 'PRIVATE'}}]})
        self.assertEqual(result['referenceData'], [{}])
        self.assertEqual(len(calls), 1)

    def test_decimal_and_numeric_aspect_ratios_are_preserved(self):
        for ratio in ('1.77778', '2', 1.77778, 2):
            with self.subTest(ratio=ratio):
                result, calls = self.run_inspector({'data': [{'attributes': {'imageSpecs': [{'specId': 'spec-1', 'aspectRatio': ratio}]}}]})
                self.assertEqual(result['referenceData'][0]['imageSpecs'][0]['aspectRatio'], ratio)
                self.assertEqual(len(calls), 1)

    def test_malformed_collection_fails_without_raw_payload(self):
        for response in (None, [], 'https://PRIVATE.invalid', {}, {'data': []}, {'data': [{}, {}]}, {'data': ['https://PRIVATE.invalid']}, {'data': [{'attributes': None}]}):
            with self.subTest(response=response):
                with self.assertRaises(SystemExit) as error:
                    self.run_inspector(response)
                self.assertNotIn('PRIVATE', str(error.exception))
                self.assertNotIn('https', str(error.exception))

if __name__ == '__main__':
    unittest.main()
