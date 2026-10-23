import ast
import hashlib
import json
import unicodedata


def resolve_currencies(configuration, locale):
    currencies = []
    glyphs = set()
    for code in configuration['locales'][locale] + configuration['fallbacks']:
        glyph = configuration['glyphs'].get(code, '')
        if len(glyph) != 1 or unicodedata.category(glyph) != 'Sc' or glyph in glyphs:
            continue
        currencies.append(code)
        glyphs.add(glyph)
        if len(currencies) == 3:
            return currencies
    raise ValueError('Three distinct currency signs are unavailable: ' + locale)


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


def validate_entry(root, locale, configuration, identity, video):
    currencies = resolve_currencies(configuration, locale)
    glyphs = [configuration['glyphs'][code] for code in currencies]
    entry = json.loads((root / locale / 'manifest.json').read_text())
    if entry.get('locale') != locale or entry.get('currencies') != currencies or entry.get('renderIdentity') != identity:
        raise ValueError('Stale locale manifest: ' + locale)
    if entry.get('glyphs') != glyphs or entry.get('reels') != currency_reels(glyphs, configuration['spinGlyphs']):
        raise ValueError('Invalid locale currency signs: ' + locale)
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


def currency_reels(glyphs, spin_glyphs):
    if len(glyphs) != 3 or len(set(glyphs)) != 3:
        raise ValueError('Three distinct opening signs are required')
    if len(set(spin_glyphs)) < 6 or len(set(spin_glyphs)) != len(spin_glyphs) or any(len(sign) != 1 or unicodedata.category(sign) != 'Sc' for sign in spin_glyphs):
        raise ValueError('At least six distinct currency signs are required for the spins')
    seed = '|'.join(glyphs)
    def ranked(signs, stage):
        return sorted(signs, key=lambda sign: hashlib.sha256((seed + ':' + stage + ':' + sign).encode()).digest())
    settled = ranked([sign for sign in spin_glyphs if sign not in glyphs], 'settled')[:3]
    reels = []
    for index, opening in enumerate(glyphs):
        moving = ranked(spin_glyphs, str(index))
        reels.append([opening, moving[0], moving[1], settled[index], moving[2], moving[3], opening])
    return reels
