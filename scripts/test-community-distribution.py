#!/usr/bin/env python3
"""Synthetic regression tests for distribution verification, no apps/network/vaults."""
import copy
import importlib.util
import io
import json
import plistlib
import tarfile
import tempfile
import unittest
from pathlib import Path

spec = importlib.util.spec_from_file_location('distribution', Path(__file__).with_name('community-distribution.py'))
distribution = importlib.util.module_from_spec(spec)
spec.loader.exec_module(distribution)


class DistributionTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        self.value = distribution.config()
        self.revision = 'a' * 40
        self.assets = self.root / 'assets'
        self.assets.mkdir()
        for name in distribution.expected_files(self.value) - {'RELEASE_MANIFEST.json', 'SHA256SUMS'}:
            (self.assets / name).write_text('Synthetic release fixture\n')
        (self.assets / 'SOURCE_REVISION.txt').write_text(self.revision + '\n')
        (self.assets / 'BUILD_INFO.txt').write_text('Mode: release\nUncommitted source: no\n')
        self.write_archive()
        distribution.write_manifest(self.assets, self.value, self.revision)

    def tearDown(self):
        self.temporary.cleanup()

    def write_archive(self, unsafe=False):
        prefix = 'CopySaver-' + self.value['tag'][1:]
        path = self.assets / distribution.names(self.value)[1]
        with tarfile.open(path, 'w:gz', pax_headers={'comment': self.revision}) as archive:
            data = json.dumps(self.value).encode()
            member = tarfile.TarInfo(prefix + '/release.json'); member.size = len(data)
            archive.addfile(member, io.BytesIO(data))
            if unsafe:
                member = tarfile.TarInfo(prefix + '/../escaped.txt'); member.size = 4
                archive.addfile(member, io.BytesIO(b'test'))

    def test_complete_bundle_verifies(self):
        self.assertEqual(distribution.verify(self.assets, self.value)['source_revision'], self.revision)

    def test_modified_asset_fails(self):
        (self.assets / distribution.names(self.value)[0]).write_bytes(b'changed')
        with self.assertRaisesRegex(ValueError, 'Checksum failed'):
            distribution.verify(self.assets, self.value)

    def test_extra_private_file_is_rejected(self):
        (self.assets / 'vault.sqlite').write_bytes(b'synthetic')
        with self.assertRaisesRegex(ValueError, 'unexpected release files'):
            distribution.verify(self.assets, self.value)

    def test_symlink_is_rejected(self):
        path = self.assets / 'INSTALL.md'; path.unlink(); path.symlink_to(self.assets / 'COMMUNITY.txt')
        with self.assertRaisesRegex(ValueError, 'regular files'):
            distribution.verify(self.assets, self.value)

    def test_source_revision_cannot_be_substituted(self):
        manifest = json.loads((self.assets / 'RELEASE_MANIFEST.json').read_text())
        manifest['source_revision'] = 'b' * 40
        (self.assets / 'RELEASE_MANIFEST.json').write_text(json.dumps(manifest))
        with self.assertRaisesRegex(ValueError, 'Source manifest mismatch'):
            distribution.verify(self.assets, self.value)

    def test_archive_traversal_is_rejected_even_with_matching_hash(self):
        self.write_archive(unsafe=True)
        distribution.write_manifest(self.assets, self.value, self.revision)
        with self.assertRaisesRegex(ValueError, 'Unsafe source archive'):
            distribution.verify(self.assets, self.value)

    def test_dirty_artifact_is_not_a_release(self):
        (self.assets / 'BUILD_INFO.txt').write_text('Mode: --preview\nUncommitted source: yes\n')
        distribution.write_manifest(self.assets, self.value, self.revision)
        with self.assertRaisesRegex(ValueError, 'Dirty/local preview'):
            distribution.verify(self.assets, self.value)

    def test_beta_version_contract_cannot_drift(self):
        for folder in ['App', 'Widget']:
            (self.root / folder).mkdir()
            (self.root / folder / 'Info.plist').write_bytes((distribution.ROOT / folder / 'Info.plist').read_bytes())
        notes = self.root / 'docs/releases'; notes.mkdir(parents=True)
        (notes / (self.value['tag'] + '.md')).write_text('Synthetic notes')
        (self.root / 'release.json').write_text(json.dumps(self.value))
        self.assertEqual(distribution.config(self.root), self.value)
        info = plistlib.loads((self.root / 'App/Info.plist').read_bytes()); info['CFBundleVersion'] = '999'
        (self.root / 'App/Info.plist').write_bytes(plistlib.dumps(info))
        with self.assertRaisesRegex(ValueError, 'version drift'):
            distribution.config(self.root)


if __name__ == '__main__':
    unittest.main()
