import argparse
import json
import os
from pathlib import Path
import re
import subprocess


EDITABLE = {'PREPARE_FOR_SUBMISSION', 'DEVELOPER_REJECTED', 'REJECTED', 'METADATA_REJECTED'}
ROOT = Path(__file__).resolve().parents[2]


def version_number(value):
    if not isinstance(value, str) or not re.fullmatch(r'(0|[1-9][0-9]*)(\.(0|[1-9][0-9]*)){0,2}', value):
        raise ValueError('Expected a numeric marketing version with at most three components')
    parts = tuple(int(part) for part in value.split('.'))
    return parts + (0,) * (3 - len(parts))


def select_version(configured, response):
    selected = version_number(configured)
    if not isinstance(response, dict) or not isinstance(response.get('data'), list):
        raise ValueError('App Store versions response is not a collection')
    if response.get('links', {}).get('next'):
        raise ValueError('App Store versions response is incomplete')
    for row in response['data']:
        attrs = row.get('attributes', {})
        if not isinstance(attrs, dict) or not attrs.get('platform'):
            raise ValueError('App Store version platform is missing')
        if attrs.get('platform') != 'IOS':
            continue
        remote = version_number(attrs.get('versionString'))
        state = attrs.get('appStoreState')
        if not isinstance(state, str) or not state:
            raise ValueError('App Store version state is missing')
        if state in EDITABLE:
            selected = max(selected, remote)
        else:
            selected = max(selected, (remote[0], remote[1], remote[2] + 1))
    return configured if selected == version_number(configured) else '.'.join(map(str, selected))


def fetch_versions(app):
    if not re.fullmatch(r'[0-9]+', app):
        raise ValueError('App ID must be numeric')
    try:
        result = subprocess.run(
            ['asc', 'api', 'GET', f'/v1/apps/{app}/appStoreVersions', '--paginate', '--output', 'json'],
            check=True, capture_output=True, text=True, timeout=60,
        )
        return json.loads(result.stdout)
    except (OSError, subprocess.SubprocessError, json.JSONDecodeError):
        raise ValueError('Cannot read App Store versions; release stopped before upload') from None


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--app', required=True)
    parser.add_argument('--check', help='Reject an archive version that is no longer safe to upload')
    args = parser.parse_args()
    configured = re.findall(r'"MARKETING_VERSION":\s*"([^"]+)"', (ROOT / 'Project.swift').read_text())
    if len(configured) != 1:
        raise ValueError('Expected one marketing version in Project.swift')
    response = fetch_versions(args.app)
    selected = select_version(args.check or configured[0], response)
    if args.check:
        if version_number(selected) != version_number(args.check):
            raise ValueError('App Store state changed; archive version is protected or outdated. Rebuild before uploading')
        return
    with open(os.environ['GITHUB_ENV'], 'a') as output:
        output.write(f'CURRENCY_MARKETING_VERSION={selected}\n')
    (Path(os.environ['RUNNER_TEMP']) / 'CurrencyMarketingVersion.txt').write_text(selected + '\n')
    print(f'TestFlight marketing version: {selected}')


if __name__ == '__main__':
    try:
        main()
    except (ValueError, KeyError, TypeError, AttributeError) as error:
        raise SystemExit(f'Release version check failed: {error}') from None
