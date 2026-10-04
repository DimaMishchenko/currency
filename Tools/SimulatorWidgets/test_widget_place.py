import contextlib
import importlib.util
import io
import json
import os
from pathlib import Path
import plistlib
import tempfile
import time
import unittest
from unittest.mock import patch

SPEC = importlib.util.spec_from_file_location('widget_place', Path(__file__).with_name('widget-place.py'))
widget_place = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(widget_place)
UDID = '11111111-1111-1111-1111-111111111111'


def widget(kind='ExampleKind', extension='org.example.widgets', size='small'):
    return {'widgetIdentifier': kind, 'bundleIdentifier': extension, 'containerBundleIdentifier': 'org.example.app', 'gridSize': size, 'uniqueIdentifier': '22222222-2222-2222-2222-222222222222', 'displayIdentifier': '33333333-3333-3333-3333-333333333333'}


class WidgetTests(unittest.TestCase):
    def setUp(self):
        widget_place.RESULT.clear()

    def test_matches_exact_extension_kind_and_family_only_in_home_lists(self):
        state = {'iconLists': [[widget(), widget(size='medium'), widget(kind='OtherKind'), widget(extension='org.other')]],
                 'todayLists': [widget()]}
        self.assertEqual(widget_place.verify_iconstate(state, 'org.example.widgets', 'ExampleKind', 'small'), [widget()])
        self.assertEqual(widget_place.verify_iconstate(state, 'org.example.widgets', 'ExampleKind', 'large'), [])

    def test_duplicate_matching_entries_are_retained_for_preflight(self):
        state = {'iconLists': [[widget(), widget()]]}
        self.assertEqual(len(widget_place.verify_iconstate(state, 'org.example.widgets', 'ExampleKind', 'small')), 2)

    def test_missing_or_non_home_iconstate_fails_closed(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'IconState.plist'
            with self.assertRaises(RuntimeError):
                widget_place.load_iconstate([path])
            path.write_bytes(plistlib.dumps({'todayLists': [widget()]}))
            with self.assertRaises(RuntimeError):
                widget_place.load_iconstate([path])
            path.write_bytes(plistlib.dumps({'iconLists': []}))
            self.assertEqual(widget_place.load_iconstate([path]), ({'iconLists': []}, path))

    def test_persisted_widget_and_leaf_identifiers_are_distinct_and_validated(self):
        identifiers = widget_place.persisted_target(widget())
        self.assertEqual(identifiers['iconIdentifier'], widget()['displayIdentifier'])
        self.assertEqual(identifiers['widgetIdentifier'], widget()['uniqueIdentifier'])
        for entry in (dict(widget(), displayIdentifier='bad'), dict(widget(), uniqueIdentifier=None)):
            with self.assertRaises(ValueError):
                widget_place.persisted_target(entry)

    def test_removal_proves_target_gone_and_preserves_other_home_entries(self):
        target = widget()
        other = dict(widget(kind='Other'), uniqueIdentifier='other-widget', displayIdentifier='other-leaf')
        before = {'iconLists': [['org.example.app', target], [other]]}
        identifiers = widget_place.persisted_target(target)
        after = {'iconLists': [['org.example.app'], [other]]}
        self.assertEqual(widget_place.removal_outcome(before, after, identifiers), (True, None))
        for invalid in (before, {'iconLists': [[other]]}, {'iconLists': [['org.example.app']]}):
            self.assertFalse(widget_place.removal_outcome(before, invalid, identifiers)[0])

    def test_remove_missing_tuple_is_noop_before_compile_or_injection(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            state = root / 'data/Library/SpringBoard/IconState.plist'
            state.parent.mkdir(parents=True)
            state.write_bytes(plistlib.dumps({'iconLists': []}))
            listing = {'devices': {'runtime': [{'udid': UDID, 'state': 'Booted', 'dataPath': str(root / 'data')}]}}
            argv = ['widget-place.py', UDID, 'org.example.widgets', 'ExampleKind', 'small', '--remove', '--state-dir', str(root / 'cache')]
            with patch.object(widget_place.sys, 'argv', argv), patch.object(widget_place, 'command', return_value=(json.dumps(listing), 0)), patch.object(widget_place, 'springboard_target', return_value='user/501/com.apple.SpringBoard'), patch.object(widget_place, 'sim') as sim, patch.object(widget_place, 'compile_worker') as compile_worker, contextlib.redirect_stdout(io.StringIO()) as output:
                self.assertEqual(widget_place.main(), 0)
            sim.assert_not_called()
            compile_worker.assert_not_called()
            result = json.loads(output.getvalue())
            self.assertEqual(result['status'], 'removed')
            self.assertTrue(result['no_op'])

    def test_exclusive_targets_only_other_widgets_from_requested_extension(self):
        desired = widget()
        other = dict(widget(size='medium'), displayIdentifier='44444444-4444-4444-4444-444444444444', uniqueIdentifier='55555555-5555-5555-5555-555555555555')
        unrelated = dict(widget(extension='org.other.widgets'), displayIdentifier='66666666-6666-6666-6666-666666666666', uniqueIdentifier='77777777-7777-7777-7777-777777777777')
        state = {'iconLists': [['org.example.app', desired, other, unrelated]]}
        target = widget_place.persisted_target(other)
        selected = widget_place.exclusive_targets(state, 'org.example.widgets', widget_place.persisted_target(desired))
        self.assertEqual(selected, [target])
        after = {'iconLists': [['org.example.app', desired, unrelated]]}
        self.assertEqual(widget_place.exclusive_outcome(state, after, 'org.example.widgets', widget_place.persisted_target(desired), selected), (True, None))
        self.assertFalse(widget_place.exclusive_outcome(state, state, 'org.example.widgets', widget_place.persisted_target(desired), selected)[0])
        self.assertFalse(widget_place.exclusive_outcome(state, {'iconLists': [[desired, unrelated]]}, 'org.example.widgets', widget_place.persisted_target(desired), selected)[0])
        with self.assertRaises(ValueError):
            widget_place.exclusive_targets({'iconLists': [[other, other]]}, 'org.example.widgets', None)

    def test_shared_home_identifiers_reject_target_before_mutation(self):
        target = widget_place.persisted_target(widget())
        widget_place.validate_home_target({'iconLists': [[widget()]]}, target)
        with self.assertRaises(ValueError):
            widget_place.validate_home_target({'iconLists': [[widget(), widget(extension='org.other')]]}, target)

    def test_batch_validation_requires_all_exact_concrete_targets(self):
        target = widget_place.persisted_target(widget())
        response = {'status': 'validated', 'targets': [dict(target, iconClass='SBWidgetIcon', widgetIdentityVerified=True)]}
        widget_place.validate_target_batch(response, [target])
        for invalid in ({'status': 'validated', 'targets': []}, {'status': 'validated', 'targets': [dict(target, iconIdentifier='wrong')]}, {'status': 'error'}):
            with self.assertRaises(ValueError):
                widget_place.validate_target_batch(invalid, [target])

    def test_new_placement_reveals_with_second_nonce_without_recompile(self):
        for corrupt_after_reveal in (False, True):
            with self.subTest(corrupt_after_reveal=corrupt_after_reveal), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                state_path = root / 'data/Library/SpringBoard/IconState.plist'
                state_path.parent.mkdir(parents=True)
                state_path.write_bytes(plistlib.dumps({'iconLists': []}))
                listing = {'devices': {'runtime': [{'udid': UDID, 'state': 'Booted', 'dataPath': str(root / 'data')}]}}
                live = {'pid': 123, 'identity': 'identity', 'protocol': 1, 'ready': True, 'udid': UDID}
                argv = ['widget-place.py', UDID, 'org.example.widgets', 'ExampleKind', 'small', '--state-dir', str(root / 'cache')]
                published = []
                original_atomic = widget_place.atomic_json
                def publish(path, payload):
                    original_atomic(path, payload)
                    if path.name != 'command.json':
                        return
                    published.append(payload)
                    response = {'nonce': payload['nonce'], 'pid': 123, 'status': 'submitted'}
                    if 'iconIdentifier' in payload:
                        response.update(widget_place.persisted_target(widget()), iconClass='SBWidgetIcon', widgetIdentityVerified=True, action='reveal')
                        if corrupt_after_reveal:
                            state_path.write_bytes(plistlib.dumps({'iconLists': [[dict(widget(), uniqueIdentifier='66666666-6666-6666-6666-666666666666')]]}))
                    else:
                        state_path.write_bytes(plistlib.dumps({'iconLists': [[widget()]]}))
                    original_atomic(path.with_name('response.json'), response)
                with patch.object(widget_place.sys, 'argv', argv), patch.object(widget_place, 'command', return_value=(json.dumps(listing), 0)), patch.object(widget_place, 'springboard_target', return_value='user/501/com.apple.SpringBoard'), patch.object(widget_place, 'springboard_pid', return_value=123), patch.object(widget_place, 'heartbeat', return_value=live), patch.object(widget_place, 'compile_worker', return_value=(root / 'worker.dylib', 'identity')) as compile_worker, patch.object(widget_place, 'atomic_json', side_effect=publish), patch.object(widget_place, 'sim') as sim, contextlib.redirect_stdout(io.StringIO()) as output:
                    self.assertEqual(widget_place.main(), 2 if corrupt_after_reveal else 0)
                compile_worker.assert_called_once()
                sim.assert_not_called()
                self.assertEqual(len(published), 2)
                self.assertNotEqual(published[0]['nonce'], published[1]['nonce'])
                self.assertEqual(set(published[1]), {'nonce', 'mode', 'iconIdentifier', 'widgetIdentifier'})
                result = json.loads(output.getvalue())
                self.assertIn('reveal_seconds', result['timings'])
                self.assertEqual(result['status'], 'reveal_persistence_unverified' if corrupt_after_reveal else 'verified')
                widget_place.RESULT.clear()

    def test_exclusive_prevalidates_then_removes_and_reveals_in_one_session(self):
        for reject_preflight in (False, True):
            with self.subTest(reject_preflight=reject_preflight), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                desired = widget()
                other = dict(widget(size='medium'), displayIdentifier='44444444-4444-4444-4444-444444444444', uniqueIdentifier='55555555-5555-5555-5555-555555555555')
                unrelated = dict(widget(extension='org.other.widgets'), displayIdentifier='66666666-6666-6666-6666-666666666666', uniqueIdentifier='77777777-7777-7777-7777-777777777777')
                before = {'iconLists': [['org.example.app', desired, other, unrelated]]}
                state_path = root / 'data/Library/SpringBoard/IconState.plist'
                state_path.parent.mkdir(parents=True)
                state_path.write_bytes(plistlib.dumps(before))
                listing = {'devices': {'runtime': [{'udid': UDID, 'state': 'Booted', 'dataPath': str(root / 'data')}]}}
                live = {'pid': 123, 'identity': 'identity', 'protocol': 1, 'ready': True, 'udid': UDID}
                argv = ['widget-place.py', UDID, 'org.example.widgets', 'MissingKind' if reject_preflight else 'ExampleKind', 'small', '--exclusive', '--state-dir', str(root / 'cache')]
                published = []
                original_atomic = widget_place.atomic_json
                def details(identifiers):
                    return dict(identifiers, iconClass='SBWidgetIcon', widgetIdentityVerified=True)
                def publish(path, payload):
                    original_atomic(path, payload)
                    if path.name != 'command.json':
                        return
                    published.append(payload)
                    response = {'nonce': payload['nonce'], 'pid': 123}
                    if payload['mode'] == 'validate':
                        if reject_preflight:
                            response.update(status='error', error='MissingDescriptor: requested MissingKind is not installed')
                        else:
                            response.update(status='validated', targets=[details(target) for target in payload['targets']], desired=dict(payload['desired'], descriptor='registered supported descriptor'))
                    elif payload['mode'] == 'remove':
                        response.update(details(widget_place.persisted_target(other)), status='removal_submitted', action='remove')
                        state_path.write_bytes(plistlib.dumps({'iconLists': [['org.example.app', desired, unrelated]]}))
                    else:
                        response.update(details(widget_place.persisted_target(desired)), status='submitted', action='reveal')
                    original_atomic(path.with_name('response.json'), response)
                with patch.object(widget_place.sys, 'argv', argv), patch.object(widget_place, 'command', return_value=(json.dumps(listing), 0)), patch.object(widget_place, 'springboard_target', return_value='user/501/com.apple.SpringBoard'), patch.object(widget_place, 'springboard_pid', return_value=123), patch.object(widget_place, 'heartbeat', return_value=live), patch.object(widget_place, 'compile_worker', return_value=(root / 'worker.dylib', 'identity')) as compile_worker, patch.object(widget_place, 'atomic_json', side_effect=publish), patch.object(widget_place, 'sim') as sim, contextlib.redirect_stdout(io.StringIO()) as output:
                    self.assertEqual(widget_place.main(), 1 if reject_preflight else 0)
                compile_worker.assert_called_once()
                sim.assert_not_called()
                self.assertEqual([payload['mode'] for payload in published], ['validate'] if reject_preflight else ['validate', 'remove', 'ensure'])
                self.assertEqual(published[0]['targets'], [widget_place.persisted_target(desired), widget_place.persisted_target(other)])
                if reject_preflight:
                    self.assertEqual(published[0]['desired']['kind'], 'MissingKind')
                    self.assertEqual(plistlib.loads(state_path.read_bytes()), before)
                else:
                    self.assertEqual(len({payload['nonce'] for payload in published}), 3)
                    self.assertEqual(len(json.loads(output.getvalue())['exclusive_removals']), 1)
                widget_place.RESULT.clear()

    def test_existing_reveal_rejects_replaced_persisted_widget_of_same_tuple(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            state_path = root / 'data/Library/SpringBoard/IconState.plist'
            state_path.parent.mkdir(parents=True)
            state_path.write_bytes(plistlib.dumps({'iconLists': [[widget()]]}))
            listing = {'devices': {'runtime': [{'udid': UDID, 'state': 'Booted', 'dataPath': str(root / 'data')}]}}
            live = {'pid': 123, 'identity': 'identity', 'protocol': 1, 'ready': True, 'udid': UDID}
            argv = ['widget-place.py', UDID, 'org.example.widgets', 'ExampleKind', 'small', '--state-dir', str(root / 'cache')]
            original_atomic = widget_place.atomic_json
            def publish(path, payload):
                original_atomic(path, payload)
                if path.name == 'command.json':
                    response = dict(widget_place.persisted_target(widget()), nonce=payload['nonce'], pid=123, status='submitted', iconClass='SBWidgetIcon', widgetIdentityVerified=True, action='reveal')
                    state_path.write_bytes(plistlib.dumps({'iconLists': [[dict(widget(), displayIdentifier='44444444-4444-4444-4444-444444444444', uniqueIdentifier='55555555-5555-5555-5555-555555555555')]]}))
                    original_atomic(path.with_name('response.json'), response)
            with patch.object(widget_place.sys, 'argv', argv), patch.object(widget_place, 'command', return_value=(json.dumps(listing), 0)), patch.object(widget_place, 'springboard_target', return_value='user/501/com.apple.SpringBoard'), patch.object(widget_place, 'springboard_pid', return_value=123), patch.object(widget_place, 'heartbeat', return_value=live), patch.object(widget_place, 'compile_worker', return_value=(root / 'worker.dylib', 'identity')), patch.object(widget_place, 'atomic_json', side_effect=publish), patch.object(widget_place, 'sim') as sim, contextlib.redirect_stdout(io.StringIO()) as output:
                self.assertEqual(widget_place.main(), 2)
            sim.assert_not_called()
            self.assertEqual(json.loads(output.getvalue())['status'], 'reveal_persistence_unverified')

    def test_batch_validation_requires_desired_descriptor_and_family_echo(self):
        target = widget_place.persisted_target(widget())
        desired = {'extension': 'org.example.widgets', 'kind': 'ExampleKind', 'size': 'small'}
        response = {'status': 'validated', 'targets': [dict(target, iconClass='SBWidgetIcon', widgetIdentityVerified=True)]}
        with self.assertRaises(ValueError):
            widget_place.validate_target_batch(response, [target], desired)
        response['desired'] = dict(desired, descriptor='registered supported descriptor')
        widget_place.validate_target_batch(response, [target], desired)
        response['desired']['size'] = 'medium'
        with self.assertRaises(ValueError):
            widget_place.validate_target_batch(response, [target], desired)

    def test_top_position_preserves_same_page_and_other_home_identities(self):
        target = widget_place.persisted_target(widget())
        before = {'iconLists': [['org.first'], ['org.second', widget(), 'org.third']]}
        self.assertEqual(widget_place.home_widget_position(before, target), (1, 1))
        after = {'iconLists': [['org.first'], [widget(), 'org.second', 'org.third']]}
        self.assertEqual(widget_place.positioning_outcome(before, after, target), (True, None))
        cross_page = {'iconLists': [[widget(), 'org.first'], ['org.second', 'org.third']]}
        lost_entry = {'iconLists': [['org.first'], [widget(), 'org.second']]}
        self.assertFalse(widget_place.positioning_outcome(before, cross_page, target)[0])
        self.assertFalse(widget_place.positioning_outcome(before, lost_entry, target)[0])
        self.assertFalse(widget_place.positioning_outcome(before, before, target)[0])
        with self.assertRaises(ValueError):
            widget_place.home_widget_position({'iconLists': [[{'nested': widget()}]]}, target)

    def test_top_position_waits_for_persisted_layout_flush(self):
        target = widget_place.persisted_target(widget())
        before = {'iconLists': [['org.app', widget()]]}
        after = {'iconLists': [[widget(), 'org.app']]}
        with tempfile.TemporaryDirectory() as directory:
            state_path = Path(directory) / 'IconState.plist'
            state_path.write_bytes(plistlib.dumps(before))
            def flush(seconds):
                state_path.write_bytes(plistlib.dumps(after))
            with patch.object(widget_place.time, 'sleep', side_effect=flush):
                verified, error, path, actual, _ = widget_place.wait_for_position([state_path], before, target)
            self.assertTrue(verified)
            self.assertIsNone(error)
            self.assertEqual(path, state_path)
            self.assertEqual(actual, after)

    def test_replacement_requires_fresh_ids_and_preserves_other_entries(self):
        old = widget()
        new = dict(widget(), displayIdentifier='66666666-6666-6666-6666-666666666666', uniqueIdentifier='77777777-7777-7777-7777-777777777777')
        previous = widget_place.persisted_target(old)
        current = widget_place.persisted_target(new)
        before = {'iconLists': [['org.app', old]]}
        after = {'iconLists': [['org.app', new]]}
        self.assertEqual(widget_place.replacement_outcome(before, after, previous, current, [previous]), (True, None))
        self.assertFalse(widget_place.replacement_outcome(before, before, previous, previous, [previous])[0])
        self.assertFalse(widget_place.replacement_outcome(before, {'iconLists': [[new]]}, previous, current, [previous])[0])

    def test_replace_recreates_desired_tuple_and_descriptor_failure_removes_nothing(self):
        for reject_descriptor in (False, True):
            with self.subTest(reject_descriptor=reject_descriptor), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                old = widget()
                other = dict(widget(kind='OtherKind', size='medium'), displayIdentifier='44444444-4444-4444-4444-444444444444', uniqueIdentifier='55555555-5555-5555-5555-555555555555')
                new = dict(widget(), displayIdentifier='66666666-6666-6666-6666-666666666666', uniqueIdentifier='77777777-7777-7777-7777-777777777777')
                before = {'iconLists': [['org.app', old, other]]}
                state_path = root / 'data/Library/SpringBoard/IconState.plist'
                state_path.parent.mkdir(parents=True)
                state_path.write_bytes(plistlib.dumps(before))
                listing = {'devices': {'runtime': [{'udid': UDID, 'state': 'Booted', 'dataPath': str(root / 'data')}]}}
                live = {'pid': 123, 'identity': 'identity', 'protocol': 1, 'ready': True, 'udid': UDID}
                argv = ['widget-place.py', UDID, 'org.example.widgets', 'ExampleKind', 'small', '--replace', '--state-dir', str(root / 'cache')]
                published = []
                original_atomic = widget_place.atomic_json
                def details(item):
                    return dict(widget_place.persisted_target(item), iconClass='SBWidgetIcon', widgetIdentityVerified=True)
                def publish(path, payload):
                    original_atomic(path, payload)
                    if path.name != 'command.json':
                        return
                    published.append(payload)
                    response = {'nonce': payload['nonce'], 'pid': 123}
                    if payload['mode'] == 'validate':
                        if reject_descriptor:
                            response.update(status='error', error='MissingDescriptor')
                        else:
                            response.update(status='validated', targets=[details(old)], desired=dict(payload['desired'], descriptor='registered supported descriptor'))
                    elif payload['mode'] == 'remove':
                        response.update(details(old), status='removal_submitted', action='remove')
                        state_path.write_bytes(plistlib.dumps({'iconLists': [['org.app', other]]}))
                    elif 'iconIdentifier' not in payload:
                        response.update(status='submitted')
                        state_path.write_bytes(plistlib.dumps({'iconLists': [['org.app', other, new]]}))
                    else:
                        response.update(details(new), status='submitted', action='reveal')
                    original_atomic(path.with_name('response.json'), response)
                with patch.object(widget_place.sys, 'argv', argv), patch.object(widget_place, 'command', return_value=(json.dumps(listing), 0)), patch.object(widget_place, 'springboard_target', return_value='user/501/com.apple.SpringBoard'), patch.object(widget_place, 'springboard_pid', return_value=123), patch.object(widget_place, 'heartbeat', return_value=live), patch.object(widget_place, 'compile_worker', return_value=(root / 'worker.dylib', 'identity')) as compile_worker, patch.object(widget_place, 'atomic_json', side_effect=publish), patch.object(widget_place, 'sim') as sim, contextlib.redirect_stdout(io.StringIO()) as output:
                    self.assertEqual(widget_place.main(), 1 if reject_descriptor else 0)
                compile_worker.assert_called_once()
                sim.assert_not_called()
                self.assertEqual([payload['mode'] for payload in published], ['validate'] if reject_descriptor else ['validate', 'remove', 'ensure', 'ensure'])
                self.assertEqual(published[0]['targets'], [widget_place.persisted_target(old)])
                result = json.loads(output.getvalue())
                if reject_descriptor:
                    self.assertEqual(plistlib.loads(state_path.read_bytes()), before)
                    self.assertEqual(result['status'], 'replace_preflight_rejected')
                else:
                    self.assertNotIn('iconIdentifier', published[2])
                    self.assertEqual(published[3]['iconIdentifier'], new['displayIdentifier'])
                    self.assertEqual(result['status'], 'verified')
                    self.assertEqual(result['iconstate_matches'], [new])
                    self.assertEqual(plistlib.loads(state_path.read_bytes())['iconLists'][0], ['org.app', other, new])
                    self.assertEqual(len(result['replace_removals']), 1)
                widget_place.RESULT.clear()

    def test_configuration_envelope_binds_all_ids_and_preserves_full_entities(self):
        expected = dict(widget_place.persisted_target(widget()), udid=UDID, extension='org.example.widgets', container='org.example.app', kind='ExampleKind', size='small')
        parameters = {'selectedItem': {'identifier': 'opaque-id', 'title': {'key': 'Example'}, 'image': {'uri': 'intents-remote-image-proxy:?proxyIdentifier=preserve.png', 'renderingMode': 1}}, 'unknown': {'nested': [None, True, 1, 1.25]}}
        envelope = dict(expected, schemaVersion=1, intent={'intentClass': 'INAppIntent', 'appBundleIdentifier': 'org.example.app', 'extensionBundleIdentifier': 'org.example.widgets', 'appIntentIdentifier': 'ExampleSettings', 'parameters': parameters})
        self.assertEqual(widget_place.validate_configuration(envelope, expected), envelope)
        self.assertEqual(widget_place.validate_configuration(json.loads(json.dumps(envelope)), expected)['intent']['parameters'], parameters)
        for key in expected:
            with self.subTest(key=key), self.assertRaises(ValueError):
                widget_place.validate_configuration(dict(envelope, **{key: 'wrong'}), expected)
        for invalid_intent in (dict(envelope['intent'], intentClass='INIntent'), dict(envelope['intent'], appBundleIdentifier='org.other'), dict(envelope['intent'], extensionBundleIdentifier='org.other.widgets'), dict(envelope['intent'], parameters=[])):
            with self.assertRaises(ValueError):
                widget_place.validate_configuration(dict(envelope, intent=invalid_intent), expected)
        with self.assertRaises(ValueError):
            widget_place.validate_configuration(dict(envelope, schemaVersion=True), expected)

    def test_export_emits_configuration_mode_and_writes_exact_roundtrip_without_mutation(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            before = {'iconLists': [['org.app', widget()]]}
            state_path = root / 'data/Library/SpringBoard/IconState.plist'
            state_path.parent.mkdir(parents=True)
            state_path.write_bytes(plistlib.dumps(before))
            destination = root / 'widget configuration.json'
            listing = {'devices': {'runtime': [{'udid': UDID, 'state': 'Booted', 'dataPath': str(root / 'data')}]}}
            live = {'pid': 123, 'identity': 'identity', 'protocol': 1, 'ready': True, 'udid': UDID}
            argv = ['widget-place.py', UDID, 'org.example.widgets', 'ExampleKind', 'small', '--export-config', str(destination), '--state-dir', str(root / 'cache')]
            original_atomic = widget_place.atomic_json
            commands = []
            expected_configuration = None
            def publish(path, payload):
                nonlocal expected_configuration
                original_atomic(path, payload)
                if path.name != 'command.json':
                    return
                commands.append(payload)
                self.assertEqual(payload['mode'], 'exportConfiguration')
                parameters = {'selectedItem': {'identifier': 'opaque-id', 'image': {'uri': 'intents-remote-image-proxy:?proxyIdentifier=preserve.png'}}}
                expected_configuration = {key: payload[key] for key in ('udid', 'extension', 'container', 'kind', 'size', 'iconIdentifier', 'widgetIdentifier')}
                expected_configuration.update(schemaVersion=1, intent={'intentClass': 'INAppIntent', 'appBundleIdentifier': 'org.example.app', 'extensionBundleIdentifier': 'org.example.widgets', 'appIntentIdentifier': 'ExampleSettings', 'parameters': parameters})
                response = dict(widget_place.persisted_target(widget()), nonce=payload['nonce'], pid=123, status='configuration_exported', iconClass='SBWidgetIcon', widgetIdentityVerified=True, configuration=expected_configuration, roundtripVerified=True, roundtrip=expected_configuration['intent'])
                original_atomic(path.with_name('response.json'), response)
            with patch.object(widget_place.sys, 'argv', argv), patch.object(widget_place, 'command', return_value=(json.dumps(listing), 0)), patch.object(widget_place, 'springboard_target', return_value='user/501/com.apple.SpringBoard'), patch.object(widget_place, 'springboard_pid', return_value=123), patch.object(widget_place, 'heartbeat', return_value=live), patch.object(widget_place, 'compile_worker', return_value=(root / 'worker.dylib', 'identity')), patch.object(widget_place, 'atomic_json', side_effect=publish), patch.object(widget_place, 'sim') as sim, contextlib.redirect_stdout(io.StringIO()) as output:
                self.assertEqual(widget_place.main(), 0)
            sim.assert_not_called()
            self.assertEqual(len(commands), 1)
            self.assertEqual(widget_place.read_json(destination), expected_configuration)
            self.assertEqual(plistlib.loads(state_path.read_bytes()), before)
            self.assertEqual(json.loads(output.getvalue())['status'], 'configuration_exported')

    def test_apply_binds_old_ids_reads_new_uuid_and_preserves_other_home_entries(self):
        for corrupt_other in (False, True):
            with self.subTest(corrupt_other=corrupt_other), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                old = widget()
                new = dict(old, uniqueIdentifier='44444444-4444-4444-4444-444444444444')
                before = {'iconLists': [['org.app', old]]}
                state_path = root / 'data/Library/SpringBoard/IconState.plist'
                state_path.parent.mkdir(parents=True)
                state_path.write_bytes(plistlib.dumps(before))
                bindings = dict(widget_place.persisted_target(old), udid=UDID, extension='org.example.widgets', container='org.example.app', kind='ExampleKind', size='small')
                intent = {'intentClass': 'INAppIntent', 'appBundleIdentifier': 'org.example.app', 'extensionBundleIdentifier': 'org.example.widgets', 'appIntentIdentifier': 'ExampleSettings', 'parameters': {'entity': {'identifier': 'opaque', 'image': {'uri': 'preserved-uri'}}}}
                configuration = dict(bindings, schemaVersion=1, intent=intent)
                source = root / 'configuration.json'
                source.write_text(json.dumps(configuration))
                listing = {'devices': {'runtime': [{'udid': UDID, 'state': 'Booted', 'dataPath': str(root / 'data')}]}}
                live = {'pid': 123, 'identity': 'identity', 'protocol': 1, 'ready': True, 'udid': UDID}
                argv = ['widget-place.py', UDID, 'org.example.widgets', 'ExampleKind', 'small', '--apply-config', str(source), '--state-dir', str(root / 'cache')]
                original_atomic = widget_place.atomic_json
                commands = []
                def publish(path, payload):
                    original_atomic(path, payload)
                    if path.name != 'command.json':
                        return
                    commands.append(payload)
                    self.assertEqual(payload['mode'], 'applyConfiguration')
                    self.assertEqual(payload['configuration'], configuration)
                    restored = dict(configuration, widgetIdentifier=new['uniqueIdentifier'])
                    response = dict(widget_place.persisted_target(old), nonce=payload['nonce'], pid=123, status='configuration_applied', iconClass='SBWidgetIcon', widgetIdentityVerified=True, appliedWidgetIdentifier=new['uniqueIdentifier'], archiving=True, configuration=restored, roundtripVerified=True, roundtrip=intent)
                    state_path.write_bytes(plistlib.dumps({'iconLists': [[new] if corrupt_other else ['org.app', new]]}))
                    original_atomic(path.with_name('response.json'), response)
                with patch.object(widget_place.sys, 'argv', argv), patch.object(widget_place, 'command', return_value=(json.dumps(listing), 0)), patch.object(widget_place, 'springboard_target', return_value='user/501/com.apple.SpringBoard'), patch.object(widget_place, 'springboard_pid', return_value=123), patch.object(widget_place, 'heartbeat', return_value=live), patch.object(widget_place, 'compile_worker', return_value=(root / 'worker.dylib', 'identity')), patch.object(widget_place, 'atomic_json', side_effect=publish), patch.object(widget_place, 'sim') as sim, contextlib.redirect_stdout(io.StringIO()) as output:
                    if corrupt_other:
                        with self.assertRaisesRegex(ValueError, 'other Home identities'):
                            widget_place.main()
                    else:
                        self.assertEqual(widget_place.main(), 0)
                        result = json.loads(output.getvalue())
                        self.assertEqual(result['configuration']['widgetIdentifier'], new['uniqueIdentifier'])
                        self.assertEqual(result['configuration']['intent'], intent)
                        self.assertEqual(result['status'], 'configuration_applied')
                sim.assert_not_called()
                self.assertEqual(len(commands), 1)
                self.assertEqual(widget_place.read_json(source), configuration)
                widget_place.RESULT.clear()

    def test_only_explicit_available_booted_device_is_selected(self):
        device = {'udid': UDID, 'state': 'Booted'}
        self.assertEqual(widget_place.select_booted_device([device], UDID), device)
        for devices in ([], [dict(device, state='Shutdown')], [dict(device, isAvailable=False)], [device, device]):
            with self.assertRaises(RuntimeError):
                widget_place.select_booted_device(devices, UDID)

    def test_runtime_target_rejects_non_ios_and_injected_architecture(self):
        identifier = 'com.apple.CoreSimulator.SimRuntime.iOS-27-0'
        listing = {'devices': {identifier: [{'udid': UDID}]}}
        runtimes = {'runtimes': [{'identifier': identifier, 'version': '27.0', 'buildversion': 'test'}]}
        self.assertEqual(widget_place.target_identity(listing, runtimes, UDID, 'arm64')[0], 'arm64-apple-ios27.0-simulator')
        with self.assertRaises(ValueError):
            widget_place.target_identity(listing, runtimes, UDID, 'arm64; touch /tmp/no')
        with self.assertRaises(ValueError):
            widget_place.target_identity({'devices': {'tvOS': [{'udid': UDID}]}}, {'runtimes': []}, UDID, 'arm64')

    def test_runtime_metadata_checks_native_architecture_and_override(self):
        identifier = 'com.apple.CoreSimulator.SimRuntime.iOS-27-0'
        listing = {'devices': {identifier: [{'udid': UDID}]}}
        runtimes = {'runtimes': [{'identifier': identifier, 'version': '27.0', 'supportedArchitectures': ['arm64']}]}
        with patch.object(widget_place.platform, 'machine', return_value='arm64'):
            self.assertEqual(widget_place.target_identity(listing, runtimes, UDID)[0], 'arm64-apple-ios27.0-simulator')
        with patch.object(widget_place.platform, 'machine', return_value='x86_64'):
            with self.assertRaises(ValueError):
                widget_place.target_identity(listing, runtimes, UDID)
            self.assertEqual(widget_place.target_identity(listing, runtimes, UDID, 'arm64')[0], 'arm64-apple-ios27.0-simulator')

    def test_compilation_is_cached_and_never_spawns_simulator_utilities(self):
        identifier = 'com.apple.CoreSimulator.SimRuntime.iOS-27-0'
        listing = {'devices': {identifier: [{'udid': UDID}]}}
        runtimes = {'runtimes': [{'identifier': identifier, 'version': '27.0', 'supportedArchitectures': ['arm64']}]}
        compilations = []
        def host_command(arguments, timeout=15):
            if arguments == ['xcrun', 'simctl', 'list', 'runtimes', '--json']:
                return json.dumps(runtimes), 0
            if '--show-sdk-path' in arguments:
                return '/selected Xcode/Simulator SDK', 0
            if '--find' in arguments:
                return '/selected Xcode/clang', 0
            if '--show-sdk-version' in arguments:
                return '27.0', 0
            if '--version' in arguments:
                return 'test clang version', 0
            if '-dynamiclib' in arguments:
                compilations.append(arguments)
                Path(arguments[arguments.index('-o') + 1]).write_bytes(b'compiled')
                return '', 0
            self.fail(f'Unexpected command: {arguments}')
        with tempfile.TemporaryDirectory() as directory, patch.object(widget_place, 'command', side_effect=host_command), patch.object(widget_place, 'sim') as sim:
            first = widget_place.compile_worker(Path(directory), UDID, json.dumps(listing), 'arm64')
            runtimes['runtimes'][0]['lastUsedAt'] = 'volatile metadata changed'
            second = widget_place.compile_worker(Path(directory), UDID, json.dumps(listing), 'arm64')
            self.assertEqual(first, second)
            self.assertTrue(first[0].is_file())
            self.assertEqual(len(compilations), 1)
            self.assertEqual(compilations[0][compilations[0].index('-target') + 1], 'arm64-apple-ios27.0-simulator')
            sim.assert_not_called()

    def test_subprocess_arguments_are_literal_without_shell(self):
        argument = 'kind; $(touch /tmp/no) `echo no` with spaces'
        with patch.object(widget_place.subprocess, 'run') as run:
            run.return_value.returncode = 0
            run.return_value.stdout = 'ok'
            widget_place.command(['example', argument])
            self.assertEqual(run.call_args.args[0], ['example', argument])
            self.assertNotIn('shell', run.call_args.kwargs)

    def test_state_path_with_spaces_and_shell_characters_stays_literal(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'cache $(nothing); spaces'
            self.assertEqual(widget_place.prepare_directory(path), path.resolve())
            link = Path(directory) / 'link'
            link.symlink_to(path)
            with self.assertRaises(ValueError):
                widget_place.prepare_directory(link)
            path.chmod(0o777)
            with self.assertRaises(ValueError):
                widget_place.prepare_directory(path)

    def test_json_validation_and_atomic_write(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'command.json'
            widget_place.atomic_json(path, {'kind': 'test'})
            self.assertEqual(widget_place.read_json(path), {'kind': 'test'})
            self.assertEqual([item.name for item in path.parent.iterdir()], ['command.json'])
            for data in ('{', '{"timestamp": NaN}', '{"timestamp": Infinity}'):
                path.write_text(data)
                self.assertIsNone(widget_place.read_json(path))

    def test_response_requires_matching_nonce_pid_and_status(self):
        response = {'nonce': 'nonce', 'pid': 123, 'status': 'submitted'}
        self.assertEqual(widget_place.validate_response(response, 'nonce', 123), response)
        for candidate in (dict(response, nonce='old'), dict(response, pid=124), dict(response, pid=True),
                          dict(response, status='unknown'), dict(response, status='error')):
            with self.assertRaises(ValueError):
                widget_place.validate_response(candidate, 'nonce', 123)

    def test_targeted_response_must_return_exact_persisted_identifiers(self):
        identifiers = widget_place.persisted_target(widget())
        response = dict(identifiers, nonce='nonce', pid=123, status='removal_submitted', iconClass='SBWidgetIcon', widgetIdentityVerified=True)
        self.assertEqual(widget_place.validate_response(response, 'nonce', 123, identifiers), response)
        with self.assertRaises(ValueError):
            widget_place.validate_response(dict(response, iconIdentifier='different'), 'nonce', 123, identifiers)

    def test_heartbeat_requires_device_freshness_and_live_integer_pid(self):
        with tempfile.TemporaryDirectory() as directory:
            session = Path(directory) / UDID
            session.mkdir()
            heartbeat = {'udid': UDID, 'timestamp': time.time(), 'pid': os.getpid()}
            path = session / 'heartbeat.json'
            widget_place.atomic_json(path, heartbeat)
            self.assertIsNotNone(widget_place.heartbeat(session))
            for candidate in (dict(heartbeat, udid='other'), dict(heartbeat, timestamp=0),
                              dict(heartbeat, pid=True), dict(heartbeat, timestamp='nan'), dict(heartbeat, pid=0)):
                widget_place.atomic_json(path, candidate)
                self.assertIsNone(widget_place.heartbeat(session))

    def test_duplicate_preflight_sends_no_device_spawn_or_compile(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            state = root / 'data/Library/SpringBoard/IconState.plist'
            state.parent.mkdir(parents=True)
            state.write_bytes(plistlib.dumps({'iconLists': [[widget(), widget()]]}))
            listing = {'devices': {'runtime': [{'udid': UDID, 'state': 'Booted', 'dataPath': str(root / 'data')}]}}
            argv = ['widget-place.py', UDID, 'org.example.widgets', 'ExampleKind', 'small', '--state-dir', str(root / 'cache')]
            with patch.object(widget_place.sys, 'argv', argv), patch.object(widget_place, 'command', return_value=(json.dumps(listing), 0)), patch.object(widget_place, 'springboard_target', return_value='user/501/com.apple.SpringBoard'), patch.object(widget_place, 'sim') as sim, patch.object(widget_place, 'compile_worker') as compile_worker, contextlib.redirect_stdout(io.StringIO()) as output:
                self.assertEqual(widget_place.main(), 2)
            sim.assert_not_called()
            compile_worker.assert_not_called()
            self.assertEqual(json.loads(output.getvalue())['status'], 'duplicate_existing_widgets')

    def test_simulated_uid_is_used_for_target_and_must_be_numeric(self):
        with patch.object(widget_place, 'sim', return_value=('502\n', 0)) as sim:
            self.assertEqual(widget_place.springboard_target(UDID), 'user/502/com.apple.SpringBoard')
            sim.assert_called_once_with(UDID, 'launchctl', 'manageruid')
        with patch.object(widget_place, 'sim', return_value=('502; anything', 0)):
            with self.assertRaises(RuntimeError):
                widget_place.springboard_target(UDID)

    def test_explicit_launch_domain_does_not_run_discovery(self):
        with patch.object(widget_place, 'sim') as sim:
            self.assertEqual(widget_place.springboard_target(UDID, 'user/502'), 'user/502/com.apple.SpringBoard')
            sim.assert_not_called()
        for domain in ('system', 'user/501/other', 'user/501; anything'):
            with self.assertRaises(ValueError):
                widget_place.springboard_target(UDID, domain)

    def test_pending_injection_unload_clears_environment_before_restart(self):
        with tempfile.TemporaryDirectory() as directory:
            session = Path(directory) / 'sessions' / UDID
            session.mkdir(parents=True)
            target = 'user/501/com.apple.SpringBoard'
            widget_place.atomic_json(session / 'injection.json', {'udid': UDID, 'target': target, 'pending': True})
            listing = {'devices': {'runtime': [{'udid': UDID, 'state': 'Booted'}]}}
            argv = ['widget-place.py', UDID, '--unload', '--state-dir', directory]
            with patch.object(widget_place.sys, 'argv', argv), patch.object(widget_place, 'command', return_value=(json.dumps(listing), 0)), patch.object(widget_place, 'springboard_target', return_value=target), patch.object(widget_place, 'springboard_pid', side_effect=[123, 124]), patch.object(widget_place, 'sim') as sim, patch.object(widget_place.time, 'sleep'), patch.object(widget_place.time, 'monotonic', side_effect=[0, 0, 0, 0, 0, 4, 4]), contextlib.redirect_stdout(io.StringIO()) as output:
                self.assertEqual(widget_place.main(), 0)
            self.assertEqual(sim.call_args_list[0].args[:5], (UDID, 'launchctl', 'debug', target, '--environment'))
            self.assertIn('DYLD_INSERT_LIBRARIES=', sim.call_args_list[0].args)
            self.assertEqual(sim.call_args_list[1].args, (UDID, 'launchctl', 'kickstart', '-k', target))
            self.assertFalse((session / 'injection.json').exists())
            self.assertEqual(json.loads(output.getvalue())['status'], 'unloaded')

    def test_prepare_reuses_worker_without_runtime_command_or_iconstate(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            live = {'pid': 123, 'identity': 'identity', 'protocol': 1, 'ready': True, 'udid': UDID}
            listing = {'devices': {'runtime': [{'udid': UDID, 'state': 'Booted'}]}}
            argv = ['widget-place.py', UDID, '--prepare', '--state-dir', directory]
            original_atomic = widget_place.atomic_json
            published = []
            def publish(path, payload):
                published.append(path.name)
                original_atomic(path, payload)
            with patch.object(widget_place.sys, 'argv', argv), patch.object(widget_place, 'command', return_value=(json.dumps(listing), 0)), patch.object(widget_place, 'springboard_target', return_value='user/501/com.apple.SpringBoard'), patch.object(widget_place, 'springboard_pid', return_value=123), patch.object(widget_place, 'heartbeat', return_value=live), patch.object(widget_place, 'compile_worker', return_value=(root / 'worker.dylib', 'identity')), patch.object(widget_place, 'load_iconstate') as preflight, patch.object(widget_place, 'atomic_json', side_effect=publish), patch.object(widget_place, 'sim') as sim, contextlib.redirect_stdout(io.StringIO()) as output:
                self.assertEqual(widget_place.main(), 0)
            preflight.assert_not_called()
            sim.assert_not_called()
            self.assertEqual(published, ['injection.json'])
            result = json.loads(output.getvalue())
            self.assertEqual(result['status'], 'ready')
            self.assertEqual(result['timings']['injection_restart_seconds'], 0)
            self.assertNotIn('response', result)

    def test_inspect_uses_warm_worker_without_iconstate_or_placement_payload(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            session = root / 'sessions' / UDID
            session.mkdir(parents=True)
            live = {'pid': 123, 'identity': 'identity', 'protocol': 1, 'ready': True, 'udid': UDID}
            listing = {'devices': {'runtime': [{'udid': UDID, 'state': 'Booted'}]}}
            argv = ['widget-place.py', UDID, '--inspect', '--state-dir', directory]
            payloads = []
            original_atomic = widget_place.atomic_json
            def publish(path, payload):
                original_atomic(path, payload)
                if path.name == 'command.json':
                    payloads.append(payload)
                    original_atomic(path.with_name('response.json'), {'nonce': payload['nonce'], 'pid': 123, 'status': 'inspected', 'inspection': {'classes': {}}})
            with patch.object(widget_place.sys, 'argv', argv), patch.object(widget_place, 'command', return_value=(json.dumps(listing), 0)), patch.object(widget_place, 'springboard_target', return_value='user/501/com.apple.SpringBoard'), patch.object(widget_place, 'springboard_pid', return_value=123), patch.object(widget_place, 'heartbeat', return_value=live), patch.object(widget_place, 'compile_worker', return_value=(root / 'worker.dylib', 'identity')), patch.object(widget_place, 'load_iconstate') as preflight, patch.object(widget_place, 'atomic_json', side_effect=publish), patch.object(widget_place, 'sim') as sim, contextlib.redirect_stdout(io.StringIO()) as output:
                self.assertEqual(widget_place.main(), 0)
            preflight.assert_not_called()
            sim.assert_not_called()
            self.assertEqual(set(payloads[0]), {'nonce', 'mode'})
            self.assertEqual(payloads[0]['mode'], 'inspect')
            self.assertFalse((session / 'command.json').exists())
            self.assertEqual(json.loads(output.getvalue())['status'], 'inspected')

    def test_unload_without_our_worker_does_not_restart(self):
        with tempfile.TemporaryDirectory() as directory:
            listing = {'devices': {'runtime': [{'udid': UDID, 'state': 'Booted'}]}}
            argv = ['widget-place.py', UDID, '--unload', '--state-dir', directory]
            with patch.object(widget_place.sys, 'argv', argv), patch.object(widget_place, 'command', return_value=(json.dumps(listing), 0)), patch.object(widget_place, 'springboard_target', return_value='user/501/com.apple.SpringBoard'), patch.object(widget_place, 'springboard_pid', return_value=123), patch.object(widget_place, 'sim') as sim, contextlib.redirect_stdout(io.StringIO()) as output:
                self.assertEqual(widget_place.main(), 0)
            sim.assert_not_called()
            self.assertTrue(json.loads(output.getvalue())['no_op'])


if __name__ == '__main__':
    unittest.main()
