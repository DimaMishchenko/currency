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


    def localized_fixture(self):
        second = dict(self.placement, locale='de-DE', master='de-DE/home', path='de-DE/iphone/default/01-home.png')
        self.recipe['placements'].append(second)
        self.recipe['masters'][second['master']] = {'approved_sha256': self.sha}
        archive = self.root / 'localized-source.zip'
        with zipfile.ZipFile(archive, 'w') as target:
            for item in self.recipe['placements']:
                target.writestr(item['path'], self.png)
            target.writestr('manifest.json', 'private')
            target.writestr('mapping.csv', 'private')
        self.recipe['approved_archive_sha256'] = generate.digest(archive)
        video = self.root / 'localized.mp4'
        video.write_bytes(b'localized-video')
        sha = generate.digest(video)
        self.recipe['approved_header_sha256_by_locale'] = {'en-US': sha, 'de-DE': sha}
        mapping = self.root / 'headers.json'
        mapping.write_text(json.dumps({'schemaVersion':1,'headers':{locale:{'path':video.name,'sha256':sha} for locale in ['en-US','de-DE']}}))
        return archive, mapping, sha

    def test_localized_bundle_deduplicates_headers_and_unpacks_exact_mapping(self):
        archive, headers, sha = self.localized_fixture()
        first, second = self.root / 'a.zip', self.root / 'b.zip'
        generate.bundle_archive(archive, None, first, self.recipe, headers)
        generate.bundle_archive(archive, None, second, self.recipe, headers)
        self.assertEqual(first.read_bytes(), second.read_bytes())
        with zipfile.ZipFile(first) as bundle:
            self.assertEqual(len([name for name in bundle.namelist() if name.endswith('.mp4')]), 1)
            manifest = json.loads(bundle.read('manifest.json'))
            self.assertNotIn('header', manifest)
            self.assertEqual(set(manifest['headers']), {'en-US','de-DE'})
        self.recipe['approved_bundle_sha256'] = generate.digest(first)
        restored = generate.unpack_bundle(first, self.root / 'unpacked', self.recipe)
        self.assertEqual(restored, manifest)
        self.assertEqual((self.root / 'unpacked' / manifest['headers']['de-DE']['path']).read_bytes(), b'localized-video')

    def test_localized_bundle_refuses_missing_locale_and_global_fallback(self):
        archive, headers, sha = self.localized_fixture()
        mapping = json.loads(headers.read_text())
        del mapping['headers']['de-DE']
        headers.write_text(json.dumps(mapping))
        with self.assertRaisesRegex(ValueError, 'cover every placement locale'):
            generate.bundle_archive(archive, None, self.root / 'output.zip', self.recipe, headers)
        with self.assertRaisesRegex(ValueError, 'without a global fallback'):
            generate.bundle_archive(archive, self.root / 'localized.mp4', self.root / 'output.zip', self.recipe)
        del self.recipe['approved_header_sha256_by_locale']['de-DE']
        with self.assertRaisesRegex(ValueError, 'cover every placement locale'):
            generate.bundle_header_plan(self.recipe)
        self.assertFalse((self.root / 'output.zip').exists())

    def test_compact_base_reuses_exact_screenshots_and_rejects_source_drift(self):
        archive, headers, sha = self.localized_fixture()
        approved_headers = self.recipe.pop('approved_header_sha256_by_locale')
        original_header = self.root / 'old.mp4'
        original_header.write_bytes(b'old-header')
        self.recipe['approved_header_sha256'] = generate.digest(original_header)
        base_bundle = self.root / 'base.zip'
        generate.bundle_archive(archive, original_header, base_bundle, self.recipe)
        source_recipe = json.loads(json.dumps(self.recipe))
        source_recipe['approved_bundle_sha256'] = generate.digest(base_bundle)
        self.recipe['approved_header_sha256_by_locale'] = approved_headers
        first, second = self.root / 'localized-a.zip', self.root / 'localized-b.zip'
        generate.bundle_archive(base_bundle,None,first,self.recipe,headers,source_recipe)
        generate.bundle_archive(base_bundle,None,second,self.recipe,headers,source_recipe)
        self.assertEqual(first.read_bytes(),second.read_bytes())
        with zipfile.ZipFile(base_bundle) as old, zipfile.ZipFile(first) as new:
            pngs = [name for name in old.namelist() if name.endswith('.png')]
            self.assertEqual(pngs,[name for name in new.namelist() if name.endswith('.png')])
            self.assertTrue(all(old.read(name)==new.read(name) for name in pngs))
            self.assertNotIn('header/header.mp4',new.namelist())
        self.recipe['placements'][0]['order'] = 2
        with self.assertRaisesRegex(ValueError,'screenshots must remain unchanged'):
            generate.bundle_archive(base_bundle,None,self.root/'drift.zip',self.recipe,headers,source_recipe)
        self.recipe['placements'][0]['order'] = 1
        base_bundle.write_bytes(base_bundle.read_bytes()+b'corrupt')
        with self.assertRaisesRegex(ValueError,'source bundle hash mismatch'):
            generate.bundle_archive(base_bundle,None,self.root/'corrupt.zip',self.recipe,headers,source_recipe)

    def test_localized_bundle_confines_video_paths_and_checks_bytes(self):
        archive, headers, sha = self.localized_fixture()
        mapping = json.loads(headers.read_text())
        mapping['headers']['de-DE']['path'] = '../outside.mp4'
        headers.write_text(json.dumps(mapping))
        with self.assertRaisesRegex(ValueError, 'Invalid relative path'):
            generate.bundle_archive(archive, None, self.root / 'output.zip', self.recipe, headers)
        mapping['headers']['de-DE']['path'] = 'localized.mp4'
        headers.write_text(json.dumps(mapping))
        (self.root / 'localized.mp4').write_bytes(b'changed')
        with self.assertRaisesRegex(ValueError, 'header bytes mismatch'):
            generate.bundle_archive(archive, None, self.root / 'output.zip', self.recipe, headers)


if __name__ == '__main__':
    unittest.main()
