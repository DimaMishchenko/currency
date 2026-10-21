#!/usr/bin/env python3
"""Fetch the pinned independent GitHub asset release and verify before unpacking."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parent


class FetchError(Exception):
    pass


def read_config(config_path, recipe_path):
    config = json.loads(config_path.read_text())
    recipe = json.loads(recipe_path.read_text())
    if config.get('schemaVersion') != 1 or not re.fullmatch(r'app-store-assets-v[1-9][0-9]*', config.get('releaseTag', '')):
        raise FetchError('Select an explicit independently versioned app-store-assets-vN release tag')
    if not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9_.-]*\.zip', config.get('fileName', '')) or not re.fullmatch('[a-f0-9]{64}', config.get('sha256', '')) or type(config.get('bytes')) is not int or not 0 < config['bytes'] <= 6 * 1024 ** 3:
        raise FetchError('Asset configuration needs an exact ZIP filename, SHA-256 and byte count')
    if config['sha256'] != recipe.get('approved_bundle_sha256'):
        raise FetchError('Asset configuration and approved design recipe disagree; update both when approving a new asset version')
    return config


def run(arguments):
    try:
        result = subprocess.run(arguments, text=True, capture_output=True, timeout=1800, check=False)
    except (OSError, subprocess.TimeoutExpired):
        raise FetchError('Asset download/unpack command could not finish; command output suppressed') from None
    if result.returncode:
        raise FetchError('Asset download/unpack failed; verify the pinned GitHub release and asset (command output suppressed)')


def fetch(config_path, recipe_path, repository, output):
    config = read_config(config_path, recipe_path)
    if not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9_.-]*/[A-Za-z0-9][A-Za-z0-9_.-]*', repository):
        raise FetchError('Use an explicit owner/repository GitHub repository name')
    if output.is_symlink() or (output.exists() and (not output.is_dir() or any(output.iterdir()))):
        raise FetchError('Media output directory must be empty and cannot be a symlink')
    output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='currency-asset-download-', dir=output.parent) as temporary:
        directory = Path(temporary)
        run(['gh', 'release', 'download', config['releaseTag'], '--repo', repository, '--pattern', config['fileName'], '--dir', str(directory)])
        archive = directory / config['fileName']
        if not archive.is_file() or archive.is_symlink() or archive.stat().st_size != config['bytes']:
            raise FetchError('Downloaded asset byte count does not match the pinned configuration')
        digest = hashlib.sha256()
        with archive.open('rb') as stream:
            for block in iter(lambda: stream.read(1024 * 1024), b''):
                digest.update(block)
        if digest.hexdigest() != config['sha256']:
            raise FetchError('Downloaded asset SHA-256 does not match the pinned configuration')
        staged = directory / 'media'
        run([sys.executable, str(ROOT / 'generator' / 'generate.py'), '--recipe', str(recipe_path), 'unpack', '--archive', str(archive), '--output', str(staged)])
        if not staged.is_dir() or not (staged / 'manifest.json').is_file():
            raise FetchError('Unpack produced no media manifest')
        if output.is_symlink() or (output.exists() and (not output.is_dir() or any(output.iterdir()))):
            raise FetchError('Media output changed during download; refusing to overwrite it')
        staged.replace(output)
    return {'releaseTag': config['releaseTag'], 'sha256': config['sha256'], 'verifiedBytes': config['bytes']}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--config', type=Path, default=ROOT / 'asset-bundle.json')
    parser.add_argument('--recipe', type=Path, default=ROOT / 'design' / 'recipe.json')
    parser.add_argument('--repo', required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    print(json.dumps(fetch(args.config, args.recipe, args.repo, args.output)))


if __name__ == '__main__':
    try:
        main()
    except (FetchError, OSError, ValueError, KeyError) as error:
        sys.exit(str(error) if isinstance(error, FetchError) else 'Invalid asset configuration or local files')
