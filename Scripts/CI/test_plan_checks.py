import importlib.util
import json
import os
from pathlib import Path
import unittest


SCRIPT = Path(__file__).with_name('plan_checks.py')
SPEC = importlib.util.spec_from_file_location('plan_checks', SCRIPT)
planner = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(planner)


def target(product, folder, dependencies=()):
    return {'product': product,
            'buildableFolders': [{'path': '/repo/' + folder,
                                  'resolvedFiles': [{'path': '/repo/' + folder + '/Existing.swift'}]}],
            'dependencies': [{'target': {'name': name}} for name in dependencies]}


def fixture():
    targets = {
        'Core': target('staticFramework', 'Domain/Core/Sources/Core'),
        'UI': target('staticFramework', 'Features/UI/Sources/UI', ['Core']),
        'CoreTests': target('unit_tests', 'Domain/Core/Tests/CoreTests', ['Core']),
        'UITests': target('unit_tests', 'Features/UI/Tests/UITests', ['UI']),
        'UIHarness': target('app', 'Features/UI/HarnessApp', ['UI']),
        'Currency': target('app', 'Apps/Currency/App/Sources', ['UI']),
        'CurrencyWatch': target('app', 'Apps/CurrencyWatch/App/Sources', ['Core']),
        'NativeIntentTests': target('ui_tests', 'Apps/Currency/Tests/NativeIntentTests', ['Currency']),
    }
    targets['Currency']['buildableFolders'][0]['exceptions'] = {
        'exceptions': [{'target': 'CurrencyWatch', 'included': ['/repo/Apps/Currency/App/Sources/Shared.swift']}]}
    return {'path': '/repo', 'projects': ['/repo', {'targets': targets}]}


class PlannerTests(unittest.TestCase):
    def plan(self, paths, full=False, missing=False, data=None):
        plan, native = planner.classify(paths, missing, full)
        if plan['xcode']:
            planner.Graph(data or fixture()).select(plan, native)
        return plan

    def test_plan_does_not_choose_unit_suite_names(self):
        for paths in ([], ['Features/UI/Tests/UITests/Existing.swift'], ['Domain/Core/Sources/Core/Existing.swift']):
            plan = self.plan(paths)
            self.assertNotIn('test_targets', plan)

    def test_transitive_production_dependencies(self):
        plan = self.plan(['Domain/Core/Sources/Core/Existing.swift'])
        self.assertTrue(plan['unit_tests'])
        self.assertEqual(plan['harness_targets'], ['UIHarness'])
        for key in ('app', 'watch', 'intents', 'publish', 'localizations', 'structure'):
            self.assertTrue(plan[key], key)
        self.assertFalse(plan['full'])

    def test_new_and_deleted_sources_use_folder_membership(self):
        for path in ('Domain/Core/Sources/Core/New.swift', 'Domain/Core/Sources/Core/Deleted.swift'):
            with self.subTest(path=path):
                self.assertTrue(self.plan([path])['unit_tests'])

    def test_tests_and_harness_do_not_select_host(self):
        plan = self.plan(['Features/UI/Tests/UITests/Existing.swift'])
        self.assertTrue(plan['unit_tests'])
        for key in ('publish', 'app', 'watch', 'intents', 'harnesses'):
            self.assertFalse(plan[key], key)
        plan = self.plan(['Features/UI/HarnessApp/New.swift'])
        self.assertEqual(plan['harness_targets'], ['UIHarness'])
        self.assertFalse(plan['unit_tests'])
        self.assertFalse(plan['app'])
        self.assertFalse(plan['publish'])

    def test_unknown_ci_helper_is_full_and_known_helpers_remain_cheap(self):
        for path in ('Scripts/CI/new_helper.sh', 'Scripts/CI/new_localizations_check.py'):
            plan = self.plan([path])
            self.assertTrue(plan['full'])
            self.assertFalse(plan['publish'])
        for path in ('Scripts/CI/resolve_release.sh', 'Scripts/CI/public_beta.sh'):
            self.assertFalse(self.plan([path])['xcode'])

    def test_shared_folder_memberships_and_exclusions(self):
        data = fixture()
        folders = data['projects'][1]['targets']['Currency']['buildableFolders']
        folders[0]['exceptions']['exceptions'].append({
            'target': 'Currency', 'excluded': ['/repo/Apps/Currency/App/Sources/Shared.swift']})
        graph = planner.Graph(data)
        self.assertEqual(graph.owners('Apps/Currency/App/Sources/Shared.swift'), {'CurrencyWatch'})
        self.assertEqual(graph.owners('Apps/Currency/App/Sources/New.swift'), {'Currency'})
        data['projects'][1]['targets']['UI']['buildableFolders'].append({
            'path': '/repo/Apps/Currency/App/Sources/Nested', 'resolvedFiles': []})
        graph = planner.Graph(data)
        self.assertEqual(graph.owners('Apps/Currency/App/Sources/Nested/New.swift'), {'Currency', 'UI'})
        plan = self.plan(['Apps/Currency/App/Sources/Shared.swift'], data=data)
        self.assertTrue(plan['watch'])
        self.assertFalse(plan['app'])

    def test_shared_exception_membership(self):
        plan = self.plan(['Apps/Currency/App/Sources/Shared.swift'])
        self.assertTrue(plan['watch'])
        self.assertTrue(plan['app'])
        self.assertTrue(plan['intents'])

    def test_e2e_markdown_and_docs(self):
        plan = self.plan(['Apps/Currency/Tests/E2E/tests/home.e2e.ts'])
        self.assertTrue(plan['e2e'])
        self.assertFalse(plan['xcode'])
        self.assertFalse(plan['publish'])
        for path in ('Apps/Currency/Tests/E2E/README.md', 'Documentation/FeatureMap.md', 'Features/UI/README.md'):
            plan = self.plan([path], full=True)
            self.assertFalse(any(plan[key] for key in planner.FLAGS), path)

    def test_unknown_history_toolchain_manifests_full(self):
        for path in ('unknown/file', 'Project.swift', '.mise.toml', 'Tuist/Package.resolved'):
            with self.subTest(path=path):
                plan = self.plan([path])
                self.assertTrue(plan['full'])
                self.assertTrue(plan['publish'])
                self.assertTrue(plan['unit_tests'])
                self.assertTrue(all(plan[key] for key in planner.TOOL_FLAGS))
        plan = self.plan([], missing=True)
        self.assertTrue(plan['full'])
        self.assertTrue(plan['publish'])

    def test_policy_full_without_publication(self):
        for path in planner.POLICY:
            plan = self.plan([path])
            self.assertTrue(plan['full'])
            self.assertFalse(plan['publish'])
            self.assertTrue(all(plan[key] for key in planner.TOOL_FLAGS))

    def test_main_full_and_release_independence(self):
        plan = self.plan(['Features/UI/Sources/UI/New.swift'], full=True)
        self.assertTrue(plan['full'])
        self.assertTrue(plan['watch'])
        plan = self.plan(['Scripts/CI/test_release_configuration.py'])
        self.assertTrue(plan['release'])
        self.assertFalse(plan['xcode'])
        self.assertFalse(plan['publish'])
        plan = self.plan(['Scripts/CI/testflight_notes.py'])
        self.assertTrue(plan['notes'])
        self.assertTrue(plan['publish'])
        self.assertFalse(plan['xcode'])
        plan = self.plan(['Scripts/History/generate_archive.py'])
        self.assertTrue(plan['history'])
        self.assertFalse(plan['publish'])
        self.assertFalse(plan['xcode'])

    def test_missing_graph_coarse_and_invalid_graph_fails(self):
        plan, _ = planner.classify(['Domain/Core/Sources/Core/New.swift'])
        self.assertTrue(plan['xcode'])
        with self.assertRaises((ValueError, KeyError, TypeError)):
            planner.Graph({'projects': []})
        data = fixture()
        data['projects'][1]['targets']['Bad;name'] = target('unit_tests', 'Tests')
        with self.assertRaises(ValueError):
            planner.Graph(data)

    def test_explicit_sources_resources_and_deleted_files(self):
        data = fixture()
        core = data['projects'][1]['targets']['Core']
        core['buildableFolders'] = []
        core['sources'] = [{'path': '/repo/Domain/Core/Sources/Core/Existing.swift'}]
        core['resources'] = {'resources': [{'file': {'path': '/repo/Domain/Core/Resources/Data.json'}}]}
        for path in ('Domain/Core/Sources/Core/Deleted.swift', 'Domain/Core/Resources/New.json'):
            self.assertTrue(self.plan([path], data=data)['unit_tests'])

    def test_real_graph_shape_when_available(self):
        graph_path = os.environ.get('CURRENCY_CI_GRAPH')
        sample = Path(graph_path) if graph_path else SCRIPT.parents[2] / '.validation/selective-ci/graph.json'
        if graph_path:
            self.assertTrue(sample.is_file(), 'CURRENCY_CI_GRAPH must name an exported Tuist graph')
        if not sample.exists():
            self.skipTest('Local Tuist graph sample unavailable')
        data = json.loads(sample.read_text())
        full = self.plan([], missing=True, data=data)
        self.assertTrue(all(full[key] for key in planner.NATIVE_FLAGS))
        self.assertNotIn('test_targets', full)
        plan = self.plan(['Domain/Conversion/Sources/Conversion/ExactAmount.swift'], data=data)
        self.assertTrue(plan['unit_tests'])
        self.assertTrue(plan['app'])
        self.assertTrue(plan['watch'])
        plan = self.plan(['Apps/Currency/Tests/NativeIntentTests/NativeIntentTests.swift'], data=data)
        self.assertTrue(plan['intents'])
        self.assertFalse(plan['app'])
        self.assertFalse(plan['unit_tests'])


if __name__ == '__main__':
    unittest.main()
