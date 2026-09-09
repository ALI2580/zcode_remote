"""Freeze an already-built development APK and its reviewable source state."""

import argparse
import hashlib
import json
import re
import subprocess
import zipfile
from datetime import datetime, timezone
from pathlib import Path


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--stage', required=True)
    args = parser.parse_args()
    if not re.fullmatch(r'[a-z0-9-]+', args.stage):
        parser.error('stage must contain only lowercase letters, digits or hyphens')
    root = Path(__file__).resolve().parents[1]
    out = root / 'build/artifacts'
    stem = f'ZcodeRemote-v2-{args.stage}'
    apk = out / f'{stem}-dev.apk'
    if not apk.is_file():
        parser.error(f'copy the verified product APK to {apk} first')
    version = re.search(r'^version:\s*(\S+)',
                        (root / 'pubspec.yaml').read_text(encoding='utf-8'), re.M).group(1)
    paths = set()
    for folder in ['lib', 'assets', 'test', 'integration_test', 'tooling', 'android/app/src']:
        directory = root / folder
        if directory.exists():
            paths.update(p for p in directory.rglob('*')
                         if p.is_file() and '__pycache__' not in p.parts)
    for name in ['pubspec.yaml', 'pubspec.lock', 'analysis_options.yaml',
                 'android/app/build.gradle.kts', 'android/build.gradle.kts',
                 'android/settings.gradle.kts', 'android/gradle.properties',
                 'android/gradle/wrapper/gradle-wrapper.properties',
                 'android/gradle/wrapper/gradle-wrapper.jar',
                 'android/gradlew', 'android/gradlew.bat']:
        path = root / name
        if path.is_file():
            paths.add(path)
    files = {p.relative_to(root).as_posix(): digest(p) for p in sorted(paths)}
    manifest_path = out / f'{stem}-manifest.json'
    if manifest_path.exists():
        previous = json.loads(manifest_path.read_text(encoding='utf-8'))
        if previous['sourceFiles'] != files or previous['apkSha256'] != digest(apk):
            parser.error('stage already exists with a different code state; use a new stage')
        print('Existing stage matches the current source and APK.')
        return
    archive = out / f'{stem}-source.zip'
    with zipfile.ZipFile(archive, 'x', zipfile.ZIP_DEFLATED) as target:
        for name in files:
            target.write(root / name, name)
    manifest = {
        'stage': args.stage,
        'createdAtUtc': datetime.now(timezone.utc).isoformat(),
        'version': version,
        'package': 'com.zcoderemote.zcode_remote.dev',
        'apk': apk.name,
        'apkSha256': digest(apk),
        'engineAbis': ['arm64-v8a', 'x86_64'],
        'baseCommit': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=root,
                                             text=True).strip(),
        'workingTreeUncommitted': bool(subprocess.check_output(
            ['git', 'status', '--porcelain'], cwd=root, text=True).strip()),
        'sourceArchive': archive.name,
        'sourceArchiveSha256': digest(archive),
        'sourceStateSha256': hashlib.sha256(json.dumps(
            files, sort_keys=True, separators=(',', ':')).encode()).hexdigest(),
        'sourceFiles': files,
    }
    manifest_path.write_text(json.dumps(manifest, indent=2) + '\n', encoding='utf-8')
    (out / f'{apk.name}.sha256').write_text(manifest['apkSha256'] + '  ' + apk.name + '\n', encoding='utf-8')
    print(json.dumps({k: v for k, v in manifest.items() if k != 'sourceFiles'}, indent=2))
    print(f'Source files: {len(files)}')


if __name__ == '__main__':
    main()
