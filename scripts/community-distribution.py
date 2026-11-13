#!/usr/bin/env python3
"""Prepare/audit certificate-free beta assets. Never publishes or changes OS trust."""
import argparse
import gzip
import hashlib
import json
import plistlib
import re
import shutil
import subprocess
import tarfile
import tempfile
from pathlib import Path, PurePosixPath

ROOT = Path(__file__).resolve().parent.parent
METADATA = ['SOURCE_REVISION.txt', 'TOOLCHAIN.txt', 'DEPENDENCIES.txt', 'BUILD_INFO.txt']
DOCUMENTS = {'INSTALL.md': 'docs/INSTALL.md', 'COMMUNITY.txt': 'docs/COMMUNITY.txt', 'LICENSE.txt': 'LICENSE'}


def require(condition, message):
    if not condition:
        raise ValueError(message)


def digest(path):
    checksum = hashlib.sha256()
    with path.open('rb') as source:
        for block in iter(lambda: source.read(1_048_576), b''):
            checksum.update(block)
    return checksum.hexdigest()


def config(root=ROOT, tag=None):
    value = json.loads((root / 'release.json').read_text())
    match = re.fullmatch(r'v(\d+\.\d+\.\d+)-beta\.([1-9]\d*)', value['tag'])
    require(value['schema_version'] == 1 and value['channel'] == 'beta' and match, 'Only explicit beta releases are enabled while stable gates remain open.')
    require(value['version'] == match[1] and value['label'] == 'Beta ' + match[2], 'Release label/version/tag mismatch.')
    require(re.fullmatch(r'[1-9]\d*', value['build']), 'Positive build number required.')
    require(value['architectures'] == ['arm64', 'x86_64'] and value['minimum_macos'] == '14.0', 'Unexpected platform contract.')
    require(re.fullmatch(r'[A-Za-z0-9_-]+/[A-Za-z0-9_.-]+', value['repository']), 'Invalid repository name.')
    require(tag is None or tag == value['tag'], 'Requested tag does not match reviewed release.json.')
    for folder in ['App', 'Widget']:
        info = plistlib.loads((root / folder / 'Info.plist').read_bytes())
        require(info['CFBundleShortVersionString'] == value['version'] and info['CFBundleVersion'] == value['build'], 'App/widget version drift.')
        require(info.get('CopySaverReleaseChannel') == value['channel'] and info.get('CopySaverReleaseLabel') == value['label'], 'App/widget beta label drift.')
    require((root / 'docs/releases' / (value['tag'] + '.md')).is_file(), 'Reviewed release notes required.')
    return value


def names(value):
    base = 'CopySaver-' + value['tag'][1:]
    return base + '-universal.dmg', base + '-source.tar.gz'


def expected_files(value):
    return set(METADATA + list(DOCUMENTS) + ['RELEASE_NOTES.md', 'RELEASE_MANIFEST.json', 'SHA256SUMS'] + list(names(value)))


def write_manifest(directory, value, revision):
    files = sorted(expected_files(value) - {'SHA256SUMS', 'RELEASE_MANIFEST.json'})
    manifest = {
        'schema_version': 1, 'tag': value['tag'], 'version': value['version'], 'build': value['build'],
        'channel': value['channel'], 'source_revision': revision, 'repository': value['repository'],
        'minimum_macos': value['minimum_macos'], 'architectures': value['architectures'],
        'storage_profile': 'automatic', 'apple_certificate': False, 'notarized': False,
        'artifacts': {name: {'bytes': (directory / name).stat().st_size, 'sha256': digest(directory / name)} for name in files},
    }
    (directory / 'RELEASE_MANIFEST.json').write_text(json.dumps(manifest, indent=2, sort_keys=True) + '\n')
    files.append('RELEASE_MANIFEST.json')
    (directory / 'SHA256SUMS').write_text(''.join(digest(directory / name) + '  ' + name + '\n' for name in sorted(files)))


def verify(directory, value):
    require(directory.is_dir() and not directory.is_symlink(), 'A real release directory is required.')
    require({p.name for p in directory.iterdir()} == expected_files(value), 'Missing or unexpected release files.')
    require(all(p.is_file() and not p.is_symlink() for p in directory.iterdir()), 'Release files must be regular files, not links.')
    manifest = json.loads((directory / 'RELEASE_MANIFEST.json').read_text())
    for key in ['tag', 'version', 'build', 'channel', 'repository', 'architectures', 'minimum_macos']:
        require(manifest.get(key) == value[key], 'Manifest release identity mismatch: ' + key)
    require(manifest.get('schema_version') == 1 and manifest.get('storage_profile') == 'automatic', 'Unexpected manifest/profile.')
    require(manifest.get('apple_certificate') is False and manifest.get('notarized') is False, 'Community signing policy mismatch.')
    revision = manifest.get('source_revision', '')
    require(re.fullmatch(r'[0-9a-f]{40}', revision), 'Exact source commit required.')
    require((directory / 'SOURCE_REVISION.txt').read_text().strip() == revision, 'Source manifest mismatch.')
    build_info = (directory / 'BUILD_INFO.txt').read_text()
    require('Mode: release\n' in build_info and 'Uncommitted source: no\n' in build_info, 'Dirty/local preview input is not a release candidate.')
    expected_artifacts = expected_files(value) - {'RELEASE_MANIFEST.json', 'SHA256SUMS'}
    require(set(manifest['artifacts']) == expected_artifacts, 'Artifact allowlist mismatch.')
    sums = {}
    for line in (directory / 'SHA256SUMS').read_text().splitlines():
        match = re.fullmatch(r'([0-9a-f]{64})  ([A-Za-z0-9_.-]+)', line)
        require(match is not None and match[2] not in sums, 'Malformed or duplicate checksum entry.')
        sums[match[2]] = match[1]
    require(set(sums) == expected_files(value) - {'SHA256SUMS'}, 'Checksum allowlist mismatch.')
    for name, checksum in sums.items():
        require(digest(directory / name) == checksum, 'Checksum failed: ' + name)
        if name in manifest['artifacts']:
            info = manifest['artifacts'][name]
            require(info == {'bytes': (directory / name).stat().st_size, 'sha256': checksum}, 'Artifact manifest mismatch: ' + name)
    for name in ['INSTALL.md', 'RELEASE_NOTES.md']:
        for target in re.findall(r'!?\[[^\]]*\]\(([^\s)]+)\)', (directory / name).read_text()):
            if '://' in target or target.startswith(('mailto:', '#')):
                continue
            require(target.split('#', 1)[0] in expected_files(value), 'Unresolvable standalone documentation link.')
    prefix = 'CopySaver-' + value['tag'][1:]
    with tarfile.open(directory / names(value)[1], 'r:gz') as archive:
        require(archive.pax_headers.get('comment') == revision, 'Source archive commit identity mismatch.')
        for member in archive.getmembers():
            path = PurePosixPath(member.name)
            require(path.parts and not path.is_absolute() and '..' not in path.parts and path.parts[0] == prefix, 'Unsafe source archive path.')
            require(member.isfile() or member.isdir(), 'Unsupported link/device in source archive.')
            require(not any(part in ['.git', '.build', 'dist'] for part in path.parts[1:]), 'Generated/private directory in source archive.')
        stream = archive.extractfile(prefix + '/release.json')
        require(stream is not None, 'Archived config must be a regular file.')
        info = json.load(stream)
        require(info == value, 'Archived release config mismatch.')
    return manifest


def audit_image(source, value):
    app = source / 'CopySaver.app'
    subprocess.run(['python3', '-O', str(ROOT / 'scripts/check-community-artifact.py'), str(app)], check=True)
    info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
    require(info['CFBundleShortVersionString'] == value['version'] and info['CFBundleVersion'] == value['build'], 'Built app release version mismatch.')
    require(info.get('CopySaverReleaseLabel') == value['label'], 'Built app beta label mismatch.')
    dmg = source / 'CopySaver-community.dmg'
    subprocess.run(['hdiutil', 'verify', str(dmg)], check=True)
    mount = Path(tempfile.mkdtemp(prefix='release-audit-', dir=ROOT / '.build'))
    mounted = False
    try:
        subprocess.run(['hdiutil', 'attach', '-readonly', '-nobrowse', '-noautoopen', '-mountpoint', str(mount), str(dmg)], check=True, stdout=subprocess.DEVNULL)
        mounted = True
        bundled = mount / 'CopySaver.app'
        subprocess.run(['python3', '-O', str(ROOT / 'scripts/check-community-artifact.py'), str(bundled)], check=True)
        for path in ['Contents/Info.plist', 'Contents/MacOS/CopySaver', 'Contents/Resources/AppIcon.icns', 'Contents/Resources/LICENSE']:
            require(digest(app / path) == digest(bundled / path), 'Mounted app identity mismatch.')
        require((mount / 'Applications').is_symlink() and (mount / 'Applications').readlink() == Path('/Applications'), 'Applications link missing.')
        require((mount / 'Read me.txt').read_bytes() == (ROOT / 'docs/COMMUNITY.txt').read_bytes(), 'Installer notes mismatch.')
        require((mount / 'License.txt').read_bytes() == (ROOT / 'LICENSE').read_bytes(), 'Installer license missing.')
    finally:
        if mounted:
            subprocess.run(['hdiutil', 'detach', str(mount)], check=True)
        mount.rmdir()


def prepare(value):
    source = ROOT / '.build/community'
    output = ROOT / 'dist' / value['tag']
    require(not output.exists(), 'Preserve the existing release directory before preparing another.')
    require(not subprocess.check_output(['git', 'status', '--porcelain'], cwd=ROOT), 'A clean reviewed source checkout is required.')
    revision = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip()
    require((source / 'SOURCE_REVISION.txt').read_text().strip() == revision, 'Rebuild the app from the current reviewed commit.')
    audit_image(source, value)
    output.parent.mkdir(exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='release-stage-', dir=output.parent) as temporary:
        directory = Path(temporary)
        for name in METADATA:
            shutil.copy2(source / name, directory / name)
        for name, path in DOCUMENTS.items():
            shutil.copy2(ROOT / path, directory / name)
        shutil.copy2(ROOT / 'docs/releases' / (value['tag'] + '.md'), directory / 'RELEASE_NOTES.md')
        dmg, archive = names(value)
        shutil.copy2(source / 'CopySaver-community.dmg', directory / dmg)
        tree = subprocess.check_output(['git', 'archive', '--format=tar', '--prefix=CopySaver-' + value['tag'][1:] + '/', revision], cwd=ROOT)
        (directory / archive).write_bytes(gzip.compress(tree, mtime=0))
        write_manifest(directory, value, revision)
        verify(directory, value)
        directory.rename(output)
    print('Audited beta assets prepared: ' + str(output))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('command', choices=['config', 'prepare', 'verify'])
    parser.add_argument('path_or_tag', nargs='?')
    args = parser.parse_args()
    value = config(tag=args.path_or_tag if args.command == 'config' else None)
    if args.command == 'config':
        print(value['tag'] + ' / ' + value['label'] + ' / build ' + value['build'])
    elif args.command == 'prepare':
        require(args.path_or_tag is None, 'prepare uses the reviewed default build/output paths.')
        prepare(value)
    else:
        directory = Path(args.path_or_tag) if args.path_or_tag else ROOT / 'dist' / value['tag']
        verify(directory, value)
        print('Release manifest, checksums and source archive verified: ' + str(directory))


if __name__ == '__main__':
    try:
        main()
    except (ValueError, KeyError, OSError, tarfile.TarError, json.JSONDecodeError, subprocess.CalledProcessError) as error:
        raise SystemExit('Distribution check failed: ' + str(error))
