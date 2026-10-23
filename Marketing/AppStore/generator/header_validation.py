import ast
import hashlib
import json


def pixel_source_sha256(source):
    tree = ast.parse(source)
    nodes = []
    started = False
    for node in tree.body:
        if isinstance(node, ast.Assign) and any(isinstance(target, ast.Tuple) and [getattr(item, 'id', None) for item in target.elts] == ['W', 'H', 'FPS', 'DURATION'] for target in node.targets):
            started = True
        if not started:
            continue
        if isinstance(node, ast.Expr) and isinstance(node.value, ast.Call) and ast.unparse(node.value.func) == 'args.output.mkdir':
            break
        if isinstance(node, ast.Assign) and any(isinstance(target, ast.Name) and target.id in {'cache_identity', 'background_cache'} for target in node.targets):
            continue
        nodes.append(ast.dump(node, include_attributes=False))
    if not nodes:
        raise ValueError('Pixel renderer section is missing')
    return hashlib.sha256('\n'.join(nodes).encode()).hexdigest()


def fingerprint(identity):
    return hashlib.sha256(json.dumps(identity, sort_keys=True, separators=(',', ':')).encode()).hexdigest()


def background_identity(identity):
    return fingerprint({key: identity[key] for key in ('pixelSourceSha256', 'sourceSha256', 'fontSha256', 'pillow', 'freetype')})


def validate_entry(root, locale, currencies, identity, video):
    entry = json.loads((root / locale / 'manifest.json').read_text())
    if entry.get('locale') != locale or entry.get('currencies') != currencies or entry.get('renderIdentity') != identity:
        raise ValueError('Stale locale manifest: ' + locale)
    poster = root / locale / 'poster.png'
    if not poster.is_file() or hashlib.sha256(poster.read_bytes()).hexdigest() != entry.get('posterSha256'):
        raise ValueError('Stale locale poster: ' + locale)
    if video:
        path = root / locale / 'header.mp4'
        if entry.get('videoComplete') is not True or entry.get('uniqueInputFrames') != 900 or entry.get('uniqueDecodedFrames') != 900:
            raise ValueError('Incomplete locale video proof: ' + locale)
        if not path.is_file() or hashlib.sha256(path.read_bytes()).hexdigest() != entry.get('videoSha256'):
            raise ValueError('Stale locale video: ' + locale)
    return entry
