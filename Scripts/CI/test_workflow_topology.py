import itertools
import os
from pathlib import Path
import re
import subprocess
import textwrap
import unittest


WORKFLOW = Path(__file__).resolve().parents[2] / '.github/workflows/tests.yml'


def job_blocks(source):
    source = source.split('jobs:\n', 1)[1]
    matches = list(re.finditer(r'^  ([a-z_]+):\n', source, re.MULTILINE))
    return {
        match.group(1): source[match.end():matches[index + 1].start()
                               if index + 1 < len(matches) else len(source)]
        for index, match in enumerate(matches)
    }


class WorkflowTopologyTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.jobs = job_blocks(WORKFLOW.read_text())

    def test_native_and_tooling_depend_only_on_plan(self):
        self.assertEqual(set(self.jobs), {'plan', 'tooling', 'native', 'test'})
        for name in ('tooling', 'native'):
            self.assertRegex(self.jobs[name], r'^    needs: plan\n')
        self.assertIn("    if: needs.plan.outputs.xcode == 'true'\n", self.jobs['native'])
        self.assertIn('    runs-on: xcode-27\n', self.jobs['native'])
        self.assertIn('    runs-on: ubuntu-latest\n', self.jobs['tooling'])
        self.assertNotIn('needs:', self.jobs['plan'])

    def test_plan_records_decisions_before_parallel_work(self):
        plan = self.jobs['plan']
        for artifact in ('currency-release-request', 'currency-ci-plan'):
            self.assertIn(f'name: {artifact}\n', plan)
            self.assertNotIn(f'name: {artifact}\n', self.jobs['tooling'])
        self.assertIn("if: github.event_name == 'push'", plan)
        self.assertNotIn('python3 Scripts/CI/test_', plan)
        for flag in ('xcode', 'release', 'localizations', 'history', 'e2e', 'notes'):
            self.assertIn(f'{flag}: ${{{{ steps.changes.outputs.{flag} }}}}', plan)
        for flag in ('release', 'localizations', 'history', 'e2e', 'notes'):
            self.assertIn(f"needs.plan.outputs.{flag} == 'true'", self.jobs['tooling'])
        self.assertIn('python3 Scripts/CI/test_workflow_topology.py', self.jobs['tooling'])

    def test_required_gate_always_aggregates_all_jobs_on_linux(self):
        gate = self.jobs['test']
        self.assertIn('    needs: [plan, tooling, native]\n', gate)
        self.assertIn('    if: always()\n', gate)
        self.assertIn('    runs-on: ubuntu-latest\n', gate)
        for name in ('plan', 'tooling', 'native'):
            self.assertIn(f'{name.upper()}_RESULT: ${{{{ needs.{name}.result }}}}', gate)
        self.assertIn('XCODE_REQUIRED: ${{ needs.plan.outputs.xcode }}', gate)
        self.assertNotIn('id-token:', gate)
        self.assertNotIn('id-token:', self.jobs['plan'])
        self.assertNotIn('id-token:', self.jobs['tooling'])

    def test_simulator_starts_after_project_checks_without_blocking_test_build(self):
        native = self.jobs['native']
        start = native.index('      - name: Start test simulator\n')
        formatting = native.index('      - name: Check Swift formatting\n')
        structure = native.index('      - name: Check source navigator structure\n')
        tests = native.index('      - name: Test affected native targets\n')
        self.assertLess(formatting, structure)
        self.assertLess(structure, start)
        self.assertLess(start, tests)
        self.assertIn('xcrun simctl create', native[start:tests])
        self.assertIn('xcrun simctl boot "$simulator"', native[start:tests])
        self.assertNotIn('bootstatus', native)
        self.assertIn('if: steps.native.outputs.unit_tests', native[start:tests])
        self.assertIn('xcrun simctl delete "$CURRENCY_TEST_SIMULATOR"', native)

    def test_gate_rejects_missing_cancelled_failed_or_skipped_required_work(self):
        script = textwrap.dedent(self.jobs['test'].split('        run: |\n', 1)[1])
        results = ('success', 'failure', 'cancelled', 'skipped')
        for plan, tooling, native, xcode in itertools.product(results, results, results, ('true', 'false', '')):
            with self.subTest(plan=plan, tooling=tooling, native=native, xcode=xcode):
                result = subprocess.run(
                    ['bash', '-e', '-c', script],
                    env=dict(os.environ, PLAN_RESULT=plan, TOOLING_RESULT=tooling,
                             NATIVE_RESULT=native, XCODE_REQUIRED=xcode),
                    capture_output=True, text=True,
                )
                expected = plan == tooling == 'success' and (
                    (xcode == 'true' and native == 'success') or
                    (xcode == 'false' and native == 'skipped')
                )
                self.assertEqual(result.returncode == 0, expected, result.stderr)


if __name__ == '__main__':
    unittest.main()
