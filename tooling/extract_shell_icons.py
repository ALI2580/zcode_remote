"""Extract literal Lucide geometry from the pinned official resource cache."""
import argparse
import ast
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CACHE = ROOT / 'build/official-web/assets'
ASSETS = {
    'settings': 'settings-DGzz5RzI.js', 'monitor': 'monitor-Dk4C5vt2.js',
    'panel-left': 'panel-left-CagPHjZQ.js', 'panel-right': 'panel-right-DvO6_dj8.js',
    'user': 'user-USHNqSrf.js', 'laptop': 'laptop-DoO08fal.js',
    'bell': 'bell-Cj4pp-1A.js', 'chevrons-up-down': 'chevrons-up-down-DAkD-Phc.js',
    'pin': 'pin-nplgCZmD.js', 'pin-off': 'pin-off-mAP2ZDWG.js',
    'archive': 'archive-BPp9RwAu.js', 'archive-restore': 'archive-restore-BFdhz6oV.js',
    'trash-2': 'trash-2-CUVh-0Q9.js', 'refresh-cw': 'refresh-cw-CrsucGgd.js',
    'info': 'info-DYP8rQkz.js', 'at-sign': 'at-sign-XlrPuDDJ.js',
    'dollar-sign': 'dollar-sign-CCfR-h8e.js', 'square-slash': 'square-slash-Duxyw-_x.js',
    'list-filter': 'list-filter-B_lvRSsH.js', 'chevrons-down-up': 'chevrons-down-up-DLlfIHib.js',
    'blocks': 'blocks-CwqFb1Y2.js', 'message-circle-plus': 'message-circle-plus-B5OtqdXu.js',
    'list': 'list-B9sFlmuH.js',
    'arrow-down': 'index-nOVzQNKW.js',
}

def array_at(source, index):
    quote, depth = None, 0
    for offset in range(index, len(source)):
        char = source[offset]
        if quote:
            if char == quote and source[offset - 1] != '\\': quote = None
        elif char in '\'"`': quote = char
        elif char == '[': depth += 1
        elif char == ']':
            depth -= 1
            if depth == 0: return source[index:offset + 1]
    raise ValueError('Unclosed icon array')

def bindings(text):
    result = {}
    for item in text.split(','):
        pair = item.strip().split(' as ')
        result[pair[-1]] = pair[0]
    return result

def icon_nodes(path, exported='__iconNode', seen=None):
    seen = set() if seen is None else seen
    identity = (path.name, exported)
    if identity in seen: raise ValueError('Cyclic icon re-export')
    seen.add(identity)
    source = path.read_text(encoding='utf-8')
    exports = {}
    for match in re.finditer(r'export\{([^}]+)\}', source):
        exports.update(bindings(match.group(1)))
    local = exports[exported]
    match = re.search(r'(?<![\w$])' + re.escape(local) + r'=\[\[', source)
    if match:
        return array_at(source, source.index('[[', match.start()))
    for match in re.finditer(r'import\{([^}]+)\}from["`]([^"`]+)["`]', source):
        imports = bindings(match.group(1))
        if local in imports:
            return icon_nodes(path.parent / match.group(2), imports[local], seen)
    raise ValueError(f'Cannot resolve official geometry: {path.name}:{exported}')

def shapes(nodes):
    result = []
    for match in re.finditer(r'\[[`"\'](path|rect|circle|line|polyline)[`"\'],\{([^}]+)\}\]', nodes):
        kind, raw = match.groups()
        attrs = {m.group(1): m.group(3) for m in re.finditer(r'([\w]+):([`"\'])(.*?)\2', raw)}
        fields = {'path': ['d'], 'rect': ['x','y','width','height','rx'],
                  'circle': ['cx','cy','r'], 'line': ['x1','y1','x2','y2'], 'polyline': ['points']}[kind]
        values = [attrs.get(field, '0') for field in fields]
        if kind == 'circle': values.append('true' if attrs.get('fill') == 'currentColor' else 'false')
        result.append(({'path':'p','rect':'r','circle':'c','line':'l','polyline':'pl'}[kind], values))
    if not result: raise ValueError('No literal SVG geometry found')
    return result

parser = argparse.ArgumentParser()
parser.add_argument('--refresh', action='store_true', help='Correct existing geometry from official exports')
parser.add_argument('--check', action='store_true', help='Report differences without editing')
args = parser.parse_args()
target = ROOT / 'lib/ui/official_icons.dart'
dart = target.read_text(encoding='utf-8')
blocks = []
different = []
for name, filename in ASSETS.items():
    if filename == 'index-nOVzQNKW.js':
        source = (CACHE / filename).read_text(encoding='utf-8')
        factory = re.search(r'[\w$]+\([`"]' + re.escape(name) + r'[`"],([\w$]+)\)', source)
        if not factory: raise ValueError(f'Missing literal icon factory: {name}')
        definitions = list(re.finditer(r'(?<![\w$])' + re.escape(factory.group(1)) + r'=\[\[', source[:factory.start()]))
        match = definitions[-1]
        geometry = shapes(array_at(source, source.index('[[', match.start())))
    else:
        geometry = shapes(icon_nodes(CACHE / filename))
    old = re.search(r'["\']' + re.escape(name) + r'["\']:\s*LucideIconData\(', dart)
    old_range = None
    if old:
        start = dart.index('[', old.start())
        raw = array_at(dart, start)
        current = [(m.group(1), ast.literal_eval(m.group(2))) for m in
                   re.finditer(r"LucideShape\('([^']+)',\s*(\[[\s\S]*?\])\)", raw)]
        if current == geometry: continue
        old_range = (dart.rfind('\n', 0, old.start()) + 1, start + len(raw) + 2)
    different.append(name)
    if args.check or old and not args.refresh: continue
    lines = [f'  "{name}": LucideIconData("{name}", [']
    lines += [f"    LucideShape('{kind}', {json.dumps(values)})," for kind, values in geometry]
    lines.append('  ]),')
    block = '\n'.join(lines)
    if old_range:
        dart = dart[:old_range[0]] + block + dart[old_range[1]:]
    else:
        blocks.append(block)
anchor = 'const Map<String, LucideIconData> kOfficialIcons = {'
if blocks:
    dart = dart.replace(anchor, anchor + '\n' + '\n'.join(blocks), 1)
if not args.check and (blocks or args.refresh):
    target.write_text(dart, encoding='utf-8')
print(f'Official geometry differences: {different}')
if args.check and different: raise SystemExit(1)
