import hashlib
import importlib.util
import json
from pathlib import Path
import struct
import tempfile
import unittest
import zipfile

SPEC = importlib.util.spec_from_file_location('generate', Path(__file__).parents[1] / 'generate.py')
generate = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(generate)


class GeneratorTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        self.addCleanup(self.temporary.cleanup)
        self.png = b'\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR' + struct.pack('>II', 10, 20)
        self.sha = hashlib.sha256(self.png).hexdigest()
        self.placement = {'locale': 'en-US', 'profile': 'iphone', 'family': 'default', 'order': 1, 'master': 'en-US/home', 'path': 'en-US/iphone/default/01-home.png', 'sha256': self.sha, 'width': 10, 'height': 20}
        self.recipe = {'masters': {'en-US/home': {'approved_sha256': self.sha}}, 'placements': [self.placement]}

    def archive(self, extra=None, data=None):
        target = self.root / 'approved.zip'
        with zipfile.ZipFile(target, 'w') as archive:
            archive.writestr(self.placement['path'], self.png if data is None else data)
            archive.writestr('manifest.json', 'private source metadata')
            archive.writestr('mapping.csv', 'private source metadata')
            if extra:
                archive.writestr(extra, 'escape')
        self.recipe['approved_archive_sha256'] = generate.digest(target)
        return target

    def test_export_assembles_verified_placements_and_replaces_private_sidecars(self):
        output = self.root / 'output'
        generate.export_archive(self.archive(), output, self.recipe)
        self.assertEqual((output / self.placement['path']).read_bytes(), self.png)
        self.assertFalse((output / 'mapping.csv').exists())
        self.assertEqual(json.loads((output / 'manifest.json').read_text())['kind'], 'approved-delivery')
        self.assertNotIn('private source', (output / 'manifest.json').read_text())

    def test_path_traversal_rejected_even_with_matching_archive_hash(self):
        with self.assertRaises(ValueError):
            generate.export_archive(self.archive('../escape.png'), self.root / 'output', self.recipe)
        self.assertFalse((self.root.parent / 'escape.png').exists())

    def test_png_corruption_rejected_after_archive_identity_check(self):
        with self.assertRaisesRegex(ValueError, 'PNG hash mismatch'):
            generate.export_archive(self.archive(data=b'corrupt'), self.root / 'output', self.recipe)

    def test_archive_identity_corruption_rejected(self):
        archive = self.archive()
        archive.write_bytes(archive.read_bytes() + b'corrupt')
        with self.assertRaisesRegex(ValueError, 'archive hash mismatch'):
            generate.export_archive(archive, self.root / 'output', self.recipe)

    def test_duplicate_slots_and_foreign_locale_rejected(self):
        self.recipe['placements'].append(dict(self.placement, path='other.png'))
        with self.assertRaisesRegex(ValueError, 'Duplicate placement'):
            generate.validate_recipe(self.recipe)
        self.recipe['placements'].pop()
        self.placement['locale'] = 'de-DE'
        with self.assertRaisesRegex(ValueError, 'Placement/master mismatch'):
            generate.validate_recipe(self.recipe)

    def test_compact_bundle_is_deterministic_and_uses_unique_master_paths(self):
        archive = self.archive()
        header = self.root / 'header.mp4'
        header.write_bytes(b'approved-video')
        self.recipe['approved_header_sha256'] = generate.digest(header)
        first = self.root / 'first.zip'
        second = self.root / 'second.zip'
        generate.bundle_archive(archive, header, first, self.recipe)
        generate.bundle_archive(archive, header, second, self.recipe)
        self.assertEqual(first.read_bytes(), second.read_bytes())
        with zipfile.ZipFile(first) as bundle:
            self.assertEqual(set(bundle.namelist()), {'masters/en-US/home.png', 'header/header.mp4', 'manifest.json'})
            manifest = json.loads(bundle.read('manifest.json'))
            self.assertEqual(manifest['schemaVersion'], 1)
            self.assertEqual(manifest['placements'][0]['path'], 'masters/en-US/home.png')
            self.assertNotIn('private source', bundle.read('manifest.json').decode())

    def test_unpack_checks_every_media_before_writing(self):
        header = self.root / 'header.mp4'
        header.write_bytes(b'approved-video')
        self.recipe['approved_header_sha256'] = generate.digest(header)
        bundle = self.root / 'bundle.zip'
        generate.bundle_archive(self.archive(), header, bundle, self.recipe)
        self.recipe['approved_bundle_sha256'] = generate.digest(bundle)
        output = self.root / 'unpacked'
        generate.unpack_bundle(bundle, output, self.recipe)
        self.assertEqual((output / 'masters/en-US/home.png').read_bytes(), self.png)
        self.assertEqual((output / 'header/header.mp4').read_bytes(), b'approved-video')
        corrupt = self.root / 'corrupt.zip'
        with zipfile.ZipFile(bundle) as source, zipfile.ZipFile(corrupt, 'w') as target:
            for name in source.namelist():
                target.writestr(name, b'corrupt' if name == 'header/header.mp4' else source.read(name))
        self.recipe['approved_bundle_sha256'] = generate.digest(corrupt)
        empty = self.root / 'must-stay-empty'
        with self.assertRaisesRegex(ValueError, 'Bundle media hash mismatch'):
            generate.unpack_bundle(corrupt, empty, self.recipe)
        self.assertFalse(empty.exists())

    def test_symlink_input_escape_rejected(self):
        identifier = hashlib.sha256(b'input').hexdigest()
        (self.root / 'objects').mkdir()
        outside = self.root.parent / (self.root.name + '-outside')
        outside.write_bytes(b'input')
        self.addCleanup(outside.unlink)
        (self.root / 'objects' / identifier).symlink_to(outside)
        with self.assertRaises(ValueError):
            generate.verified_object(self.root, identifier, {identifier: {'size': 5}})

    def test_frozen_native_body_is_not_painted_or_relabelled(self):
        from PIL import Image
        native = self.root / 'native.png'
        image = Image.new('RGB', (13, 17), '#a23b45')
        image.putpixel((7, 9), (14, 29, 61))
        image.save(native)
        identifier = generate.digest(native)
        (self.root / 'objects').mkdir()
        native.rename(self.root / 'objects' / identifier)
        registry = {identifier: {'size': (self.root / 'objects' / identifier).stat().st_size}}
        result = generate.render_master('en-US/watch', {'native': identifier, 'approved_sha256': identifier}, self.root, self.root / 'render', registry)
        with Image.open(self.root / 'render' / result['path']) as rendered:
            self.assertEqual(image.tobytes(), rendered.tobytes())


if __name__ == '__main__':
    unittest.main()
