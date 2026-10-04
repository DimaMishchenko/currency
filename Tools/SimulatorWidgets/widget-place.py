#!/usr/bin/env python3
"""Ensure one persisted Home Screen widget on an explicitly booted iOS simulator."""
import argparse
from collections import Counter
import hashlib
import fcntl
import json
import math
import os
import platform
from pathlib import Path
import plistlib
import re
import subprocess
import sys
import time
import uuid

ROOT = Path(__file__).resolve().parent
PROTOCOL = 1
SIZES = {'small', 'medium', 'large'}
RESULT = {}

def command(args, timeout=15):
    started = time.monotonic()
    proc = subprocess.run(args, text=True, capture_output=True, timeout=timeout)
    if proc.returncode:
        raise RuntimeError(f"{' '.join(args)} failed ({proc.returncode}): {(proc.stderr or proc.stdout).strip()}")
    return proc.stdout, time.monotonic() - started

def sim(udid, *args, timeout=15):
    return command(['xcrun', 'simctl', 'spawn', udid, *args], timeout)

def reject_json_constant(value):
    raise ValueError(f'Invalid JSON numeric constant: {value}')

def read_json(path):
    try:
        return json.loads(path.read_text(), parse_constant=reject_json_constant)
    except (OSError, ValueError):
        return None

def atomic_json(path, payload):
    temp = path.with_name(path.name + '.' + uuid.uuid4().hex + '.tmp')
    temp.write_text(json.dumps(payload) + '\n')
    os.replace(temp, path)

def heartbeat(session):
    value = read_json(session / 'heartbeat.json')
    if not isinstance(value, dict) or value.get('udid') != session.name:
        return None
    stamp = value.get('timestamp')
    pid = value.get('pid')
    if type(stamp) not in {int, float} or not math.isfinite(stamp) or type(pid) is not int:
        return None
    try:
        if abs(time.time() - stamp) > 3 or pid < 1:
            return None
        os.kill(int(pid), 0)
    except (ValueError, TypeError, OSError):
        return None
    return value

def prepare_directory(path):
    path = path.expanduser().absolute()
    if path.is_symlink():
        raise ValueError(f'State directory must not be a symlink: {path}')
    path.mkdir(parents=True, exist_ok=True, mode=0o700)
    info = path.stat()
    if info.st_uid != os.getuid() or info.st_mode & 0o022:
        raise ValueError(f'State directory must be owned by this user and not writable by others: {path}')
    return path.resolve()

def select_booted_device(devices, requested):
    matches = [device for device in devices if device.get('udid', '').upper() == requested]
    if len(matches) != 1 or matches[0].get('state') != 'Booted' or matches[0].get('isAvailable') is False:
        raise RuntimeError('The explicitly requested simulator must already be available and booted')
    return matches[0]

def target_identity(listing, runtimes, requested, architecture=None):
    identifiers = [identifier for identifier, devices in listing['devices'].items()
                   if any(device.get('udid', '').upper() == requested for device in devices)]
    if len(identifiers) != 1:
        raise ValueError('Requested device must belong to exactly one runtime')
    runtime = next((item for item in runtimes['runtimes'] if item.get('identifier') == identifiers[0]), None)
    if not runtime or not identifiers[0].startswith('com.apple.CoreSimulator.SimRuntime.iOS-'):
        raise ValueError('Only iOS simulator runtimes are supported')
    architecture = architecture or platform.machine()
    if architecture not in {'arm64', 'x86_64'}:
        raise ValueError(f'Unsupported simulator architecture: {architecture}')
    supported = runtime.get('supportedArchitectures')
    if supported is not None and (not isinstance(supported, list) or architecture not in supported):
        raise ValueError(f'Runtime does not support requested architecture {architecture}: {supported}')
    version = runtime.get('version', '')
    if not re.fullmatch(r'[0-9]+(?:\.[0-9]+){1,2}', version):
        raise ValueError('Runtime version must be a numeric iOS version')
    return f'{architecture}-apple-ios{version}-simulator', runtime

def compile_worker(state_dir, requested, listing, architecture=None):
    runtimes, _ = command(['xcrun', 'simctl', 'list', 'runtimes', '--json'])
    target, runtime = target_identity(json.loads(listing), json.loads(runtimes), requested, architecture)
    sdk, _ = command(['xcrun', '--sdk', 'iphonesimulator', '--show-sdk-path'])
    compiler, _ = command(['xcrun', '--sdk', 'iphonesimulator', '--find', 'clang'])
    compiler_version, _ = command([compiler.strip(), '--version'])
    sdk_version, _ = command(['xcrun', '--sdk', 'iphonesimulator', '--show-sdk-version'])
    source = ROOT / 'worker.m'
    identity = hashlib.sha256(source.read_bytes() + json.dumps({
        'protocol': PROTOCOL, 'target': target,
        'runtime': {key: runtime.get(key) for key in ('identifier', 'version', 'buildversion')},
        'sdk': sdk.strip(), 'sdk_version': sdk_version.strip(),
        'compiler': compiler.strip(), 'compiler_version': compiler_version,
    }, sort_keys=True).encode()).hexdigest()
    workers = prepare_directory(state_dir / 'workers')
    cache = prepare_directory(workers / identity)
    worker = cache / 'worker.dylib'
    with (cache / 'compile.lock').open('a') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        if not worker.is_file():
            temporary = cache / f'worker-{uuid.uuid4().hex}.dylib'
            try:
                command([compiler.strip(), '-target', target, '-isysroot', sdk.strip(),
                         '-dynamiclib', '-framework', 'Foundation', '-fobjc-arc',
                         '-Wall', '-Wextra', '-Werror', str(source), '-o', str(temporary)], timeout=60)
                os.replace(temporary, worker)
            finally:
                temporary.unlink(missing_ok=True)
    return worker, identity

def validate_response(value, nonce, pid, expected_identifiers=None):
    if not isinstance(value, dict) or value.get('nonce') != nonce:
        raise ValueError('Worker response does not match the command nonce')
    if type(value.get('pid')) is not int or value['pid'] != pid:
        raise ValueError('Worker response does not match the injected SpringBoard PID')
    if value.get('status') not in {'submitted', 'removal_submitted', 'validated', 'inspected', 'configuration_exported', 'configuration_applied', 'error'}:
        raise ValueError('Worker response contains an invalid status')
    if value.get('status') == 'error' and not isinstance(value.get('error'), str):
        raise ValueError('Worker error response must include an error string')
    if expected_identifiers and value['status'] != 'error':
        if any(value.get(key) != identifier for key, identifier in expected_identifiers.items()):
            raise ValueError('Worker response does not match the targeted persisted identifiers')
        if not isinstance(value.get('iconClass'), str) or type(value.get('widgetIdentityVerified')) is not bool:
            raise ValueError('Worker response is missing concrete widget identity validation')
    return value

def validate_configuration(envelope, expected):
    if not isinstance(envelope, dict) or type(envelope.get('schemaVersion')) is not int or envelope['schemaVersion'] != 1:
        raise ValueError('Configuration requires schemaVersion 1')
    for key, value in expected.items():
        if envelope.get(key) != value:
            raise ValueError(f'Configuration {key} does not match the current widget')
    intent = envelope.get('intent')
    keys = {'intentClass', 'appBundleIdentifier', 'extensionBundleIdentifier', 'appIntentIdentifier', 'parameters'}
    if not isinstance(intent, dict) or set(intent) != keys:
        raise ValueError('Configuration must include the full canonical intent envelope')
    if intent['intentClass'] != 'INAppIntent' or intent['appBundleIdentifier'] != expected['container'] or intent['extensionBundleIdentifier'] != expected['extension']:
        raise ValueError('Configuration intent class, app, or extension does not match the widget')
    if not isinstance(intent['appIntentIdentifier'], str) or not intent['appIntentIdentifier']:
        raise ValueError('Configuration appIntentIdentifier must be nonempty')
    if not isinstance(intent['parameters'], dict):
        raise ValueError('Configuration parameters must be a full dictionary')
    json.dumps(envelope, allow_nan=False)
    return envelope

def request_worker(session, live, payload, expected_identifiers=None):
    nonce = str(uuid.uuid4())
    command_payload = dict(payload, nonce=nonce)
    started = time.monotonic()
    (session / 'command.json').unlink(missing_ok=True)
    (session / 'response.json').unlink(missing_ok=True)
    atomic_json(session / 'command.json', command_payload)
    deadline = started + 30
    try:
        while time.monotonic() < deadline:
            candidate = read_json(session / 'response.json')
            if isinstance(candidate, dict) and candidate.get('nonce') == nonce:
                response = validate_response(candidate, nonce, int(live['pid']), expected_identifiers)
                return response, time.monotonic() - started
            current = heartbeat(session)
            if not current or current.get('pid') != live['pid'] or current.get('identity') != live.get('identity'):
                raise RuntimeError('Worker heartbeat changed or stopped while waiting for command response')
            time.sleep(.05)
        raise RuntimeError('No response matching the command nonce within 30 seconds')
    finally:
        (session / 'command.json').unlink(missing_ok=True)

def load_iconstate(paths):
    errors = []
    for path in paths:
        try:
            with path.open('rb') as handle:
                value = plistlib.load(handle)
            if not isinstance(value, dict) or not isinstance(value.get('iconLists'), list):
                raise ValueError('IconState must contain Home iconLists')
            return value, path
        except (OSError, ValueError, plistlib.InvalidFileException) as error:
            errors.append(str(error))
    raise RuntimeError('Cannot read persisted Home IconState for duplicate preflight: ' + '; '.join(errors))

def records(value):
    if isinstance(value, dict):
        yield value
        for child in value.values():
            yield from records(child)
    elif isinstance(value, list):
        for child in value:
            yield from records(child)

def verify_iconstate(data, extension, kind, size):
    matches = []
    if not isinstance(data, dict):
        raise ValueError('IconState root must be a dictionary')
    for item in records(data.get('iconLists', [])):
        kind_value = item.get('widgetIdentifier', item.get('widgetKind', item.get('kind')))
        extension_value = item.get('extensionBundleIdentifier', item.get('widgetExtensionBundleIdentifier', item.get('bundleIdentifier')))
        grid = item.get('gridSize', item.get('gridSizeClass', item.get('sizeClass')))
        if kind_value == kind and extension_value == extension and str(grid).lower().replace(' ', '') == size:
            matches.append(item)
    return matches

def persisted_target(item):
    result = {}
    for source, key in (('displayIdentifier', 'iconIdentifier'), ('uniqueIdentifier', 'widgetIdentifier')):
        value = item.get(source)
        if not isinstance(value, str):
            raise ValueError(f'Widget entry is missing {source}')
        try:
            uuid.UUID(value)
        except ValueError as error:
            raise ValueError(f'Widget {source} is not a UUID') from error
        result[key] = value
    return result

def home_identities(state):
    identities = Counter()
    def collect(value):
        if isinstance(value, dict):
            for key in ('displayIdentifier', 'uniqueIdentifier'):
                if isinstance(value.get(key), str):
                    identities[(key, value[key])] += 1
            for child in value.values():
                if isinstance(child, (dict, list)):
                    collect(child)
        elif isinstance(value, list):
            for child in value:
                if isinstance(child, str):
                    identities[('leaf', child)] += 1
                else:
                    collect(child)
    collect(state.get('iconLists', []))
    return identities

def validate_home_target(state, target):
    identities = home_identities(state)
    if identities[('displayIdentifier', target['iconIdentifier'])] != 1 or identities[('uniqueIdentifier', target['widgetIdentifier'])] != 1:
        raise ValueError('Targeted widget identifiers must each identify exactly one Home entry')

def removal_outcome(before, after, target):
    excluded = {('displayIdentifier', target['iconIdentifier']), ('uniqueIdentifier', target['widgetIdentifier'])}
    current = home_identities(after)
    if any(current[key] for key in excluded):
        return False, 'Targeted Home widget identifiers are still persisted'
    expected = home_identities(before)
    for key in excluded:
        expected.pop(key, None)
    missing = expected - current
    if missing:
        return False, f'Other Home entries disappeared: {dict(missing)}'
    return True, None

def exclusive_targets(state, extension, desired):
    targets = []
    for item in records(state.get('iconLists', [])):
        bundle = item.get('extensionBundleIdentifier', item.get('widgetExtensionBundleIdentifier', item.get('bundleIdentifier')))
        kind = item.get('widgetIdentifier', item.get('widgetKind', item.get('kind')))
        if bundle != extension or not isinstance(kind, str):
            continue
        identifiers = persisted_target(item)
        validate_home_target(state, identifiers)
        if identifiers != desired:
            targets.append(identifiers)
    icon_identifiers = [item['iconIdentifier'] for item in targets]
    widget_identifiers = [item['widgetIdentifier'] for item in targets]
    if len(set(icon_identifiers)) != len(targets) or len(set(widget_identifiers)) != len(targets):
        raise ValueError('Exclusive preflight contains duplicate persisted identifiers')
    return targets

def validate_target_batch(response, targets, desired=None):
    if desired is not None:
        actual_desired = response.get('desired')
        if not isinstance(actual_desired, dict) or any(actual_desired.get(key) != value for key, value in desired.items()) or not isinstance(actual_desired.get('descriptor'), str):
            raise ValueError('Worker did not validate the desired widget descriptor and family')
    actual = response.get('targets')
    if response.get('status') != 'validated' or not isinstance(actual, list) or len(actual) != len(targets):
        raise ValueError('Worker did not validate all exclusive targets')
    for expected, item in zip(targets, actual):
        if not isinstance(item, dict) or any(item.get(key) != value for key, value in expected.items()):
            raise ValueError('Worker validated different persisted identifiers')
        if not isinstance(item.get('iconClass'), str) or type(item.get('widgetIdentityVerified')) is not bool:
            raise ValueError('Worker batch validation omitted concrete widget identity')

def exclusive_outcome(before, after, extension, desired, removed):
    if exclusive_targets(after, extension, desired):
        return False, 'Other widgets from the requested extension remain in Home IconState'
    expected = home_identities(before)
    for target in removed:
        expected.pop(('displayIdentifier', target['iconIdentifier']), None)
        expected.pop(('uniqueIdentifier', target['widgetIdentifier']), None)
    missing = expected - home_identities(after)
    if missing:
        return False, f'Preserved Home entries disappeared: {dict(missing)}'
    return True, None

def replacement_outcome(before, after, previous, current, removed):
    if current['iconIdentifier'] == previous['iconIdentifier'] or current['widgetIdentifier'] == previous['widgetIdentifier']:
        return False, 'Replacement reused a removed widget identifier'
    expected = home_identities(before)
    for target in removed:
        expected.pop(('displayIdentifier', target['iconIdentifier']), None)
        expected.pop(('uniqueIdentifier', target['widgetIdentifier']), None)
    missing = expected - home_identities(after)
    if missing:
        return False, f'Other Home entries disappeared during replacement: {dict(missing)}'
    return True, None

def wait_for_removal(state_paths, before, target):
    started = time.monotonic()
    deadline = started + 5
    verified, verification_error, state_path, after = False, None, None, None
    while time.monotonic() < deadline:
        try:
            after, state_path = load_iconstate(state_paths)
            verified, verification_error = removal_outcome(before, after, target)
            if verified:
                break
        except RuntimeError as error:
            verification_error = str(error)
        time.sleep(.1)
    return verified, verification_error, state_path, after, time.monotonic() - started

def home_widget_position(state, target):
    matches = []
    for page_index, page in enumerate(state.get('iconLists', [])):
        if not isinstance(page, list):
            continue
        for item_index, item in enumerate(page):
            if isinstance(item, dict) and item.get('displayIdentifier') == target['iconIdentifier'] and item.get('uniqueIdentifier') == target['widgetIdentifier']:
                matches.append((page_index, item_index))
    if len(matches) != 1:
        raise ValueError('Positioning requires exactly one direct Home page widget entry')
    return matches[0]

def positioning_outcome(before, after, target):
    before_page, _ = home_widget_position(before, target)
    if home_widget_position(after, target) != (before_page, 0):
        return False, 'Widget is not at index zero of its original Home page'
    missing = home_identities(before) - home_identities(after)
    if missing:
        return False, f'Other Home entries disappeared during positioning: {dict(missing)}'
    return True, None

def wait_for_position(state_paths, before, target):
    started = time.monotonic()
    deadline = started + 5
    verified, error, state_path, after = False, None, None, None
    while time.monotonic() < deadline:
        try:
            after, state_path = load_iconstate(state_paths)
            verified, error = positioning_outcome(before, after, target)
            if verified:
                break
        except (RuntimeError, ValueError) as failure:
            error = str(failure)
        time.sleep(.1)
    return verified, error, state_path, after, time.monotonic() - started

def springboard_target(udid, launch_domain=None):
    if launch_domain is not None:
        if not re.fullmatch(r'user/[0-9]+', launch_domain):
            raise ValueError('Launch domain must be user/UID')
        return f'{launch_domain}/com.apple.SpringBoard'
    uid, _ = sim(udid, 'launchctl', 'manageruid')
    uid = uid.strip()
    if not re.fullmatch(r'[0-9]+', uid):
        raise RuntimeError('Simulator did not report a numeric launch-user UID')
    return f'user/{uid}/com.apple.SpringBoard'

def springboard_pid(udid, target):
    text, _ = sim(udid, 'launchctl', 'print', target)
    match = re.search(r'(?m)^\s*pid\s*=\s*(\d+)\s*$', text)
    return int(match.group(1)) if match else None

def iconstate_metadata(paths, extension, kind):
    fields = ('widgetIdentifier', 'bundleIdentifier', 'containerBundleIdentifier', 'gridSize', 'uniqueIdentifier', 'displayIdentifier')
    for path in paths:
        try:
            with path.open('rb') as handle:
                state = plistlib.load(handle)
            items = [item for item in records(state.get('iconLists', [])) if item.get('widgetIdentifier') == kind and item.get('bundleIdentifier') == extension]
            return [{key: item[key] for key in fields if key in item} for item in items]
        except (OSError, ValueError, plistlib.InvalidFileException):
            continue
    return []

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('udid')
    parser.add_argument('extension', nargs='?')
    parser.add_argument('kind', nargs='?')
    parser.add_argument('size', nargs='?')
    parser.add_argument('--container')
    parser.add_argument('--export-config', type=Path, help='Export the exact current widget configuration and validate detached no-op reconstruction.')
    parser.add_argument('--apply-config', type=Path, help='Apply a full exported configuration bound to the exact current widget; emit its new restoration envelope.')
    parser.add_argument('--prepare', action='store_true', help='Initialize or reuse the worker without sending an inspection or widget command.')
    parser.add_argument('--replace', action='store_true', help='Remove and recreate the desired tuple after descriptor preflight, preserving other widgets unless --exclusive is also supplied.')
    parser.add_argument('--position', choices=['top'], help='Move the requested widget to index zero of its current Home page before reveal.')
    parser.add_argument('--exclusive', action='store_true', help='Ensure only the requested widget tuple remains for this extension, preserving other extensions and apps.')
    parser.add_argument('--remove', action='store_true', help='Remove exactly one matching persisted Home widget and preserve other entries.')
    parser.add_argument('--icon-identifier', help='UUID of a persisted leaf icon for read-only --inspect object metadata.')
    parser.add_argument('--architecture', choices=['arm64', 'x86_64'], help='Override native host simulator architecture; checked against runtime metadata when available.')
    parser.add_argument('--inspect', action='store_true', help='Read relevant SpringBoard runtime class/method metadata without placing widgets.')
    parser.add_argument('--launch-domain', help='Explicit simulated launch domain, user/UID; default discovers launchctl manageruid.')
    parser.add_argument('--state-dir', type=Path, default=Path.home() / 'Library/Caches/SimulatorWidgets', help='Host directory for generated workers and per-device sessions.')
    parser.add_argument('--unload', action='store_true', help='Restart only this simulator SpringBoard without the one-launch injection.')
    args = parser.parse_args()
    try:
        requested = str(uuid.UUID(args.udid)).upper()
    except ValueError:
        parser.error('UDID must be an explicit UUID')
    if sum((args.unload, args.inspect, args.remove, args.prepare, bool(args.export_config), bool(args.apply_config))) > 1:
        parser.error('--unload, --inspect, --remove, --prepare, --export-config, and --apply-config are mutually exclusive')
    if args.replace and (args.remove or args.unload or args.inspect or args.prepare or args.export_config or args.apply_config):
        parser.error('--replace applies only to ensure placement')
    if args.position and (args.remove or args.unload or args.inspect or args.prepare or args.export_config or args.apply_config):
        parser.error('--position applies only to ensure placement')
    if args.exclusive and (args.remove or args.unload or args.inspect or args.prepare or args.export_config or args.apply_config):
        parser.error('--exclusive applies only to ensure placement')
    if args.icon_identifier and not args.inspect:
        parser.error('--icon-identifier requires --inspect')
    if args.icon_identifier:
        try:
            uuid.UUID(args.icon_identifier)
        except ValueError:
            parser.error('--icon-identifier must be a UUID')
    if (args.unload or args.inspect or args.prepare) and any((args.extension, args.kind, args.size, args.container)):
        parser.error('--unload, --inspect, and --prepare accept only UDID and lifecycle options')
    if not args.unload and not args.inspect and not args.prepare:
        if not args.extension or not args.kind or not args.size:
            parser.error('placement requires EXTENSION KIND SIZE')
        if args.size not in SIZES:
            parser.error('size must be small, medium, or large')
        if not args.kind.strip() or not args.extension.strip():
            parser.error('extension and kind must be non-empty')
    output = RESULT
    output.update(udid=requested, mode='unload' if args.unload else 'inspect' if args.inspect else 'prepare' if args.prepare else 'remove' if args.remove else 'export' if args.export_config else 'apply' if args.apply_config else 'ensure', timings={})
    state_dir = prepare_directory(args.state_dir)
    output['state_dir'] = str(state_dir)
    sessions = prepare_directory(state_dir / 'sessions')
    session = prepare_directory(sessions / requested)
    with (session / 'runner.lock').open('a') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        listing, _ = command(['xcrun', 'simctl', 'list', 'devices', '--json'])
        devices = [d for group in json.loads(listing)['devices'].values() for d in group]
        device = select_booted_device(devices, requested)
        target = springboard_target(requested, args.launch_domain)
        output['springboard_target'] = target
        injection_path = session / 'injection.json'
        data_path = Path(device.get('dataPath', str(Path.home() / 'Library/Developer/CoreSimulator/Devices' / requested / 'data')))
        state_paths = [data_path / 'Library/SpringBoard/IconState.plist', data_path / 'home/mobile/Library/SpringBoard/IconState.plist']
        if args.unload:
            (session / 'command.json').unlink(missing_ok=True)
            before = heartbeat(session)
            previous_pid = springboard_pid(requested, target)
            injection = read_json(injection_path)
            owned = isinstance(injection, dict) and injection.get('udid') == requested and injection.get('target') == target
            pending = owned and injection.get('pending') is True
            active = owned and type(injection.get('pid')) is int and injection['pid'] == previous_pid
            if not pending and not active and (not before or int(before['pid']) != previous_pid):
                injection_path.unlink(missing_ok=True)
                output.update(status='unloaded', no_op=True, springboard_pid=previous_pid)
                print(json.dumps(output))
                return 0
            started = time.monotonic()
            if pending:
                sim(requested, 'launchctl', 'debug', target, '--environment', 'DYLD_INSERT_LIBRARIES=', 'WIDGETCTL_SESSION_DIR=', 'WIDGETCTL_IDENTITY=', 'WIDGETCTL_UDID=')
            sim(requested, 'launchctl', 'kickstart', '-k', target)
            deadline = time.monotonic() + 45
            new_pid = None
            while time.monotonic() < deadline:
                new_pid = springboard_pid(requested, target)
                if new_pid and new_pid != previous_pid:
                    break
                time.sleep(.2)
            output['timings']['injection_restart_seconds'] = time.monotonic() - started
            if not new_pid or new_pid == previous_pid:
                raise RuntimeError('SpringBoard did not publish a new target PID after unload restart')
            observation = time.monotonic()
            unexpected_worker = None
            while time.monotonic() - observation < 3:
                unexpected_worker = heartbeat(session)
                if unexpected_worker:
                    break
                time.sleep(.1)
            output['timings']['unload_observation_seconds'] = time.monotonic() - observation
            if not unexpected_worker:
                injection_path.unlink(missing_ok=True)
                (session / 'heartbeat.json').unlink(missing_ok=True)
            output.update(status='unloaded' if not unexpected_worker else 'worker_still_live', previous_heartbeat=before, previous_springboard_pid=previous_pid, springboard_pid=new_pid)
            print(json.dumps(output))
            return 0 if output['status'] == 'unloaded' else 1
        (session / 'command.json').unlink(missing_ok=True)
        if not args.inspect and not args.prepare:
            existing_state, _ = load_iconstate(state_paths)
            output['iconstate_before'] = iconstate_metadata(state_paths, args.extension, args.kind)
            existing_matches = verify_iconstate(existing_state, args.extension, args.kind, args.size)
            if len(existing_matches) > 1:
                output.update(status='duplicate_existing_widgets', error='Multiple Home widgets already match this kind and size; no widget command sent')
                print(json.dumps(output))
                return 2
            if (args.export_config or args.apply_config) and not existing_matches:
                raise RuntimeError('Configuration export requires one installed persisted widget tuple')
            if args.remove and not existing_matches:
                output.update(status='removed', no_op=True, iconstate_matches=[])
                print(json.dumps(output))
                return 0
            target_identifiers = persisted_target(existing_matches[0]) if existing_matches else None
            if target_identifiers:
                validate_home_target(existing_state, target_identifiers)
        else:
            target_identifiers = None
        scoped_targets = exclusive_targets(existing_state, args.extension, target_identifiers) if args.exclusive else []
        replaced_identifiers = target_identifiers if args.replace else None
        if replaced_identifiers:
            scoped_targets.append(replaced_identifiers)
            output['replaced_identifiers'] = replaced_identifiers
        worker, identity = compile_worker(state_dir, requested, listing, args.architecture)
        output['worker_path'] = str(worker)
        live = heartbeat(session)
        if live and (live.get('protocol') != PROTOCOL or live.get('identity') != identity or live.get('ready') is not True):
            live = None
        if live:
            target_pid = springboard_pid(requested, target)
            output['springboard_pid'] = target_pid
            if target_pid != int(live['pid']):
                live = None
        if not live:
            started = time.monotonic()
            (session / 'command.json').unlink(missing_ok=True)
            (session / 'heartbeat.json').unlink(missing_ok=True)
            atomic_json(injection_path, {'udid': requested, 'target': target, 'pending': True, 'identity': identity})
            sim(requested, 'launchctl', 'debug', target, '--environment', f'DYLD_INSERT_LIBRARIES={worker}', f'WIDGETCTL_SESSION_DIR={session}', f'WIDGETCTL_IDENTITY={identity}', f'WIDGETCTL_UDID={requested}')
            sim(requested, 'launchctl', 'kickstart', '-k', target)
            deadline = time.monotonic() + 45
            while time.monotonic() < deadline:
                live = heartbeat(session)
                if live and live.get('protocol') == PROTOCOL and live.get('identity') == identity and live.get('ready') is True and springboard_pid(requested, target) == int(live['pid']):
                    break
                live = None
                time.sleep(.1)
            output['timings']['injection_restart_seconds'] = time.monotonic() - started
            if not live:
                raise RuntimeError('Injected worker did not publish a live heartbeat within 45 seconds')
        else:
            output['timings']['injection_restart_seconds'] = 0
        atomic_json(injection_path, {'udid': requested, 'target': target, 'pending': False, 'identity': identity, 'pid': int(live['pid'])})
        output['worker'] = live
        output['springboard_pid'] = int(live['pid'])
        if args.prepare:
            output['status'] = 'ready'
            print(json.dumps(output))
            return 0
        if scoped_targets:
            validation_targets = ([target_identifiers] if target_identifiers and target_identifiers not in scoped_targets else []) + scoped_targets
            operation_prefix = 'exclusive' if args.exclusive else 'replace'
            desired = {'extension': args.extension, 'kind': args.kind, 'size': args.size}
            if args.container:
                desired['container'] = args.container
            validation_payload = {'mode': 'validate', 'targets': validation_targets, 'desired': desired}
            if args.position:
                validation_payload['position'] = args.position
            validation, validation_elapsed = request_worker(session, live, validation_payload)
            output[f'{operation_prefix}_preflight'] = validation
            output['timings'][f'{operation_prefix}_preflight_seconds'] = validation_elapsed
            if validation['status'] == 'error':
                output.update(status=f'{operation_prefix}_preflight_rejected', error=validation['error'])
                print(json.dumps(output))
                return 1
            validate_target_batch(validation, validation_targets, desired)
            output[f'{operation_prefix}_removals'] = []
            for scoped_target in scoped_targets:
                before, _ = load_iconstate(state_paths)
                removal, removal_elapsed = request_worker(session, live, {'mode': 'remove', **scoped_target}, scoped_target)
                result = {'identifiers': scoped_target, 'response': removal, 'command_seconds': removal_elapsed}
                output[f'{operation_prefix}_removals'].append(result)
                if removal['status'] == 'error':
                    output.update(status=f'{operation_prefix}_removal_rejected', error=removal['error'])
                    print(json.dumps(output))
                    return 1
                if removal['status'] != 'removal_submitted':
                    raise ValueError('Exclusive removal received an unexpected worker response')
                verified, error, _, _, verification_elapsed = wait_for_removal(state_paths, before, scoped_target)
                result['verification_seconds'] = verification_elapsed
                if not verified:
                    output.update(status=f'{operation_prefix}_removal_unverified', verification_error=error)
                    print(json.dumps(output))
                    return 2
        if replaced_identifiers:
            target_identifiers = None
        position_before = None
        if args.position and target_identifiers:
            position_before, _ = load_iconstate(state_paths)
            home_widget_position(position_before, target_identifiers)
        payload = {'mode': 'inspect' if args.inspect else 'remove' if args.remove else 'exportConfiguration' if args.export_config else 'applyConfiguration' if args.apply_config else 'ensure'}
        if target_identifiers:
            payload.update(target_identifiers)
            if args.position:
                payload['position'] = args.position
        if args.icon_identifier:
            payload['iconIdentifier'] = args.icon_identifier
        if not args.inspect:
            payload.update(extension=args.extension, kind=args.kind, size=args.size)
        if args.container:
            payload['container'] = args.container
        if args.export_config or args.apply_config:
            container = existing_matches[0].get('containerBundleIdentifier')
            if not isinstance(container, str) or not container or (args.container and args.container != container):
                raise ValueError('Configuration export requires the exact persisted app container identifier')
            payload.update(udid=requested, container=container)
            if args.apply_config:
                expected = {key: payload[key] for key in ('udid', 'extension', 'container', 'kind', 'size', 'iconIdentifier', 'widgetIdentifier')}
                payload['configuration'] = validate_configuration(read_json(args.apply_config.expanduser().absolute()), expected)
        response, elapsed = request_worker(session, live, payload, target_identifiers)
        output['timings']['command_seconds'] = elapsed
        output['response'] = response
        if response.get('status') == 'error':
            output['status'] = 'worker_rejected'
            print(json.dumps(output))
            return 1
        if args.apply_config:
            if response['status'] != 'configuration_applied' or response.get('roundtripVerified') is not True or response.get('widgetIdentityVerified') is not True or response.get('archiving') is not True:
                raise ValueError('Worker did not prove archived configuration apply and exact live readback')
            updated = dict(target_identifiers, widgetIdentifier=response.get('appliedWidgetIdentifier'))
            persisted_target({'displayIdentifier': updated['iconIdentifier'], 'uniqueIdentifier': updated['widgetIdentifier']})
            expected = {key: payload[key] for key in ('udid', 'extension', 'container', 'kind', 'size', 'iconIdentifier', 'widgetIdentifier')}
            expected.update(updated)
            configuration = validate_configuration(response.get('configuration'), expected)
            if configuration['intent'] != payload['configuration']['intent'] or response.get('roundtrip') != configuration['intent']:
                raise ValueError('Configuration readback differs from the full requested intent')
            started = time.monotonic()
            while True:
                current, _ = load_iconstate(state_paths)
                matches = verify_iconstate(current, args.extension, args.kind, args.size)
                if len(matches) == 1 and persisted_target(matches[0]) == updated:
                    expected_identities = home_identities(existing_state)
                    expected_identities[('uniqueIdentifier', target_identifiers['widgetIdentifier'])] -= 1
                    expected_identities[('uniqueIdentifier', updated['widgetIdentifier'])] += 1
                    if +expected_identities != home_identities(current):
                        raise ValueError('Configuration apply changed other Home identities')
                    break
                if time.monotonic() - started >= 5:
                    raise ValueError('Updated configuration widget identity did not persist')
                time.sleep(0.1)
            output['timings']['configuration_persistence_seconds'] = time.monotonic() - started
            output.update(status='configuration_applied', configuration=configuration, iconstate_matches=matches)
            print(json.dumps(output))
            return 0
        if args.export_config:
            if response['status'] != 'configuration_exported' or response.get('roundtripVerified') is not True or response.get('widgetIdentityVerified') is not True:
                raise ValueError('Worker did not prove exact configuration identity and detached roundtrip')
            expected = {key: payload[key] for key in ('udid', 'extension', 'container', 'kind', 'size', 'iconIdentifier', 'widgetIdentifier')}
            configuration = validate_configuration(response.get('configuration'), expected)
            if response.get('roundtrip') != configuration['intent']:
                raise ValueError('Worker roundtrip differs from the canonical exported intent')
            current, _ = load_iconstate(state_paths)
            matches = verify_iconstate(current, args.extension, args.kind, args.size)
            if len(matches) != 1 or persisted_target(matches[0]) != target_identifiers:
                raise ValueError('Configuration target persisted identity changed during export')
            destination = args.export_config.expanduser().absolute()
            atomic_json(destination, configuration)
            output.update(status='configuration_exported', configuration_path=str(destination))
            print(json.dumps(output))
            return 0
        if args.inspect:
            if response['status'] != 'inspected' or not isinstance(response.get('inspection'), dict):
                raise ValueError('Inspection command received an invalid worker response')
            output['status'] = 'inspected'
            print(json.dumps(output))
            return 0
        if args.remove:
            if response['status'] != 'removal_submitted':
                raise ValueError('Removal command received an unexpected worker response status')
            verified, verification_error, state_path, _, elapsed = wait_for_removal(state_paths, existing_state, target_identifiers)
            output['timings']['iconstate_verification_seconds'] = elapsed
            output.update(status='removed' if verified else 'removal_unverified', removed_identifiers=target_identifiers, iconstate_path=str(state_path) if state_path else None)
            if not verified:
                output['verification_error'] = verification_error
            print(json.dumps(output))
            return 0 if verified else 2
        if response['status'] != 'submitted':
            raise ValueError('Placement command received an unexpected worker response status')
        started = time.monotonic()
        matches, last_error, state_path = [], None, None
        deadline = time.monotonic() + 5
        while time.monotonic() < deadline:
            for path in state_paths:
                try:
                    with path.open('rb') as handle:
                        state = plistlib.load(handle)
                    matches = verify_iconstate(state, args.extension, args.kind, args.size)
                    state_path = path
                    if matches:
                        break
                except (OSError, ValueError, plistlib.InvalidFileException) as error:
                    last_error = str(error)
            if matches:
                break
            time.sleep(.1)
        output['timings']['iconstate_verification_seconds'] = time.monotonic() - started
        if len(matches) == 1 and target_identifiers is not None and persisted_target(matches[0]) != target_identifiers:
            output.update(status='reveal_persistence_unverified', verification_error='Existing revealed widget persisted identity changed')
            print(json.dumps(output))
            return 2
        if len(matches) == 1 and target_identifiers is None:
            revealed_identifiers = persisted_target(matches[0])
            validate_home_target(state, revealed_identifiers)
            reveal_payload = {'mode': 'ensure', **revealed_identifiers}
            if args.position:
                position_before = state
                home_widget_position(position_before, revealed_identifiers)
                reveal_payload['position'] = args.position
            reveal_response, reveal_elapsed = request_worker(session, live, reveal_payload, revealed_identifiers)
            output['reveal_response'] = reveal_response
            output['timings']['reveal_seconds'] = reveal_elapsed
            if reveal_response['status'] == 'error':
                output.update(status='reveal_rejected', error=reveal_response['error'])
                print(json.dumps(output))
                return 1
            if reveal_response['status'] != 'submitted' or reveal_response.get('action') != 'reveal':
                raise ValueError('Reveal command received an unexpected worker response')
            post_reveal_started = time.monotonic()
            state, state_path = load_iconstate(state_paths)
            matches = verify_iconstate(state, args.extension, args.kind, args.size)
            output['timings']['post_reveal_verification_seconds'] = time.monotonic() - post_reveal_started
            if len(matches) != 1 or persisted_target(matches[0]) != revealed_identifiers:
                output.update(status='reveal_persistence_unverified', verification_error='Revealed widget persisted identity changed')
                print(json.dumps(output))
                return 2
        if args.position and len(matches) == 1:
            verified, error, state_path, after, elapsed = wait_for_position(state_paths, position_before, persisted_target(matches[0]))
            output['timings']['position_verification_seconds'] = elapsed
            if not verified:
                output.update(status='position_unverified', verification_error=error)
                print(json.dumps(output))
                return 2
            output['position'] = {'page': home_widget_position(after, persisted_target(matches[0]))[0], 'index': 0}
        if args.exclusive and len(matches) == 1:
            after, state_path = load_iconstate(state_paths)
            verified, error = exclusive_outcome(existing_state, after, args.extension, persisted_target(matches[0]), scoped_targets)
            if not verified:
                output.update(status='exclusive_persistence_unverified', verification_error=error)
                print(json.dumps(output))
                return 2
        if replaced_identifiers and len(matches) == 1:
            after, state_path = load_iconstate(state_paths)
            verified, error = replacement_outcome(existing_state, after, replaced_identifiers, persisted_target(matches[0]), scoped_targets)
            if not verified:
                output.update(status='replacement_persistence_unverified', verification_error=error)
                print(json.dumps(output))
                return 2
        output['iconstate_after'] = iconstate_metadata(state_paths, args.extension, args.kind)
        output.update(status='verified' if len(matches)==1 else 'response_received_but_iconstate_unverified', iconstate_path=str(state_path) if state_path else None, iconstate_matches=matches)
        if len(matches) > 1:
            output['verification_error'] = 'Multiple IconState entries match the requested widget and size'
        if not matches:
            output['verification_error'] = last_error or 'No IconState entry matches extension, kind, and grid size'
        print(json.dumps(output, default=str))
        return 0 if len(matches)==1 else 2

if __name__ == '__main__':
    try:
        sys.exit(main())
    except (RuntimeError, OSError, ValueError, subprocess.TimeoutExpired) as error:
        RESULT.update(status='failed', error=str(error))
        print(json.dumps(RESULT, default=str))
        sys.exit(1)
