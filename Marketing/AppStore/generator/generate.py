import argparse
import base64
import hashlib
import io
import json
from pathlib import Path, PurePosixPath
import re
import struct
import subprocess
import zipfile
import xml.etree.ElementTree as ET

DESIGN = Path(__file__).resolve().parents[1] / 'design'
SVG = '{http://www.w3.org/2000/svg}'
XLINK = '{http://www.w3.org/1999/xlink}href'
ET.register_namespace('', SVG[1:-1])


def digest(path):
    value = hashlib.sha256()
    with path.open('rb') as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b''):
            value.update(block)
    return value.hexdigest()


def confined(root, name):
    parts = PurePosixPath(name)
    if not name or '\\' in name or parts.is_absolute() or any(p in ('..', '.') for p in name.split('/')):
        raise ValueError('Invalid relative path: ' + name)
    target = (root / name).resolve()
    if not target.is_relative_to(root.resolve()):
        raise ValueError('Path escapes its root: ' + name)
    return target


def load(path):
    return json.loads(path.read_text(encoding='utf-8'))


def write_json(path, value):
    path.write_text(json.dumps(value, ensure_ascii=False, sort_keys=True, indent=2) + '\n', encoding='utf-8')


def verified_object(inputs, identifier, registry):
    if not re.fullmatch('[a-f0-9]{64}', identifier) or identifier not in registry:
        raise ValueError('Unknown input object')
    path = confined(inputs, 'objects/' + identifier)
    if path.stat().st_size != registry[identifier]['size'] or digest(path) != identifier:
        raise ValueError('Input hash mismatch: ' + identifier)
    return path


def validate_recipe(recipe):
    paths = set()
    slots = set()
    referenced = set()
    for item in recipe['placements']:
        confined(Path('/tmp'), item['path'])
        slot = tuple(item[k] for k in ('locale', 'profile', 'family', 'order'))
        if item['path'] in paths or slot in slots:
            raise ValueError('Duplicate placement')
        paths.add(item['path'])
        slots.add(slot)
        master = recipe['masters'][item['master']]
        if master['approved_sha256'] != item['sha256'] or not item['master'].startswith(item['locale'] + '/'):
            raise ValueError('Placement/master mismatch')
        if item['width'] <= 0 or item['height'] <= 0:
            raise ValueError('Invalid image dimensions')
        referenced.add(item['master'])
    if referenced != set(recipe['masters']):
        raise ValueError('Unplaced master')


def png_dimensions(header):
    if header[:16] != b'\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR':
        raise ValueError('Invalid PNG header')
    return struct.unpack('>II', header[16:24])


def export_archive(archive, output, recipe):
    validate_recipe(recipe)
    if output.exists() and any(output.iterdir()):
        raise ValueError('Output directory must be empty')
    if digest(archive) != recipe['approved_archive_sha256']:
        raise ValueError('Approved archive hash mismatch')
    expected = {p['path']: p for p in recipe['placements']}
    with zipfile.ZipFile(archive) as source:
        names = source.namelist()
        if len(set(names)) != len(names):
            raise ValueError('Duplicate archive member')
        for member in source.infolist():
            confined(output, member.filename)
            if (member.external_attr >> 16) & 0o170000 == 0o120000:
                raise ValueError('Archive symlink refused')
        if set(names) != set(expected) | {'mapping.csv', 'manifest.json'}:
            raise ValueError('Unexpected archive members')
        output.mkdir(parents=True, exist_ok=True)
        for name, placement in expected.items():
            data = source.read(name)
            if hashlib.sha256(data).hexdigest() != placement['sha256']:
                raise ValueError('Approved PNG hash mismatch: ' + name)
            if png_dimensions(data[:24]) != (placement['width'], placement['height']):
                raise ValueError('Approved PNG dimensions mismatch: ' + name)
            target = confined(output, name)
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(data)
    result = {'schemaVersion': 1, 'kind': 'approved-delivery', 'archive_sha256': recipe['approved_archive_sha256'], 'placements': recipe['placements']}
    write_json(output / 'manifest.json', result)
    return result


def bundle_archive(archive, header, output, recipe):
    validate_recipe(recipe)
    if output.exists():
        raise ValueError('Bundle output already exists')
    if digest(archive) != recipe['approved_archive_sha256']:
        raise ValueError('Approved archive hash mismatch')
    if digest(header) != recipe['approved_header_sha256']:
        raise ValueError('Approved header hash mismatch')
    placements = []
    unique = {}
    for item in recipe['placements']:
        path = 'masters/' + item['master'] + '.png'
        placements.append({**item, 'path': path})
        unique.setdefault(item['master'], item)
    result = {'schemaVersion': 1, 'placements': placements, 'header': {'path': 'header/header.mp4', 'sha256': recipe['approved_header_sha256']}}
    output.parent.mkdir(parents=True, exist_ok=True)
    pending = output.with_name(output.name + '.partial')
    if pending.exists():
        raise ValueError('Partial bundle output already exists')
    try:
        with zipfile.ZipFile(archive) as source, zipfile.ZipFile(pending, 'w', compression=zipfile.ZIP_STORED, allowZip64=True) as target:
            names = source.namelist()
            if len(names) != len(set(names)) or set(names) != {p['path'] for p in recipe['placements']} | {'mapping.csv', 'manifest.json'}:
                raise ValueError('Unexpected archive members')
            for name in names:
                confined(output.parent, name)
            for key, item in sorted(unique.items()):
                data = source.read(item['path'])
                if hashlib.sha256(data).hexdigest() != item['sha256'] or png_dimensions(data[:24]) != (item['width'], item['height']):
                    raise ValueError('Approved master mismatch: ' + key)
                info = zipfile.ZipInfo('masters/' + key + '.png', (1980, 1, 1, 0, 0, 0))
                info.create_system = 3
                info.external_attr = 0o100644 << 16
                target.writestr(info, data)
            for name, data in [('header/header.mp4', header.read_bytes()), ('manifest.json', (json.dumps(result, ensure_ascii=False, sort_keys=True, separators=(',', ':')) + '\n').encode())]:
                info = zipfile.ZipInfo(name, (1980, 1, 1, 0, 0, 0))
                info.create_system = 3
                info.external_attr = 0o100644 << 16
                target.writestr(info, data)
        pending.replace(output)
    except BaseException:
        pending.unlink(missing_ok=True)
        raise
    return result


def unpack_bundle(archive, output, recipe):
    validate_recipe(recipe)
    if output.exists() and any(output.iterdir()):
        raise ValueError('Output directory must be empty')
    if digest(archive) != recipe['approved_bundle_sha256']:
        raise ValueError('Approved bundle hash mismatch')
    expected_placements = [{**p, 'path': 'masters/' + p['master'] + '.png'} for p in recipe['placements']]
    expected_manifest = {'schemaVersion': 1, 'placements': expected_placements, 'header': {'path': 'header/header.mp4', 'sha256': recipe['approved_header_sha256']}}
    expected = {}
    for p in expected_placements:
        expected[p['path']] = (p['sha256'], (p['width'], p['height']))
    expected['header/header.mp4'] = (recipe['approved_header_sha256'], None)
    with zipfile.ZipFile(archive) as source:
        names = source.namelist()
        if len(names) != len(set(names)) or set(names) != set(expected) | {'manifest.json'}:
            raise ValueError('Unexpected bundle members')
        for member in source.infolist():
            confined(output, member.filename)
            if (member.external_attr >> 16) & 0o170000 == 0o120000:
                raise ValueError('Bundle symlink refused')
        if json.loads(source.read('manifest.json')) != expected_manifest:
            raise ValueError('Bundle placement mapping mismatch')
        for name, (sha, dimensions) in expected.items():
            data = source.read(name)
            if hashlib.sha256(data).hexdigest() != sha:
                raise ValueError('Bundle media hash mismatch: ' + name)
            if dimensions and png_dimensions(data[:24]) != dimensions:
                raise ValueError('Bundle PNG dimensions mismatch: ' + name)
        output.mkdir(parents=True, exist_ok=True)
        for name in expected:
            target = confined(output, name)
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(source.read(name))
        write_json(output / 'manifest.json', expected_manifest)
    return expected_manifest


def render_master(key, master, inputs, output, registry, design=DESIGN, renderer='rsvg-convert'):
    from PIL import Image, ImageDraw, ImageFont
    cache = {}

    def input_path(identifier):
        if identifier not in cache:
            cache[identifier] = verified_object(inputs, identifier, registry)
        return cache[identifier]

    if 'native' in master:
        with Image.open(input_path(master['native'])) as raw:
            image = raw.convert('RGB')
    else:
        tree = ET.parse(confined(design, master['template'])).getroot()
        for element in tree.iter():
            if element.tag == SVG + 'image':
                attr = 'href' if element.get('href') is not None else XLINK
                reference = element.get(attr, '')
                if not re.fullmatch('slot:[0-9]+', reference):
                    raise ValueError('Only frozen bitmap slots may appear in templates')
                data = input_path(master['images'][int(reference[5:])]).read_bytes()
                element.set(attr, 'data:image/png;base64,' + base64.b64encode(data).decode())
            elif element.tag in {SVG + 'script', SVG + 'foreignObject', SVG + 'text', SVG + 'style'}:
                raise ValueError('Unsupported template element')
            for attr, value in element.attrib.items():
                if attr.lower().startswith('on') or (attr in ('href', XLINK) and element.tag != SVG + 'image'):
                    raise ValueError('External template reference refused')
                if 'url(' in value and not re.fullmatch(r'url\(#[\w-]+\)', value):
                    raise ValueError('External template resource refused')
        body = subprocess.run([renderer, '--unlimited'], input=ET.tostring(tree), capture_output=True, check=True).stdout
        with Image.open(io.BytesIO(body)) as rendered:
            image = rendered.convert('RGB')
        draw = ImageDraw.Draw(image)
        for line in master['headlines']:
            font = ImageFont.truetype(str(input_path(line['font'])), round(line['size']), index=line['face'])
            if line['axes']:
                font.set_variation_by_axes(line['axes'])
            x = line['x']
            for text, color in line['runs']:
                draw.text((x, line['y']), text, font=font, anchor='ls', fill=color)
                x += font.getlength(text)
    target = confined(output, 'masters/' + key + '.png')
    target.parent.mkdir(parents=True, exist_ok=True)
    image.save(target, optimize='native' not in master)
    return {'master': key, 'path': str(target.relative_to(output.resolve())), 'sha256': digest(target), 'approved_byte_match': digest(target) == master['approved_sha256']}


def render(recipe, inputs, output, registry, locale=None, asset=None, renderer='rsvg-convert'):
    validate_recipe(recipe)
    selected = {k: v for k, v in recipe['masters'].items() if (not locale or k.split('/')[0] in locale) and (not asset or k.split('/')[1] in asset)}
    if not selected:
        raise ValueError('Selection contains no masters')
    output.mkdir(parents=True, exist_ok=True)
    rendered = [render_master(k, v, inputs, output, registry, renderer=renderer) for k, v in selected.items()]
    result = {'schemaVersion': 1, 'kind': 'design-preview', 'masters': rendered, 'placements': [p for p in recipe['placements'] if p['master'] in selected]}
    write_json(output / 'manifest.json', result)
    return result


def main():
    parser = argparse.ArgumentParser(description='Render editable frozen designs or assemble exact approved screenshot placements.')
    parser.add_argument('--recipe', type=Path, default=DESIGN / 'recipe.json')
    sub = parser.add_subparsers(dest='command', required=True)
    verify = sub.add_parser('verify-inputs')
    verify.add_argument('--inputs', required=True, type=Path)
    export = sub.add_parser('export')
    export.add_argument('--archive', required=True, type=Path)
    export.add_argument('--output', required=True, type=Path)
    bundle = sub.add_parser('bundle')
    bundle.add_argument('--archive', required=True, type=Path)
    bundle.add_argument('--header', required=True, type=Path)
    bundle.add_argument('--output', required=True, type=Path)
    unpack = sub.add_parser('unpack')
    unpack.add_argument('--archive', required=True, type=Path)
    unpack.add_argument('--output', required=True, type=Path)
    preview = sub.add_parser('render')
    preview.add_argument('--inputs', required=True, type=Path)
    preview.add_argument('--output', required=True, type=Path)
    preview.add_argument('--locale', action='append')
    preview.add_argument('--asset', action='append')
    preview.add_argument('--renderer', default='rsvg-convert')
    args = parser.parse_args()
    recipe = load(args.recipe)
    validate_recipe(recipe)
    registry = load(DESIGN / 'input-manifest.json')['objects']
    if args.command == 'verify-inputs':
        for identifier in registry:
            verified_object(args.inputs, identifier, registry)
        print(json.dumps({'verified_objects': len(registry)}))
    elif args.command == 'unpack':
        result = unpack_bundle(args.archive, args.output, recipe)
        print(json.dumps({'placements': len(result['placements']), 'masters': len(recipe['masters'])}))
    elif args.command == 'bundle':
        result = bundle_archive(args.archive, args.header, args.output, recipe)
        print(json.dumps({'placements': len(result['placements']), 'masters': len(recipe['masters']), 'bundle_sha256': digest(args.output)}))
    elif args.command == 'export':
        result = export_archive(args.archive, args.output, recipe)
        print(json.dumps({'placements': len(result['placements']), 'kind': result['kind']}))
    else:
        result = render(recipe, args.inputs, args.output, registry, args.locale, args.asset, args.renderer)
        print(json.dumps({'masters': len(result['masters']), 'approved_byte_matches': sum(m['approved_byte_match'] for m in result['masters']), 'kind': result['kind']}))


if __name__ == '__main__':
    main()
