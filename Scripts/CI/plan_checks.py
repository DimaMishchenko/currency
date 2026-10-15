import argparse
from collections import defaultdict
import json
import os
from pathlib import Path, PurePosixPath
import re
import subprocess


FLAGS = ('xcode', 'publish', 'full', 'unit_tests', 'app', 'watch', 'intents',
         'harnesses', 'e2e', 'history', 'release', 'notes', 'localizations',
         'swift_format', 'structure')
NATIVE_FLAGS = ('unit_tests', 'app', 'watch', 'intents', 'harnesses')
TOOL_FLAGS = ('e2e', 'history', 'release', 'notes', 'localizations', 'swift_format', 'structure')
POLICY = {'Scripts/CI/changes.sh', 'Scripts/CI/plan_checks.py',
          'Scripts/CI/test_plan_checks.py', 'Scripts/CI/test_skip_rules.py',
          '.github/workflows/tests.yml', '.github/workflows/cache.yml',
          'Scripts/CI/run_native_checks.sh', 'Scripts/CI/test_native_checks.py',
          'Scripts/CI/check_swift_format.sh',
          'Scripts/CI/check_project_structure.py', 'Scripts/CI/test_project_structure.py'}
RELEASE = {'Scripts/CI/signing.sh', 'Scripts/CI/profile_name.sh',
           'Scripts/CI/release.sh', 'Scripts/CI/verify_ipa.sh',
           '.github/workflows/publish.yml'}
MODULE_README = re.compile(r'^(App|DesignSystem|Domain/[^/]+|Features/[^/]+|App/Modules/[^/]+|Apps/[^/]+|Apps/[^/]+/App|Apps/[^/]+/Modules/[^/]+|AppExtensions/[^/]+|Foundation/[^/]+)/README\.md$')
TEST_PATH = re.compile(r'^(App/Tests/|App/Modules/[^/]+/Tests/|Apps/[^/]+/Tests/|Apps/[^/]+/Modules/[^/]+/Tests/|AppExtensions/[^/]+/Tests/|Foundation/[^/]+/Tests/|(DesignSystem|Domain/[^/]+|Features/[^/]+)/Tests/|(Domain/[^/]+|Features/[^/]+)/HarnessApp/)')


def classify(paths, missing=False, force_full=False):
    plan = {key: False for key in FLAGS}
    plan.update(harness_targets=[], changed_files=paths, reasons=[])
    native = []
    broad = missing
    if missing:
        plan['publish'] = True
        plan['reasons'].append('Base history unavailable; validate conservatively')
    for path in paths:
        if path.startswith('Apps/Currency/Tests/E2E/'):
            if not path.endswith('.md'):
                plan['e2e'] = True
            continue
        if path in POLICY:
            broad = True
            continue
        if path == 'Scripts/CI/testflight_notes.py':
            plan['publish'] = True
            plan['notes'] = True
            continue
        if path in RELEASE:
            plan['release'] = plan['publish'] = True
            broad = True
            continue
        if path.startswith('Scripts/History/') or path == '.github/workflows/history-refresh.yml':
            plan['history'] = not path.endswith('.md') or plan['history']
            continue
        if path in ('Scripts/CI/check_localizations.py', 'Scripts/CI/test_check_localizations.py'):
            plan['localizations'] = True
            continue
        if path in ('Scripts/CI/check_release_signing.py', 'Scripts/CI/test_release_configuration.py'):
            plan['release'] = True
            continue
        if path == 'Scripts/CI/test_testflight_notes.py':
            plan['notes'] = True
            continue
        if path in ('Scripts/CI/public_beta.sh', 'Scripts/CI/resolve_release.sh'):
            continue
        if path.startswith('Scripts/CI/'):
            broad = True
            plan['reasons'].append('Unknown CI helper; full validation selected')
            continue
        if path == '.swift-format':
            plan['swift_format'] = True
            broad = True
            continue
        if path.startswith('Tools/SimulatorWidgets/'):
            broad = True
            continue
        if path.startswith(('Documentation/', '.github/')) or path in ('README.md', 'LICENSE', '.gitignore', 'AGENTS.md') or MODULE_README.match(path):
            continue
        native.append(path)
        plan['xcode'] = True
        plan['structure'] = True
        if path.endswith('.swift'):
            plan['swift_format'] = True
        if path.endswith('.xcstrings') or (path.endswith('.swift') and not TEST_PATH.match(path)):
            plan['localizations'] = True
        if not TEST_PATH.match(path):
            plan['publish'] = True
        if path in ('.mise.toml', 'Project.swift', 'Tuist.swift', 'Package.swift', 'Package.resolved') or path.startswith('Tuist/') or path.endswith(('/Package.swift', '/Package.resolved', '/Project.swift')):
            broad = True
    plan['xcode'] |= broad
    plan['full'] = broad or (force_full and plan['xcode'])
    if plan['full']:
        for key in TOOL_FLAGS:
            plan[key] = True
        plan['reasons'].append('Full validation required by history, configuration or fallback policy')
    elif native:
        plan['reasons'].append('Native membership selects job groups; Tuist selects unit tests')
    else:
        plan['reasons'].append('No native changes; native checks skipped')
    return plan, native


def path_strings(value):
    if isinstance(value, dict):
        for key, item in value.items():
            if key == 'path' and isinstance(item, str):
                yield item
            else:
                yield from path_strings(item)
    elif isinstance(value, list):
        for item in value:
            yield from path_strings(item)


class Graph:
    def __init__(self, data):
        projects = data['projects']
        if not isinstance(projects, list) or len(projects) % 2:
            raise ValueError('Invalid graph projects')
        self.targets = {}
        self.files = defaultdict(set)
        self.roots = defaultdict(set)
        self.excluded = defaultdict(set)
        self.reverse = defaultdict(set)
        root = data.get('path', projects[0] if projects else '')
        if not isinstance(root, str) or not root:
            raise ValueError('Graph has no repository root')
        self.root = PurePosixPath(root)
        for project in projects[1::2]:
            self.targets.update(project['targets'])
        if not self.targets:
            raise ValueError('Graph has no targets')
        for name, target in self.targets.items():
            if not re.fullmatch(r'[A-Za-z_][A-Za-z0-9_]*', name):
                raise ValueError('Unsafe graph target name')
            for dependency in target.get('dependencies', []):
                dep = dependency.get('target', {}).get('name')
                if dep:
                    if dep not in self.targets:
                        raise ValueError('Graph target dependency missing')
                    self.reverse[dep].add(name)
            for key in ('sources', 'resources', 'coreDataModels', 'infoPlist', 'entitlements'):
                for path in path_strings(target.get(key, [])):
                    self.add_file(path, name)
            for folder in target.get('buildableFolders', []):
                self.roots[self.relative(folder['path'])].add(name)
                for path in path_strings(folder.get('resolvedFiles', [])):
                    self.add_file(path, name)
                for exception in folder.get('exceptions', {}).get('exceptions', []):
                    other = exception.get('target', name)
                    if other not in self.targets:
                        raise ValueError('Unknown exception target')
                    for path in exception.get('included', []):
                        self.add_file(path, other, infer_root=False)
                    for path in exception.get('excluded', []):
                        self.excluded[self.relative(path)].add(other)
        if not self.files and not self.roots:
            raise ValueError('Graph has no file membership')

    def relative(self, path):
        path = PurePosixPath(path)
        return str(path.relative_to(self.root)) if path.is_absolute() else str(path)

    def add_file(self, path, name, infer_root=True):
        path = self.relative(path)
        self.files[path].add(name)
        if not infer_root:
            return
        parts = PurePosixPath(path).parts
        for marker in ('Sources', 'Tests', 'HarnessApp', 'Resources', 'Configuration'):
            if marker in parts:
                index = parts.index(marker)
                depth = index + (2 if marker in ('Sources', 'Tests') and len(parts) > index + 2 else 1)
                self.roots[str(PurePosixPath(*parts[:depth]))].add(name)
                break

    def owners(self, path):
        result = set(self.files.get(path, ()))
        matching = [(root, owners) for root, owners in self.roots.items() if path == root or path.startswith(root + '/')]
        for _, owners in matching:
            result.update(owners)
        for file, owners in self.files.items():
            if path.startswith(file + '/'):
                result.update(owners)
        for excluded, owners in self.excluded.items():
            if path == excluded or path.startswith(excluded + '/'):
                result.difference_update(owners)
        return result

    def closure(self, selected):
        selected = set(selected)
        pending = list(selected)
        while pending:
            for dependent in self.reverse[pending.pop()] - selected:
                selected.add(dependent)
                pending.append(dependent)
        return selected

    def select(self, plan, paths):
        affected = set()
        for path in paths:
            owners = self.owners(path)
            if not owners:
                plan['full'] = True
                plan['reasons'].append('Unmapped native path; full graph validation selected')
            affected.update(owners)
        selected = set(self.targets) if plan['full'] else self.closure(affected)
        if plan['full']:
            for key in TOOL_FLAGS:
                plan[key] = True
        plan['harness_targets'] = sorted(n for n in selected if n.endswith('Harness') and self.targets[n]['product'] == 'app')
        plan['unit_tests'] = any(self.targets[name]['product'] == 'unit_tests' for name in selected)
        plan['harnesses'] = bool(plan['harness_targets'])
        plan['app'] = 'Currency' in selected
        plan['watch'] = 'CurrencyWatch' in selected
        plan['intents'] = 'NativeIntentTests' in selected


def changed_paths(base):
    valid = base and not re.fullmatch('0+', base)
    if valid:
        valid = subprocess.run(['git', 'cat-file', '-e', base + '^{commit}'], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode == 0
    if not valid:
        return [], True
    output = subprocess.check_output(['git', 'diff', '--no-renames', '--name-only', '-z', base, 'HEAD'])
    return [os.fsdecode(path) for path in output.split(b'\0') if path], False


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('base', nargs='?', default='')
    parser.add_argument('--graph', type=Path)
    parser.add_argument('--full', action='store_true')
    args = parser.parse_args()
    paths, missing = changed_paths(args.base)
    plan, native = classify(paths, missing, args.full)
    if plan['xcode']:
        if args.graph:
            try:
                Graph(json.loads(args.graph.read_text())).select(plan, native)
            except (ValueError, KeyError, TypeError, OSError) as error:
                raise SystemExit(f'Cannot safely select native validation from graph: {error}') from error
        else:
            for key in NATIVE_FLAGS:
                plan[key] = True
    destination = Path(os.environ.get('RUNNER_TEMP', '/tmp'))
    destination.mkdir(parents=True, exist_ok=True)
    (destination / 'CurrencyCIPlan.json').write_text(json.dumps(plan, indent=2, ensure_ascii=True) + '\n')
    (destination / 'ShouldPublish.txt').write_text(str(plan['publish']).lower() + '\n')
    lines = [f'{key}={str(plan[key]).lower()}' for key in FLAGS]
    lines.append('harness_targets=' + ' '.join(plan['harness_targets']))
    with open(os.environ['GITHUB_OUTPUT'], 'a') as output:
        output.write('\n'.join(lines) + '\n')
    with open(os.environ['GITHUB_STEP_SUMMARY'], 'a') as summary:
        summary.write('### Validation plan\n\n')
        summary.write('Selected: ' + ', '.join(key for key in FLAGS if plan[key]) + '\n\n')
        summary.write('Skipped: ' + ', '.join(key for key in FLAGS if not plan[key]) + '\n\n')
        for reason in plan['reasons']:
            summary.write('- ' + reason + '\n')
        if plan['unit_tests']:
            summary.write('- Unit suites: selected by Tuist from CurrencyTests\n')
        if plan['harness_targets']:
            summary.write('- harness_targets: ' + ', '.join(plan['harness_targets']) + '\n')


if __name__ == '__main__':
    main()
