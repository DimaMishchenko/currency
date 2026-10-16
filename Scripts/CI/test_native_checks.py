import json
import os
from pathlib import Path
import subprocess
import tempfile
import textwrap
import unittest
from unittest.mock import patch

from cache_toolchain import SDKS, cache_toolchain


SCRIPT = Path(__file__).with_name('run_native_checks.sh').resolve()


class CacheToolchainTests(unittest.TestCase):
    def identity(self, xcode='Xcode 27.1\nBuild version 27B501', sdk_build='24B501'):
        with patch('cache_toolchain.subprocess.check_output') as command:
            command.side_effect = lambda args, **kwargs: xcode if args[0] == 'xcodebuild' else sdk_build
            result = cache_toolchain()
            self.assertEqual(command.call_args_list[0].args[0], ('xcodebuild', '-version'))
            self.assertEqual([call.args[0][2] for call in command.call_args_list[1:]], list(SDKS))
            return result

    def test_same_toolchain_has_stable_identity(self):
        self.assertEqual(self.identity(), self.identity())
        self.assertRegex(self.identity(), r'^[a-f0-9]{64}$')

    def test_xcode_and_sdk_builds_each_change_identity(self):
        baseline = self.identity()
        self.assertNotEqual(baseline, self.identity(xcode='Xcode 27.1\nBuild version 27B502'))
        self.assertNotEqual(baseline, self.identity(sdk_build='24B502'))

    def test_toolchain_query_failure_is_fatal(self):
        with patch('cache_toolchain.subprocess.check_output', side_effect=subprocess.CalledProcessError(1, 'xcrun')):
            with self.assertRaises(subprocess.CalledProcessError):
                cache_toolchain()

    def test_warming_and_consuming_export_same_identity_before_tuist(self):
        root = SCRIPT.parents[2]
        command = 'identity=$(python3 Scripts/CI/cache_toolchain.py)'
        for name in ('tests.yml', 'cache.yml'):
            workflow = (root / '.github/workflows' / name).read_text()
            with self.subTest(workflow=name):
                self.assertEqual(workflow.count(command), 1)
                self.assertLess(workflow.index(command), workflow.index('tuist install'))
        project = (root / 'Project.swift').read_text()
        self.assertIn('Environment.currencyCacheToolchain', project)
        self.assertIn('"CURRENCY_CACHE_TOOLCHAIN"', project)

    def test_toolchain_query_failure_stops_workflow_before_export(self):
        root = SCRIPT.parents[2]
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory)
            executable = path / 'python3'
            executable.write_text('#!/bin/sh\nexit 17\n')
            executable.chmod(0o755)
            environment_file = path / 'environment'
            for name in ('tests.yml', 'cache.yml'):
                workflow = (root / '.github/workflows' / name).read_text()
                step = workflow.split('      - name: Identify cache toolchain\n', 1)[1]
                run = textwrap.dedent(step.split('        run: |\n', 1)[1].split('      - ', 1)[0])
                with self.subTest(workflow=name):
                    result = subprocess.run(['bash', '-e', '-c', run], capture_output=True,
                                            env={**os.environ, 'PATH': directory + os.pathsep + os.environ['PATH'],
                                                 'GITHUB_ENV': str(environment_file)})
                    self.assertEqual(result.returncode, 17, result.stderr)
                    self.assertFalse(environment_file.exists())


class NativeChecksTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.commands = self.root / 'commands.jsonl'
        self.summary = self.root / 'summary.md'
        self.plan = {'full': False, 'harness_targets': ['ConverterHarness']}
        for command in ('tuist', 'xcodebuild', 'xcbeautify'):
            executable = self.root / command
            executable.write_text('''#!/usr/bin/env python3
import json
import os
from pathlib import Path
import sys

name = Path(sys.argv[0]).name
with open(os.environ['COMMAND_LOG'], 'a') as output:
    output.write(json.dumps({'name': name, 'args': sys.argv[1:], 'environment': {
        key: value for key, value in os.environ.items() if key.startswith('TUIST_CURRENCY_')
    }}) + '\\n')
if name == 'xcbeautify':
    sys.stdout.write(sys.stdin.read())
else:
    print(name + ' standard output')
    print(name + ' diagnostic output', file=sys.stderr)
if name == os.environ.get('FAIL_COMMAND'):
    sys.exit(17)
''')
            executable.chmod(0o755)
        self.environment = {**os.environ, 'RUNNER_TEMP': str(self.root),
                            'PATH': str(self.root) + os.pathsep + os.environ['PATH'],
                            'GITHUB_STEP_SUMMARY': str(self.summary),
                            'CURRENCY_TEST_SIMULATOR': 'owned-device-123',
                            'COMMAND_LOG': str(self.commands)}
        self.environment.pop('CURRENCY_TUIST_UPLOAD', None)

    def run_phase(self, phase, **environment):
        (self.root / 'CurrencyCIPlan.json').write_text(json.dumps(self.plan))
        result = subprocess.run(['bash', str(SCRIPT), phase], cwd=self.root,
                                env={**self.environment, **environment}, text=True,
                                capture_output=True, timeout=10)
        calls = [json.loads(line) for line in self.commands.read_text().splitlines()] if self.commands.exists() else []
        return result, [call for call in calls if call['name'] != 'xcbeautify']

    def test_pull_request_unit_checks_delegate_selection_to_tuist_and_use_owned_device(self):
        result, calls = self.run_phase('unit')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(len(calls), 1)
        command = calls[0]
        self.assertEqual(command['args'][:2], ['test', 'CurrencyTests'])
        for flag in ('--skip-quarantine', '--selective-testing', '--binary-cache', '--no-upload'):
            self.assertIn(flag, command['args'])
        self.assertEqual(command['environment'], {
            'TUIST_CURRENCY_CI_CACHE': 'true',
            'TUIST_CURRENCY_CI_CLOUD': 'false',
            'TUIST_CURRENCY_CI_HARNESS_TARGETS': 'ConverterHarness'})
        self.assertIn('platform=iOS Simulator,id=owned-device-123', command['args'])
        passthrough = command['args'].index('--')
        self.assertGreater(command['args'].index('-destination'), passthrough)
        self.assertIn(str(self.root / 'CurrencyUnitTests.xcresult'), command['args'])
        self.assertIn('diagnostic output', (self.root / 'CurrencyUnitTests.log').read_text())
        self.assertIn('including generation and build', self.summary.read_text())

    def test_full_validation_disables_selective_testing_and_binary_cache(self):
        self.plan['full'] = True
        result, calls = self.run_phase('unit', CURRENCY_TUIST_UPLOAD='true')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('--no-selective-testing', calls[0]['args'])
        self.assertIn('--no-binary-cache', calls[0]['args'])
        self.assertNotIn('--no-upload', calls[0]['args'])
        self.assertEqual(calls[0]['environment']['TUIST_CURRENCY_CI_CLOUD'], 'true')
        self.assertEqual(calls[0]['environment']['TUIST_CURRENCY_CI_CACHE'], 'false')

    def test_real_test_failure_propagates_without_retry(self):
        result, calls = self.run_phase('unit', FAIL_COMMAND='tuist')
        self.assertEqual(result.returncode, 17)
        self.assertEqual(len(calls), 1)
        self.assertIn('| 17 |', self.summary.read_text())

    def test_formatter_failure_propagates(self):
        result, calls = self.run_phase('app', FAIL_COMMAND='xcbeautify')
        self.assertEqual(result.returncode, 17)
        self.assertEqual([call['name'] for call in calls], ['tuist'])

    def test_non_unit_builds_regenerate_the_selected_graph(self):
        for phase, scheme, platform in [('app', 'Currency', 'iOS'),
                                         ('watch', 'CurrencyWatch', 'watchOS'),
                                         ('harnesses', 'CurrencyHarnesses', 'iOS')]:
            with self.subTest(phase=phase):
                self.commands.unlink(missing_ok=True)
                result, calls = self.run_phase(phase)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(calls[0]['args'], ['generate', '--no-open', '--cache-profile', 'all-possible'])
                self.assertEqual(calls[1]['name'], 'xcodebuild')
                self.assertEqual(calls[1]['args'][0], 'build')
                self.assertIn(scheme, calls[1]['args'])
                self.assertIn(f'generic/platform={platform} Simulator', calls[1]['args'])
                self.assertIn(str(self.root / 'CurrencyTestsDerivedData'), calls[1]['args'])

    def test_full_generation_uses_source_graph(self):
        self.plan['full'] = True
        result, calls = self.run_phase('app')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(calls[0]['args'][-1], 'none')

    def test_intent_tests_preserve_serial_execution_timeouts_and_diagnostics(self):
        result, calls = self.run_phase('intents')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(len(calls), 2)
        args = calls[1]['args']
        self.assertEqual(args[0], 'test')
        self.assertIn('NativeIntentTests', args)
        for flag, value in [('-parallel-testing-enabled', 'NO'),
                            ('-test-timeouts-enabled', 'YES'),
                            ('-default-test-execution-time-allowance', '120'),
                            ('-maximum-test-execution-time-allowance', '120'),
                            ('-destination', 'platform=iOS Simulator,id=owned-device-123')]:
            self.assertEqual(args[args.index(flag) + 1], value)
        self.assertIn(str(self.root / 'CurrencyNativeIntents.xcresult'), args)
        self.assertIn('diagnostic output', (self.root / 'CurrencyNativeIntents.log').read_text())

    def test_missing_owned_simulator_and_malformed_plan_fail_before_commands(self):
        self.environment.pop('CURRENCY_TEST_SIMULATOR')
        result, calls = self.run_phase('unit')
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(calls, [])
        self.plan['harness_targets'] = 'ConverterHarness'
        result, calls = self.run_phase('app')
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(calls, [])

    def test_post_build_session_timing_excludes_build_and_preserves_test_failure(self):
        executable = self.root / 'xcrun'
        executable.write_text('''#!/usr/bin/env python3
import json
import os
import sys

with open(os.environ['COMMAND_LOG'], 'a') as output:
    output.write(json.dumps({'name': 'xcrun', 'args': sys.argv[1:]}) + '\\n')
if sys.argv[1:5] == ['xcresulttool', 'get', 'test-results', 'summary']:
    print(json.dumps({'startTime': 1000, 'finishTime': 1040,
                      'passedTests': 3, 'failedTests': 0, 'skippedTests': 0}))
elif sys.argv[1:5] == ['xcresulttool', 'get', 'log', '--type'] and sys.argv[5] == 'build':
    print(json.dumps({'startTime': 1005, 'duration': 10}))
else:
    sys.exit(2)
''')
        executable.chmod(0o755)
        (self.root / 'CurrencyUnitTests.xcresult').mkdir()
        for fail_command, expected_status in [('', 0), ('tuist', 17)]:
            with self.subTest(failed_command=fail_command):
                self.commands.unlink(missing_ok=True)
                self.summary.unlink(missing_ok=True)
                result, calls = self.run_phase('unit', FAIL_COMMAND=fail_command)
                self.assertEqual(result.returncode, expected_status, result.stderr)
                self.assertEqual(len([call for call in calls if call['name'] == 'tuist']), 1)
                self.assertEqual(len([call for call in calls if call['name'] == 'xcrun']), 2)
                self.assertIn('Build: 10.0s; post-build test session: 25.0s; '
                              '3 passed, 0 failed, 0 skipped.', self.summary.read_text())
                for extension in ('summary.json', 'build.json'):
                    self.assertTrue((self.root / f'CurrencyUnitTests.xcresult.{extension}').exists())

    def test_native_test_failure_is_not_retried(self):
        result, calls = self.run_phase('intents', FAIL_COMMAND='xcodebuild')
        self.assertEqual(result.returncode, 17)
        self.assertEqual(len([call for call in calls if call['name'] == 'xcodebuild']), 1)
        self.assertTrue((self.root / 'CurrencyNativeIntents.log').exists())


if __name__ == '__main__':
    unittest.main()
