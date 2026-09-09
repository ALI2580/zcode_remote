"""Explicit-target Android UI observations for repeatable local acceptance.

Captures the app via ADB without changing screen resolution or app data. Optional
tap/key actions must use coordinates from the preceding observed UI state.
"""
import argparse
import json
from pathlib import Path
import subprocess
import sys
import xml.etree.ElementTree as ET

parser = argparse.ArgumentParser()
parser.add_argument('--adb', default='adb')
parser.add_argument('--target', required=True)
parser.add_argument('--tap', nargs=2, type=int)
parser.add_argument('--key', type=int)
parser.add_argument('--capture', type=Path)
args = parser.parse_args()
sys.stdout.reconfigure(encoding='utf-8')


def adb(*command):
    return subprocess.check_output([args.adb, '-s', args.target, *command],
                                   stderr=subprocess.PIPE)


if args.tap:
    adb('shell', 'input', 'tap', *map(str, args.tap))
if args.key is not None:
    adb('shell', 'input', 'keyevent', str(args.key))
# A failed dump may still exit successfully. Use a unique destination so an
# older tree can never be mistaken for the app that is currently on screen.
import uuid
dump_path = f'/sdcard/zcode_goal_ui_{uuid.uuid4().hex}.xml'
adb('shell', 'uiautomator', 'dump', dump_path)
raw = adb('shell', 'cat', dump_path)
adb('shell', 'rm', dump_path)
root = ET.fromstring(raw)
nodes = []
contains_credentials = False
for node in root.iter('node'):
    text = node.get('text') or node.get('content-desc') or ''
    if not text:
        continue
    if any(marker in text for marker in ['sid=', 'hash=']):
        contains_credentials = True
        text = '[connection credentials hidden]'
    nodes.append({'label': text[:160], 'bounds': node.get('bounds'),
                  'clickable': node.get('clickable') == 'true',
                  'focused': node.get('focused') == 'true'})
if args.capture:
    if contains_credentials:
        raise SystemExit('Capture skipped: connection credentials are visible.')
    args.capture.parent.mkdir(parents=True, exist_ok=True)
    args.capture.write_bytes(adb('exec-out', 'screencap', '-p'))
print(json.dumps({'target': args.target, 'nodes': nodes}, ensure_ascii=False))
