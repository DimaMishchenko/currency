#!/usr/bin/env python3
"""Plan/reconcile App Store drafts through the pinned asc CLI. Never submit review."""
import argparse
from fractions import Fraction
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import shutil
import struct
import subprocess
import sys
import tempfile

ASC_VERSION = '5.16.0'
PROFILES = {'iphone': 'APP_IPHONE_61', 'ipad': 'APP_IPAD_PRO_3GEN_129', 'watch': 'APP_WATCH_SERIES_10'}
DIMENSIONS = {'iphone': (1206, 2622), 'ipad': (2064, 2752), 'watch': (416, 496), 'duo-inner': (2853, 2007), 'duo-outer': (1398, 2034)}
FAMILIES = ['default', 'offline', 'travel', 'history', 'crypto', 'metals']
EDITABLE = {'PREPARE_FOR_SUBMISSION', 'DEVELOPER_REJECTED', 'REJECTED', 'METADATA_REJECTED'}
SCOPES = {'metadata', 'default', 'cpp', 'duo', 'header'}
INFO_FIELDS = {'name', 'subtitle', 'privacyPolicyUrl', 'privacyChoicesUrl'}
VERSION_FIELDS = {'description', 'keywords', 'promotionalText', 'marketingUrl', 'supportUrl', 'whatsNew'}


class UploadError(Exception):
    pass


def duo_presentation(metadata):
    presentation = metadata.get('duoPresentation')
    if not isinstance(presentation, dict) or set(presentation) != set(FAMILIES):
        raise UploadError('Duo presentation must select six approved images for every family')
    for profiles in presentation.values():
        if not isinstance(profiles, list) or len(profiles) != 6 or any(not isinstance(profile, str) or profile not in {'duo-inner', 'duo-outer'} for profile in profiles) or set(profiles) != {'duo-inner', 'duo-outer'}:
            raise UploadError('Duo presentation must select six ordered images using both displays')
    return presentation


def sha256(path):
    h = hashlib.sha256()
    with path.open('rb') as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b''):
            h.update(block)
    return h.hexdigest()


def confined(root, name):
    if not isinstance(name, str) or not name or '\\' in name or PurePosixPath(name).is_absolute() or any(p in ('', '.', '..') for p in name.split('/')):
        raise UploadError('Media manifest contains an invalid relative path')
    path = (root / name).resolve()
    if not path.is_relative_to(root.resolve()) or any(part.is_symlink() for part in [root / name, *(root / name).parents] if part.is_relative_to(root)):
        raise UploadError('Media path escapes its root or uses a symlink')
    return path


def validate_media(root, manifest, metadata):
    if manifest.get('schemaVersion') != 1 or metadata.get('schemaVersion') != 1 or metadata.get('families') != FAMILIES:
        raise UploadError('Unsupported manifest or metadata schema/families')
    if metadata.get('appId') != '6816213577' or len(metadata.get('locales', {})) != 18:
        raise UploadError('Expected Currency app ID and all 18 locales')
    duo_presentation(metadata)
    slots, hashes = {}, {}
    for item in manifest.get('placements', []):
        slot = (item['locale'], item['profile'], item['family'], item['order'])
        if slot in slots or item['locale'] not in metadata['locales'] or item['family'] not in FAMILIES or item['profile'] not in {*PROFILES, 'duo-inner', 'duo-outer'} or type(item['order']) is not int or item['order'] not in range(1, 7):
            raise UploadError('Invalid or duplicate screenshot placement')
        path = confined(root, item['path'])
        if path.suffix.lower() != '.png' or not path.is_file():
            raise UploadError('Screenshot must be a regular PNG')
        if path not in hashes:
            hashes[path] = sha256(path)
        validate_png(path, DIMENSIONS[item['profile']])
        if hashes[path] != item['sha256']:
            raise UploadError('Screenshot SHA-256 mismatch')
        slots[slot] = dict(item, file=path)
    expected = {(l, p, f, n) for l in metadata['locales'] for p in {*PROFILES, 'duo-inner', 'duo-outer'} for f in FAMILIES for n in range(1, 7)}
    if set(slots) != expected:
        raise UploadError('Media manifest must contain all 3240 screenshot placements')
    header = manifest.get('header', {})
    path = confined(root, header.get('path'))
    if path.suffix.lower() not in {'.mp4', '.m4v', '.mov'} or not path.is_file() or sha256(path) != header.get('sha256'):
        raise UploadError('Approved header video is missing or has the wrong hash')
    video = validate_video(path)
    return slots, dict(header, file=path, video=video)


def validate_png(path, dimensions):
    with path.open('rb') as stream:
        header = stream.read(33)
        if len(header) != 33 or header[:16] != b'\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR' or struct.unpack('>II', header[16:24]) != dimensions:
            raise UploadError('Screenshot PNG dimensions do not match its device profile')
        if header[25] not in {0, 2, 3}:
            raise UploadError('Screenshot PNG alpha channel is not allowed')
        while True:
            chunk = stream.read(8)
            if len(chunk) != 8:
                raise UploadError('Truncated screenshot PNG')
            size, kind = struct.unpack('>I4s', chunk)
            if kind == b'tRNS':
                raise UploadError('Screenshot PNG transparency is not allowed')
            if size > path.stat().st_size:
                raise UploadError('Invalid screenshot PNG chunk')
            stream.seek(size + 4, 1)
            if kind == b'IEND':
                return


def validate_video(path):
    try:
        result = subprocess.run(['ffprobe', '-v', 'error', '-show_streams', '-show_format', '-of', 'json', str(path)], text=True, capture_output=True, timeout=60, check=True)
        info = json.loads(result.stdout)
        videos = [s for s in info['streams'] if s.get('codec_type') == 'video']
        video = videos[0]
        fps = float(Fraction(video['avg_frame_rate']))
        if len(videos) != 1 or (video['width'], video['height']) != (3840, 1646) or abs(float(info['format']['duration']) - 15) > .1 or min(abs(fps - 30), abs(fps - 60)) > .01:
            raise ValueError()
        return {'fps': fps, 'duration': float(info['format']['duration']), 'audio': any(s.get('codec_type') == 'audio' for s in info['streams'])}
    except (OSError, subprocess.SubprocessError, ValueError, KeyError, IndexError, ZeroDivisionError):
        raise UploadError('Header must be the approved 15-second 3840x1646 video at 30/60 fps; install ffprobe and verify the export') from None


def safe_error_diagnostics(stdout, stderr, http_trace=False):
    statuses, codes, pointers = set(), set(), set()
    def status(value):
        text = str(value)
        if re.fullmatch('[0-9]{3}', text) and (int(text) in {401, 403, 404, 409, 422, 429} or 500 <= int(text) <= 599):
            statuses.add(text)
    decoder = json.JSONDecoder()
    for output in (stdout, stderr):
        sample = output[:262144]
        for index, start in enumerate(re.finditer(r'\{', sample)):
            if index >= 64:
                break
            try:
                payload, _ = decoder.raw_decode(sample, start.start())
            except (json.JSONDecodeError, RecursionError):
                continue
            errors = payload.get('errors') if isinstance(payload, dict) else None
            if not isinstance(errors, list):
                continue
            for error in errors[:20]:
                if not isinstance(error, dict):
                    continue
                status(error.get('status', ''))
                code = error.get('code')
                if isinstance(code, str) and re.fullmatch('[A-Z][A-Z0-9_.-]{0,159}', code):
                    codes.add(code)
                source = error.get('source')
                pointer = source.get('pointer') if isinstance(source, dict) else None
                if isinstance(pointer, str) and len(pointer) <= 180 and re.fullmatch(r'/(?:data|included)(?:/(?:[A-Za-z][A-Za-z0-9_-]*|[0-9]+))*', pointer):
                    pointers.add(pointer)
        if http_trace:
            for match in re.finditer(r'^level=INFO msg="← HTTP Response" status=([0-9]{3})(?: [^\r\n]*)?$', sample, re.MULTILINE):
                status(match[1])
    parts = []
    if statuses:
        parts.append('HTTP ' + ', '.join(sorted(statuses)))
    if codes:
        parts.append('code ' + ', '.join(sorted(codes)[:10]))
    if pointers:
        parts.append('pointer ' + ', '.join(sorted(pointers)[:10]))
    return ' (' + '; '.join(parts) + ')' if parts else ''


def safe_metadata_failure_summary(stdout):
    if len(stdout) > 1048576:
        return ''
    try:
        payload = json.loads(stdout)
    except (json.JSONDecodeError, RecursionError):
        return ''
    actions = payload.get('actions') if isinstance(payload, dict) else None
    if not isinstance(actions, list) or len(actions) > 200:
        return ''
    locales = {'de-DE', 'en-AU', 'en-CA', 'en-GB', 'en-US', 'es-ES', 'es-MX', 'fr-CA', 'fr-FR', 'it', 'ja', 'ko', 'pt-BR', 'ru', 'tr', 'uk', 'zh-Hans', 'zh-Hant'}
    scopes = {'app-info': INFO_FIELDS, 'version': VERSION_FIELDS}
    counts = {'succeeded': 0, 'failed': 0, 'skipped': 0}
    failures = []
    for action in actions:
        if not isinstance(action, dict) or any(not isinstance(action.get(key), str) for key in ('scope', 'locale', 'action', 'status')) or action.get('scope') not in scopes or action.get('locale') not in locales or action.get('action') not in {'create', 'update', 'delete', 'reconcile'} or action.get('status') not in counts:
            continue
        status = action['status']
        counts[status] += 1
        if status == 'failed':
            entry = {key: action[key] for key in ('scope', 'locale', 'action', 'status')}
            fields = action.get('desiredFields')
            if isinstance(fields, dict):
                entry['attemptedFields'] = sorted(set(fields) & scopes[action['scope']])
            error = action.get('error')
            if isinstance(error, str) and len(error) <= 16384 and 'the app name you entered is already being used' in error.casefold():
                entry['reason'] = 'app-name-already-used'
            failures.append(entry)
    if not any(counts.values()):
        return ''
    return ' metadataActions=' + json.dumps({'counts': counts, 'failures': failures}, separators=(',', ':'))


def safe_screenshot_conflict(set_id, actual, expected):
    def identifier(value):
        return value if isinstance(value, str) and re.fullmatch('[A-Za-z0-9-]{1,180}', value) else None
    assets = []
    for row in actual[:20]:
        attrs = row.get('attributes', {})
        checksum, size = attrs.get('sourceFileChecksum'), attrs.get('fileSize')
        delivery = attrs.get('assetDeliveryState')
        state = delivery.get('state') if isinstance(delivery, dict) else None
        resource_type = row.get('type')
        assets.append({
            'id': identifier(row.get('id')),
            'type': resource_type if resource_type == 'appScreenshots' else None,
            'checksum': checksum if isinstance(checksum, str) and re.fullmatch('[A-Fa-f0-9]{32}', checksum) else None,
            'fileSize': size if type(size) is int and 0 <= size <= 2**63 - 1 else None,
            'state': state if isinstance(state, str) and state in {'AWAITING_UPLOAD', 'UPLOAD_COMPLETE', 'COMPLETE', 'FAILED'} else None,
        })
    identifiers = {identifier(row.get('id')) for row in actual} - {None}
    states = [row.get('attributes', {}).get('assetDeliveryState') for row in actual]
    return {
        'setId': identifier(set_id), 'assetCount': len(actual), 'uniqueIdCount': len(identifiers),
        'completeCount': sum(isinstance(state, dict) and state.get('state') == 'COMPLETE' for state in states),
        'assets': assets, 'approvedChecksums': [{'order': order, 'checksum': checksum} for order, checksum in enumerate(expected, 1)],
    }


class CLI:
    """Capture all CLI output; signed upload URLs/private API errors never reach logs."""
    def __init__(self, executable='asc', apply=False, receipts=None):
        self.executable, self.apply = executable, apply
        self.receipts = receipts

    def receipt(self, event, result=None):
        if self.receipts is None:
            return
        identifiers = {}
        def scan(value):
            if isinstance(value, dict):
                for key, item in value.items():
                    if key in {'id', 'imageId', 'videoId', 'screenshotId', 'assetId', 'setId', 'localizationId'} and isinstance(item, str) and re.fullmatch('[A-Za-z0-9-]{1,180}', item):
                        identifiers.setdefault(key, []).append(item)
                    else:
                        scan(item)
            elif isinstance(value, list):
                for item in value:
                    scan(item)
        scan(result)
        self.receipts.parent.mkdir(parents=True, exist_ok=True)
        fd = os.open(self.receipts, os.O_WRONLY | os.O_APPEND | os.O_CREAT, 0o600)
        with os.fdopen(fd, 'a') as stream:
            stream.write(json.dumps({'event': event, 'resourceIds': identifiers}) + '\n')
            stream.flush()
            os.fsync(stream.fileno())

    def run(self, args, body=None, mutate=False, cwd=None):
        if mutate and not self.apply:
            raise UploadError('Internal safety guard refused a mutation during dry-run')
        env = os.environ.copy()
        for key in ('ASC_PROFILE', 'ASC_CONFIG_PATH', 'ASC_BYPASS_KEYCHAIN', 'ASC_PRIVATE_KEY_PATH', 'ASC_PRIVATE_KEY', 'ASC_DEBUG', 'ASC_DEBUG_HTTP'):
            env.pop(key, None)
        env['ASC_STRICT_AUTH'] = 'true'
        raw_api = len(args) >= 3 and args[0] == 'api' and args[1] in {'GET', 'POST', 'PATCH', 'DELETE'}
        metadata_apply = args[:2] == ['metadata', 'apply']
        http_trace = raw_api or metadata_apply
        env['ASC_DEBUG'] = 'api' if http_trace else 'false'
        try:
            if mutate:
                self.receipt('mutation-started')
            result = subprocess.run([self.executable, *args], input=None if body is None else json.dumps(body), text=True, capture_output=True, env=env, cwd=cwd, timeout=2100, check=False)
        except (OSError, subprocess.TimeoutExpired):
            raise UploadError('asc command could not finish; inspect remote draft state before retrying') from None
        if result.returncode:
            try:
                self.receipt('mutation-failed-inspect-before-retry', json.loads(result.stdout))
            except json.JSONDecodeError:
                self.receipt('mutation-failed-no-receipt-inspect-before-retry')
            diagnostic = safe_error_diagnostics(result.stdout, result.stderr, http_trace=http_trace)
            if metadata_apply:
                diagnostic += safe_metadata_failure_summary(result.stdout)
            raise UploadError('asc command failed' + diagnostic + '; inspect App Store Connect draft state before retrying (raw output suppressed)')
        try:
            value = json.loads(result.stdout) if result.stdout.strip() else {}
            if mutate:
                self.receipt('mutation-completed', value)
            return value
        except json.JSONDecodeError:
            raise UploadError('asc returned invalid JSON (raw output suppressed)') from None

    def api(self, method, path, body=None):
        args = ['api', method, path, '--output', 'json']
        if method == 'GET':
            args += ['--paginate'] if not path.partition('?')[0].endswith('/assetLibrary') else []
        else:
            args += ['--confirm', '--body-file', '-']
        return self.run(args, body, mutate=method != 'GET')


def relationship(kind, identifier):
    return {'data': {'type': kind, 'id': identifier}}


def resource(kind, attrs, relations=None, identifier=None):
    data = {'type': kind, 'attributes': attrs}
    if identifier:
        data['id'] = identifier
    if relations:
        data['relationships'] = relations
    return {'data': data}


def write_canonical_metadata(root, metadata, version):
    if not re.fullmatch('[A-Za-z0-9][A-Za-z0-9._-]{0,99}', version):
        raise UploadError('Metadata version is not a safe canonical directory name')
    for locale, values in metadata['locales'].items():
        if locale == 'default' or not re.fullmatch('[A-Za-z]{2,3}(?:-[A-Za-z0-9]{2,8})*', locale):
            raise UploadError('Metadata requires explicit supported locale files; default fallback is disabled')
        for relative, fields in (('app-info/' + locale + '.json', INFO_FIELDS), ('version/' + version + '/' + locale + '.json', VERSION_FIELDS)):
            selected = {key: value for key, value in values.items() if key in fields}
            if not selected:
                continue
            if any(not isinstance(value, str) or not value.strip() for value in selected.values()):
                raise UploadError('Metadata null values and empty field clears are disabled')
            target = confined(root, relative)
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text(json.dumps(selected, ensure_ascii=False, sort_keys=True) + '\n', encoding='utf-8')


def resolve_targets(cli, app_id, version_id=None, version_string=None, info_id=None):
    """Resolve only unique editable targets using optional restrictive filters."""
    def rows(relationship):
        values = cli.api('GET', '/v1/apps/' + app_id + '/' + relationship).get('data', [])
        if not isinstance(values, list):
            raise UploadError('Target discovery returned an invalid collection; inspect App Store Connect before retrying')
        return values

    versions = [v for v in rows('appStoreVersions') if v.get('attributes', {}).get('platform') == 'IOS' and v.get('attributes', {}).get('appStoreState') in EDITABLE and (not version_id or v.get('id') == version_id) and (not version_string or v.get('attributes', {}).get('versionString') == version_string)]
    if not versions:
        raise UploadError('No editable iOS version matches the requested filters. Inspect App Store Connect and create or select an editable draft; no version was created automatically.')
    if len(versions) != 1:
        raise UploadError('Multiple editable iOS versions match. Supply --version-id or --version-string to select one exact draft.')
    infos = [i for i in rows('appInfos') if i.get('attributes', {}).get('appStoreState') in EDITABLE and (not info_id or i.get('id') == info_id)]
    if not infos:
        raise UploadError('No editable app-info matches the requested filter. Inspect App Store Connect and select an editable app-info draft; no draft was created automatically.')
    if len(infos) != 1:
        raise UploadError('Multiple editable app-info resources match. Supply --app-info-id to select one exact draft.')
    target = {'versionId': versions[0].get('id'), 'versionString': versions[0].get('attributes', {}).get('versionString'), 'appInfoId': infos[0].get('id')}
    if any(not isinstance(target[k], str) or not re.fullmatch('[A-Za-z0-9-]+', target[k]) for k in ('versionId', 'appInfoId')) or not isinstance(target['versionString'], str) or not target['versionString'] or len(target['versionString']) > 100:
        raise UploadError('Target discovery returned invalid resource identifiers or version text; inspect App Store Connect before retrying')
    return target



class Planner:
    def __init__(self, cli, metadata, slots, header, version_id, version_string, info_id, scopes):
        self.cli, self.meta, self.slots, self.header = cli, metadata, slots, header
        self.version, self.version_string, self.info = version_id, version_string, info_id
        self.scopes, self.ops, self.blockers, self.notes = scopes, [], [], []
        self.app = metadata['appId']
        self.library = None
        self.library_rows = {}
        self.media = {}
        self.duo_groups = {}
        self.cpp_profiles = []
        self.cpp_status = None
        self.header_group = None

    def get(self, path):
        if '@pending-' in path:
            return []
        value = self.cli.api('GET', path).get('data', [])
        return value if isinstance(value, list) else [value]

    def queue(self, method, path, body=None, **extra):
        ref = '@pending-' + str(len(self.ops))
        self.ops.append(dict(ref=ref, method=method, path=path, body=body, **extra))
        return ref

    def upsert(self, kind, existing, attrs, relations):
        if existing:
            changed = {k: v for k, v in attrs.items() if existing.get('attributes', {}).get(k) != v}
            if changed:
                self.queue('PATCH', '/v1/' + kind + '/' + existing['id'], resource(kind, changed, identifier=existing['id']))
            return existing['id']
        return self.queue('POST', '/v1/' + kind, resource(kind, attrs, relations))

    @staticmethod
    def unique(rows, key):
        result = {}
        for row in rows:
            value = row.get('attributes', {}).get(key)
            if value in result:
                raise UploadError('Ambiguous remote resources; resolve duplicates before applying')
            result[value] = row
        return result

    def preflight(self):
        versions = self.get('/v1/apps/' + self.app + '/appStoreVersions')
        selected = [v for v in versions if v['id'] == self.version]
        if len(selected) != 1 or selected[0]['attributes'].get('versionString') != self.version_string or selected[0]['attributes'].get('platform') != 'IOS':
            raise UploadError('Explicit iOS version ID/string does not belong to Currency')
        if selected[0]['attributes'].get('appStoreState') not in EDITABLE:
            raise UploadError('Selected App Store version is not an editable draft')
        infos = [i for i in self.get('/v1/apps/' + self.app + '/appInfos') if i['id'] == self.info]
        if len(infos) != 1 or infos[0]['attributes'].get('appStoreState') not in EDITABLE:
            raise UploadError('Explicit app-info ID does not belong to an editable Currency draft')
        self.native_policy_preflight()
        metadata_changes = False
        if 'metadata' in self.scopes:
            result = self.sync_metadata(dry_run=True)
            metadata_changes = bool(result['adds'] or result['updates'])
            if metadata_changes:
                self.queue('METADATA', '')
        version_locales = self.unique(self.get('/v1/appStoreVersions/' + self.version + '/appStoreVersionLocalizations'), 'locale')
        targets = {}
        for locale, fields in self.meta['locales'].items():
            existing = version_locales.get(locale)
            if 'metadata' in self.scopes:
                if existing:
                    target = existing['id']
                elif metadata_changes:
                    target = self.queue('LOOKUP', '/v1/appStoreVersions/' + self.version + '/appStoreVersionLocalizations', locale=locale)
                else:
                    raise UploadError('Metadata dry-run did not plan the missing version locale; inspect draft state before applying')
            else:
                target = self.upsert('appStoreVersionLocalizations', existing, {'locale': locale}, {'appStoreVersion': relationship('appStoreVersions', self.version)})
            targets[('default', locale)] = target
        if 'cpp' in self.scopes or 'duo' in self.scopes:
            self.cpp_targets(targets)
        if 'header' in self.scopes or 'duo' in self.scopes:
            libraries = self.get('/v1/apps/' + self.app + '/assetLibrary')
            if len(libraries) != 1:
                raise UploadError('No unique Asset Library; initialize it in App Store Connect first')
            self.library = libraries[0]['id']
        if 'header' in self.scopes:
            video = self.library_media(self.header, 'video')
            for (family, locale), target in targets.items():
                self.place_header(target, family, video)
        for (family, locale), target in targets.items():
            if (family == 'default' and 'default' in self.scopes) or (family != 'default' and 'cpp' in self.scopes):
                for profile in (PROFILES if family == 'default' else self.cpp_profiles):
                    self.screenshots(target, family, locale, profile)
            if 'duo' in self.scopes:
                self.duo_screenshots(target, family, locale)
        if 'duo' in self.scopes:
            self.notes.append('Duo uses six ordered screenshots per page, mixing inner and outer displays through the approved presentation. Runtime group capacities and Apple processing still apply.')
        return self

    def sync_metadata(self, dry_run):
        with tempfile.TemporaryDirectory(prefix='currency-metadata-') as temporary:
            directory = Path(temporary)
            write_canonical_metadata(directory, self.meta, self.version_string)
            arguments = ['metadata', 'apply', '--app', self.app, '--app-info', self.info, '--version', self.version_string, '--platform', 'IOS', '--dir', str(directory), '--include', 'localizations', '--if-exists', 'update', '--output', 'json']
            if dry_run:
                arguments.append('--dry-run')
            result = self.cli.run(arguments, mutate=not dry_run, cwd=directory)
            expected = {'appId': self.app, 'appInfoId': self.info, 'version': self.version_string, 'versionId': self.version}
            if not isinstance(result, dict) or any(result.get(key) != value for key, value in expected.items()):
                raise UploadError('Metadata CLI resolved a different or incomplete target; inspect draft state before retrying')
            if any(not isinstance(result.get(key), list) for key in ('adds', 'updates', 'deletes')) or result['deletes']:
                raise UploadError('Metadata CLI reported an invalid plan or requested deletions; deletion is disabled')
            return result

    def native_policy_preflight(self):
        if not self.scopes & {'cpp', 'duo', 'header'}:
            return
        catalog = self.get('/v1/appAssetLibraryRefData')
        if len(catalog) != 1:
            raise UploadError('Native asset reference data is unavailable or ambiguous; no changes applied')
        attrs = catalog[0].get('attributes', {})
        if not isinstance(attrs, dict):
            raise UploadError('Native asset reference data is malformed; no changes applied')
        def records(value):
            if not isinstance(value, list) or any(not isinstance(item, dict) for item in value):
                raise UploadError('Native asset reference data is malformed; no changes applied')
            return value
        def identifiers(value):
            if not isinstance(value, list) or any(not isinstance(item, str) for item in value):
                raise UploadError('Native asset reference data is malformed; no changes applied')
            return value
        def index(name, key):
            values = records(attrs.get(name, []))
            if any(not isinstance(value.get(key), str) for value in values):
                raise UploadError('Native asset reference data is malformed; no changes applied')
            result = {value[key]: value for value in values}
            if len(result) != len(values):
                raise UploadError('Native asset reference data has duplicate identifiers; no changes applied')
            return result
        groups = index('placementProfileGroups', 'placementProfileGroupId')
        types = index('placementTypes', 'placementTypeId')
        features = index('features', 'featureId')

        def spec_constraints(spec, dimensions, media_type):
            ratio = spec.get('aspectRatio')
            bounds = spec.get('dimensions', {})
            exact_dimensions = all(type(bounds.get(key)) is int for key in ('minWidth', 'maxWidth', 'minHeight', 'maxHeight')) and bounds['minWidth'] == bounds['maxWidth'] and bounds['minHeight'] == bounds['maxHeight']
            if ratio is not None and not exact_dimensions:
                match = re.fullmatch(r'([0-9]+):([1-9][0-9]*)', ratio) if isinstance(ratio, str) else None
                if not match or abs(dimensions[0] / dimensions[1] - int(match[1]) / int(match[2])) > .001:
                    return False
            if media_type != 'video':
                return True
            video = self.header.get('video', {})
            if 'frameRates' in spec:
                fps = video.get('fps')
                rates = records(spec['frameRates'])
                if not isinstance(fps, (int, float)) or not any(type(rate.get('minFps')) is int and type(rate.get('maxFps')) is int and rate['minFps'] <= fps <= rate['maxFps'] for rate in rates):
                    return False
            if 'duration' in spec:
                bounds = spec['duration']
                def seconds(value):
                    match = re.fullmatch(r'PT(?:(\d+(?:\.\d+)?)H)?(?:(\d+(?:\.\d+)?)M)?(?:(\d+(?:\.\d+)?)S)?', value) if isinstance(value, str) else None
                    return sum(float(part or 0) * scale for part, scale in zip(match.groups(), (3600, 60, 1))) if match and any(match.groups()) else None
                low = seconds(bounds.get('min')) if isinstance(bounds, dict) else None
                high = seconds(bounds.get('max')) if isinstance(bounds, dict) else None
                duration = video.get('duration')
                if low is None or high is None or not isinstance(duration, (int, float)) or not low <= duration <= high:
                    return False
            if spec.get('audioRequired') is True and video.get('audio') is not True:
                return False
            return True

        def matching_group(placement_type, dimensions, media_type, display_class, platform, category):
            placement = types.get(placement_type, {})
            if category not in identifiers(placement.get('acceptsAssetCategories', [])):
                raise UploadError('Native asset category is unsupported by current reference data; no changes applied')
            specs = index(media_type + 'Specs', 'specId')
            candidates = set()
            for mapping in records(placement.get('specMappings', [])):
                group = mapping.get('placementGroupId')
                profile = groups.get(group, {})
                if profile.get('displayClassId') != display_class or profile.get('platform') != platform:
                    continue
                for spec_id in identifiers(mapping.get('specs', [])):
                    spec = specs.get(spec_id, {})
                    bounds = spec.get('dimensions', {})
                    width, height = dimensions
                    if isinstance(bounds, dict) and placement_type in identifiers(spec.get('compatiblePlacementTypes', [])) and all(type(bounds.get(k)) is int for k in ('minWidth', 'maxWidth', 'minHeight', 'maxHeight')) and bounds['minWidth'] <= width <= bounds['maxWidth'] and bounds['minHeight'] <= height <= bounds['maxHeight'] and spec_constraints(spec, dimensions, media_type):
                        candidates.add(group)
            if len(candidates) != 1:
                raise UploadError('Native asset group/specification is missing or ambiguous for ' + placement_type + '; no changes applied')
            group = next(iter(candidates))
            if not isinstance(group, str) or not re.fullmatch('[A-Za-z0-9_-]{1,120}', group):
                raise UploadError('Native asset group identifier is invalid; no changes applied')
            return group

        def capacity(feature_id, placement_type, group, required, allow_unlisted=False):
            feature = features.get(feature_id, {})
            policies = [p for p in records(feature.get('placementPolicies', [])) if p.get('placementType') == placement_type]
            limits = [limit.get('maxCount') for policy in policies for limit in records(policy.get('groupLimits', [])) if group in identifiers(limit.get('groupIds', []))]
            if policies and not limits and allow_unlisted:
                return False
            if not limits or any(type(limit) is not int or limit < 0 for limit in limits):
                raise UploadError('Native placement policy is unavailable for ' + feature_id + '/' + placement_type + '/' + group + '; no changes applied')
            maximum = min(limits)
            message = feature_id + '/' + placement_type + '/' + group + ': requires ' + str(required) + ', maximum ' + str(maximum)
            if required > maximum:
                raise UploadError('Native placement capacity is insufficient (' + message + '); select a supported scope or approve a revised media mapping; no changes applied')
            self.notes.append('Native placement capacity ' + message)
            return True

        if 'cpp' in self.scopes:
            self.cpp_profiles = []
            profiles = {
                'iphone': ('IPHONE_DYNAMIC_ISLAND_MEDIUM_DISPLAY', 'IPHONE_APP_STORE'),
                'ipad': ('IPAD_13_DISPLAY', 'IPAD_APP_STORE'),
                'watch': ('WATCH_SERIES_10', 'WATCH_APP_STORE'),
            }
            for profile, (display_class, platform) in profiles.items():
                group = matching_group('APP_SCREENSHOT', DIMENSIONS[profile], 'image', display_class, platform, 'APP_SCREENSHOTS_AND_PREVIEWS')
                if capacity('CUSTOM_PRODUCT_PAGES', 'APP_SCREENSHOT', group, 6, allow_unlisted=profile == 'watch'):
                    self.cpp_profiles.append(profile)
                else:
                    self.notes.append('Watch screenshots omitted from custom product pages: current Apple CUSTOM_PRODUCT_PAGES policy does not list ' + group + '; default-page Watch screenshots remain included when default scope is selected.')

        if 'duo' in self.scopes:
            presentation = duo_presentation(self.meta)
            for profile in ('duo-outer', 'duo-inner'):
                group = matching_group('APP_SCREENSHOT', DIMENSIONS[profile], 'image', 'IPHONE_DUO', 'IPHONE_APP_STORE', 'APP_SCREENSHOTS_AND_PREVIEWS')
                self.duo_groups[profile] = group
            counts = {}
            for profiles in presentation.values():
                family_counts = {}
                for profile in profiles:
                    group = self.duo_groups[profile]
                    family_counts[group] = family_counts.get(group, 0) + 1
                for group, count in family_counts.items():
                    counts[group] = max(counts.get(group, 0), count)
            for feature in ('APP_STORE_VERSIONS', 'CUSTOM_PRODUCT_PAGES'):
                for group, count in counts.items():
                    capacity(feature, 'APP_SCREENSHOT', group, count)
        if 'header' in self.scopes:
            self.header_group = matching_group('PRODUCT_PAGE_HEADER_ASSET', (3840, 1646), 'video', 'DEFAULT', 'ANY', 'CREATIVE_ASSETS')
            surfaces = ['APP_STORE_VERSIONS']
            if self.scopes & {'cpp', 'duo'}:
                surfaces.append('CUSTOM_PRODUCT_PAGES')
            for feature in surfaces:
                capacity(feature, 'PRODUCT_PAGE_HEADER_ASSET', self.header_group, 1)

    def cpp_targets(self, targets):
        pages = self.unique(self.get('/v1/apps/' + self.app + '/appCustomProductPages'), 'name')
        self.cpp_status = {'preparedFamilyCount': len(FAMILIES) - 1, 'targetedFamilies': FAMILIES[1:]}
        routing = self.meta.get('keywordRouting', {}) if 'cpp' in self.scopes else {}
        if 'cpp' in self.scopes and not routing and self.cpp_status['targetedFamilies']:
            self.notes.append('CPP keyword associations deferred: choose terms from the latest approved app version and provide keywordRouting; draft uploads remain available.')
        for family in FAMILIES[1:]:
            name = 'Currency - ' + family
            page = pages.get(name)
            page_id = page['id'] if page else self.queue('CPP_CREATE', '/v1/appCustomProductPages', name=name)
            versions = self.get('/v1/appCustomProductPages/' + page_id + '/appCustomProductPageVersions')
            drafts = [v for v in versions if v.get('attributes', {}).get('state') in {'PREPARE_FOR_SUBMISSION', 'REJECTED'}]
            if len(drafts) > 1:
                raise UploadError('Multiple editable CPP drafts; choose one in App Store Connect')
            if versions and not drafts:
                raise UploadError('CPP has no editable draft; create its next draft in App Store Connect first')
            if not page:
                version = self.queue('CPP_VERSION_LOOKUP', '/v1/appCustomProductPages/' + page_id + '/appCustomProductPageVersions')
            else:
                version = drafts[0]['id'] if drafts else self.queue('POST', '/v1/appCustomProductPageVersions', resource('appCustomProductPageVersions', {}, {'appCustomProductPage': relationship('appCustomProductPages', page_id)}))
            locales = self.unique(self.get('/v1/appCustomProductPageVersions/' + version + '/appCustomProductPageLocalizations'), 'locale')
            for locale, fields in self.meta['locales'].items():
                attrs = {'locale': locale}
                if 'cpp' in self.scopes:
                    text = fields.get('contextualPromotionalText', {}).get(family)
                    if not isinstance(text, str) or not text:
                        raise UploadError('Every CPP family/locale needs contextualPromotionalText')
                    attrs['promotionalText'] = text
                target = self.upsert('appCustomProductPageLocalizations', locales.get(locale), attrs, {'appCustomProductPageVersion': relationship('appCustomProductPageVersions', version)})
                targets[(family, locale)] = target
                if family in routing:
                    terms = routing[family].get(locale)
                    if not isinstance(terms, list) or not terms or any(not isinstance(t, str) or not t for t in terms):
                        raise UploadError('keywordRouting needs nonempty terms per configured family/locale')
                    approved = self.get('/v1/apps/' + self.app + '/searchKeywords')
                    allowed = {r['id'] for r in approved}
                    if not set(terms) <= allowed:
                        raise UploadError('keywordRouting contains terms absent from approved search keywords')
                    current = self.get('/v1/appCustomProductPageLocalizations/' + target + '/searchKeywords')
                    present = {r['id'] for r in current}
                    missing = [t for t in terms if t not in present]
                    if missing:
                        self.queue('POST', '/v1/appCustomProductPageLocalizations/' + target + '/relationships/searchKeywords', {'data': [{'type': 'appKeywords', 'id': t} for t in missing]})

    def screenshots(self, target, family, locale, profile):
        items = [self.slots[(locale, profile, family, i)] for i in range(1, 7)]
        resume = False
        kind = 'appStoreVersionLocalizations' if family == 'default' else 'appCustomProductPageLocalizations'
        sets = self.get('/v1/' + kind + '/' + target + '/appScreenshotSets')
        matching = [s for s in sets if s.get('attributes', {}).get('screenshotDisplayType') == PROFILES[profile]]
        if len(matching) > 1:
            raise UploadError('Duplicate remote screenshot sets')
        if matching:
            actual = self.get('/v1/appScreenshotSets/' + matching[0]['id'] + '/appScreenshots')
            expected = [hashlib.md5(i['file'].read_bytes()).hexdigest() for i in items]
            received = [r.get('attributes', {}).get('sourceFileChecksum') for r in actual]
            identifiers = [r.get('id') for r in actual]
            states = [r.get('attributes', {}).get('assetDeliveryState') for r in actual]
            complete_count = sum(isinstance(state, dict) and state.get('state') == 'COMPLETE' for state in states)
            complete = complete_count == len(actual) and all(isinstance(identifier, str) and re.fullmatch('[A-Za-z0-9-]{1,180}', identifier) for identifier in identifiers) and len(set(identifiers)) == len(actual)
            if received == expected and complete:
                return
            if actual:
                if not complete or len(set(expected)) != len(expected) or any(not isinstance(checksum, str) or checksum not in expected for checksum in received) or len(set(received)) != len(actual):
                    diagnostic = json.dumps(safe_screenshot_conflict(matching[0]['id'], actual, expected), separators=(',', ':'))
                    raise UploadError('Existing screenshot set differs or is incomplete for %s/%s (%d assets, %d complete); reconcile it manually before apply. Automatic deletion is disabled. screenshotConflict=%s' % (locale, profile, len(actual), complete_count, diagnostic))
                resume = True
        self.queue('SCREENSHOTS', target, family=family, profile=profile, files=[str(i['file']) for i in items], skip_existing=resume)

    def library_media(self, item, media_type):
        reference = 'currency-approved-' + item['sha256']
        if reference in self.media:
            return self.media[reference]
        if media_type not in self.library_rows:
            self.library_rows[media_type] = self.get('/v1/appAssetLibraries/' + self.library + '/' + ('videos' if media_type == 'video' else 'images'))
        resources = self.library_rows[media_type]
        found = [r for r in resources if r.get('attributes', {}).get('referenceName') == reference]
        if len(found) > 1:
            raise UploadError('Duplicate approved library assets; resolve duplicates first')
        if found:
            attrs = found[0].get('attributes', {})
            if attrs.get('state') not in {'PREPARE_FOR_SUBMISSION', 'APPROVED'}:
                raise UploadError('Existing approved media is still processing or failed; inspect it before retry')
            category = 'APP_SCREENSHOTS_AND_PREVIEWS' if media_type == 'image' else 'CREATIVE_ASSETS'
            ready = attrs.get('videoAsset') if media_type == 'video' else attrs.get('imageAsset', {}).get('width') and attrs.get('imageAsset', {}).get('height')
            if not ready or not attrs.get('specId') or attrs.get('category') != category or attrs.get('fileSize') != item['file'].stat().st_size:
                raise UploadError('Existing library asset does not match approved media readiness, category or file size; inspect it before reuse')
            identifier = found[0]['id']
        else:
            identifier = self.queue('LIBRARY', '', media_type=media_type, library=self.library, file=str(item['file']), reference=reference)
        self.media[reference] = identifier
        return identifier

    def duo_screenshots(self, target, family, locale):
        if set(self.duo_groups) != {'duo-outer', 'duo-inner'}:
            raise UploadError('Duo native placement policy preflight is required before planning placements')
        kind = 'appStoreVersionLocalizations' if family == 'default' else 'appCustomProductPageLocalizations'
        rel = 'appStoreVersionLocalization' if family == 'default' else 'appCustomProductPageLocalization'
        placements = self.get('/v1/' + kind + '/' + target + '/placements' + '?include=image&sort=placementGroupPosition')
        existing = [p for p in placements if p.get('attributes', {}).get('placementGroup') in self.duo_groups.values()]
        if any(p.get('attributes', {}).get('placementType') != 'APP_SCREENSHOT' for p in existing):
            raise UploadError('Duo group contains app previews; reconcile mixed media ordering explicitly first')
        desired, ordered = [], {}
        for order, profile in enumerate(duo_presentation(self.meta)[family], 1):
            group = self.duo_groups[profile]
            ordered.setdefault(group, [])
            image = self.library_media(self.slots[(locale, profile, family, order)], 'image')
            desired.append((image, group))
            matching = [p for p in existing if p.get('attributes', {}).get('placementGroup') == group and p.get('relationships', {}).get('image', {}).get('data', {}).get('id') == image]
            if len(matching) > 1:
                raise UploadError('Duplicate Duo image placements; reconcile in App Store Connect first')
            if matching:
                if matching[0].get('attributes', {}).get('state') == 'FAILED':
                    raise UploadError('Existing Duo placement failed; inspect before retry')
                ordered[group].append(matching[0]['id'])
            else:
                ordered[group].append(self.queue('POST', '/v1/appAssetLibraryPlacements', resource('appAssetLibraryPlacements', {'placementType': 'APP_SCREENSHOT', 'placementGroup': group}, {'image': relationship('appAssetLibraryImages', image), rel: relationship(kind, target)})))
        if len(set(desired)) != len(desired):
            raise UploadError('Duo approved mapping contains duplicate image/group pairs')
        if any((p.get('relationships', {}).get('image', {}).get('data', {}).get('id'), p.get('attributes', {}).get('placementGroup')) not in desired for p in existing):
            raise UploadError('Existing Duo placements differ from the approved set; automatic deletion is disabled')
        for group, identifiers in ordered.items():
            current = [p['id'] for p in existing if p.get('attributes', {}).get('placementGroup') == group]
            if current != identifiers:
                self.queue('POST', '/v1/appAssetLibraryPlacementOrderingRequests', resource('appAssetLibraryPlacementOrderingRequests', {'placementGroup': group}, {'orderedPlacements': {'data': [{'type': 'appAssetLibraryPlacements', 'id': p} for p in identifiers]}, rel: relationship(kind, target)}))

    def place_header(self, target, family, video):
        if not self.header_group:
            raise UploadError('Header native placement policy preflight is required before planning placements')
        kind = 'appStoreVersionLocalizations' if family == 'default' else 'appCustomProductPageLocalizations'
        placements = self.get('/v1/' + kind + '/' + target + '/placements' + '?include=video')
        headers = [p for p in placements if p.get('attributes', {}).get('placementType') == 'PRODUCT_PAGE_HEADER_ASSET']
        if headers:
            if len(headers) == 1 and headers[0].get('attributes', {}).get('placementGroup') == self.header_group and headers[0].get('relationships', {}).get('video', {}).get('data', {}).get('id') == video:
                if headers[0].get('attributes', {}).get('state') == 'FAILED':
                    raise UploadError('Existing header placement failed; inspect before retry')
                return
            raise UploadError('Existing product-page header differs; inspect and remove/swap explicitly in App Store Connect first')
        self.queue('POST', '/v1/appAssetLibraryPlacements', resource('appAssetLibraryPlacements', {'placementType': 'PRODUCT_PAGE_HEADER_ASSET', 'placementGroup': self.header_group}, {'video': relationship('appAssetLibraryVideos', video), 'appStoreVersionLocalization' if family == 'default' else 'appCustomProductPageLocalization': relationship(kind, target)}))

    def apply_resource(self, method, path, body):
        parents = {
            '/v1/appStoreVersionLocalizations': ('appStoreVersion', 'appStoreVersions'),
            '/v1/appCustomProductPageLocalizations': ('appCustomProductPageVersion', 'appCustomProductPageVersions'),
        }
        if method == 'POST' and path in parents:
            relation, parent_kind = parents[path]
            data = body['data']
            parent = data['relationships'][relation]['data']['id']
            rows = self.cli.api('GET', '/v1/' + parent_kind + '/' + parent + path.removeprefix('/v1')).get('data')
            if not isinstance(rows, list) or any(not isinstance(row, dict) for row in rows):
                raise UploadError('Localization refresh returned an invalid collection; inspect draft state before retrying')
            matching = [row for row in rows if row.get('attributes', {}).get('locale') == data['attributes']['locale']]
            if len(matching) > 1:
                raise UploadError('Localization refresh found duplicates; inspect draft state before retrying')
            if matching:
                existing = matching[0]
                identifier = existing.get('id')
                if not isinstance(identifier, str) or not re.fullmatch('[A-Za-z0-9-]+', identifier):
                    raise UploadError('Localization refresh returned an invalid identity; inspect draft state before retrying')
                changed = {key: value for key, value in data['attributes'].items() if key != 'locale' and existing.get('attributes', {}).get(key) != value}
                if changed:
                    self.cli.api('PATCH', path + '/' + identifier, resource(data['type'], changed, identifier=identifier))
                return {'data': existing}
        return self.cli.api(method, path, body)

    def execute(self):
        if self.blockers:
            raise UploadError('; '.join(self.blockers))
        if not self.cli.apply:
            raise UploadError('Apply mode is required to execute a plan')
        resolved = {}
        def substitute(value):
            if isinstance(value, str):
                for ref, identifier in sorted(resolved.items(), key=lambda p: -len(p[0])):
                    value = value.replace(ref, identifier)
                if '@pending-' in value:
                    raise UploadError('Unresolved planned resource; stopped before mutation')
                return value
            if isinstance(value, list):
                return [substitute(v) for v in value]
            if isinstance(value, dict):
                return {k: substitute(v) for k, v in value.items()}
            return value
        for index, operation in enumerate(self.ops, 1):
            op = substitute({k: v for k, v in operation.items() if k != 'ref'})
            if hasattr(self.cli, 'receipt'):
                self.cli.receipt('operation-%d-started' % index)
            if op['method'] == 'METADATA':
                self.sync_metadata(dry_run=False)
                identifier = ''
            elif op['method'] == 'CPP_CREATE':
                pages = self.unique(self.get('/v1/apps/' + self.app + '/appCustomProductPages'), 'name')
                existing = pages.get(op['name'])
                response = {'data': existing} if existing else self.cli.run(['product-pages', 'custom-pages', 'create', '--app', self.app, '--name', op['name'], '--output', 'json'], mutate=True)
                identifier = response.get('data', {}).get('id')
                if not isinstance(identifier, str) or not re.fullmatch('[A-Za-z0-9-]+', identifier):
                    raise UploadError('Custom page creation returned no valid page identity; inspect draft state before retrying')
            elif op['method'] == 'CPP_VERSION_LOOKUP':
                drafts = [row for row in self.get(op['path']) if row.get('attributes', {}).get('state') in {'PREPARE_FOR_SUBMISSION', 'REJECTED'}]
                if len(drafts) != 1 or not isinstance(drafts[0].get('id'), str) or not re.fullmatch('[A-Za-z0-9-]+', drafts[0]['id']):
                    raise UploadError('Custom page creation did not resolve one editable initial version; inspect draft state before retrying')
                identifier = drafts[0]['id']
            elif op['method'] == 'LOOKUP':
                matches = [row for row in self.get(op['path']) if row.get('attributes', {}).get('locale') == op['locale']]
                if len(matches) != 1 or not isinstance(matches[0].get('id'), str) or not re.fullmatch('[A-Za-z0-9-]+', matches[0]['id']):
                    raise UploadError('Metadata synchronization did not resolve one expected version localization; inspect draft state before retrying')
                identifier = matches[0]['id']
            elif op['method'] == 'LIBRARY':
                plural = 'videos' if op['media_type'] == 'video' else 'images'
                category = 'APP_SCREENSHOTS_AND_PREVIEWS' if op['media_type'] == 'image' else 'CREATIVE_ASSETS'
                response = self.cli.run(['asset-library', plural, 'upload', '--library-id', op['library'], '--file', op['file'], '--reference-name', op['reference'], '--category', category, '--output', 'json'], mutate=True)
                identifier = response.get(op['media_type'] + 'Id')
                if not identifier:
                    raise UploadError('Library upload returned no asset ID; inspect remote library before retry')
            elif op['method'] == 'SCREENSHOTS':
                with tempfile.TemporaryDirectory(prefix='currency-shots-') as directory:
                    for order, name in enumerate(op['files'], 1):
                        shutil.copyfile(name, Path(directory) / ('%02d.png' % order))
                    args = ['screenshots', 'upload', '--version-localization', op['path']] if op['family'] == 'default' else ['product-pages', 'custom-pages', 'localizations', 'screenshot-sets', 'upload', '--localization-id', op['path']]
                    self.cli.run([*args, '--path', directory, '--device-type', PROFILES[op['profile']], '--output', 'json', *(['--skip-existing'] if op.get('skip_existing') else [])], mutate=True)
                identifier = ''
            else:
                response = self.apply_resource(op['method'], op['path'], op['body'])
                identifier = response.get('data', {}).get('id', '')
                if op['method'] == 'POST' and isinstance(response.get('data'), dict) and not identifier:
                    raise UploadError('Creation response omitted resource identity; inspect before retry')
            resolved[operation['ref']] = identifier
            if hasattr(self.cli, 'receipt'):
                self.cli.receipt('operation-%d-completed' % index, {'id': identifier})
            print('Completed draft operation %d/%d' % (index, len(self.ops)), flush=True)

    def summary(self):
        result = []
        for index, operation in enumerate(self.ops, 1):
            data = (operation.get('body') or {}).get('data', {})
            data = data if isinstance(data, dict) else {}
            entry = {'operation': index, 'method': operation['method'], 'resource': data.get('type', operation['path']), 'fields': sorted(data.get('attributes', {}))}
            if 'locale' in data.get('attributes', {}):
                entry['locale'] = data['attributes']['locale']
            if operation['method'] == 'SCREENSHOTS':
                entry.update(family=operation['family'], profile=operation['profile'], screenshotCount=len(operation['files']), resumeExisting=operation.get('skip_existing', False))
            if operation['method'] == 'LIBRARY':
                entry.update(mediaType=operation['media_type'], approvedReference=operation['reference'])
            if operation['method'] == 'METADATA':
                entry.update(localeCount=len(self.meta['locales']), appInfoFields=sorted({key for fields in self.meta['locales'].values() for key in fields if key in INFO_FIELDS}), versionFields=sorted({key for fields in self.meta['locales'].values() for key in fields if key in VERSION_FIELDS}))
            if operation['method'] == 'CPP_CREATE':
                entry['pageName'] = operation['name']
            if operation['method'] == 'LOOKUP':
                entry['locale'] = operation['locale']
            if data.get('attributes', {}).get('placementGroup'):
                entry['placementGroup'] = data['attributes']['placementGroup']
            result.append(entry)
        return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--metadata', type=Path, default=Path(__file__).with_name('metadata.json'))
    parser.add_argument('--media-dir', type=Path, default=Path(__file__).with_name('media'))
    parser.add_argument('--validate-only', action='store_true', help='Validate approved media without credentials or App Store requests')
    parser.add_argument('--version-id', help='Optional exact editable iOS version filter; otherwise require one unique candidate')
    parser.add_argument('--version-string', help='Optional exact iOS version-string filter')
    parser.add_argument('--app-info-id', help='Optional exact editable app-info filter; otherwise require one unique candidate')
    parser.add_argument('--scope', default='metadata,default,cpp,header,duo')
    parser.add_argument('--apply', action='store_true')
    parser.add_argument('--receipts', type=Path, help='Private durable JSONL receipt path; required for remote plans and apply')
    args = parser.parse_args()
    scopes = set(args.scope.split(','))
    if not scopes or not scopes <= SCOPES:
        parser.error('--scope must select metadata,default,cpp,header,duo')
    if args.validate_only and args.apply:
        parser.error('--validate-only cannot be combined with --apply')
    args.version_id = args.version_id.strip() if args.version_id else None
    args.version_string = args.version_string.strip() if args.version_string else None
    args.app_info_id = args.app_info_id.strip() if args.app_info_id else None
    if not args.validate_only:
        if not args.receipts:
            parser.error('--receipts is required unless --validate-only is selected')
        for identifier in (args.version_id, args.app_info_id):
            if identifier and not re.fullmatch('[A-Za-z0-9-]+', identifier):
                parser.error('Resource IDs may contain only letters, digits and hyphens')
    root = args.media_dir.resolve()
    metadata = json.loads(args.metadata.read_text())
    manifest = json.loads((root / 'manifest.json').read_text())
    slots, header = validate_media(root, manifest, metadata)
    if args.validate_only:
        print(json.dumps({'mode': 'validate-only', 'verifiedPlacements': len(slots), 'verifiedHeader': True, 'appStoreRequests': 0}))
        return 0
    cli = CLI(apply=args.apply, receipts=args.receipts)
    target = resolve_targets(cli, metadata['appId'], args.version_id, args.version_string, args.app_info_id)
    print(json.dumps({'resolvedTarget': target}))
    plan = Planner(cli, metadata, slots, header, target['versionId'], target['versionString'], target['appInfoId'], scopes).preflight()
    print(json.dumps({'mode': 'apply' if args.apply else 'dry-run', 'plannedDraftOperations': len(plan.ops), 'scopes': sorted(scopes), 'blockers': plan.blockers, 'notes': plan.notes, 'cppStatus': plan.cpp_status, 'plan': plan.summary()}, ensure_ascii=False, indent=2))
    if args.apply:
        plan.execute()
    elif plan.blockers:
        return 2
    return 0


if __name__ == '__main__':
    try:
        sys.exit(main())
    except (UploadError, OSError, ValueError, KeyError) as error:
        print('Error: ' + (str(error) if isinstance(error, UploadError) else 'Invalid local input; validate checked-in media and metadata'), file=sys.stderr)
        sys.exit(1)
