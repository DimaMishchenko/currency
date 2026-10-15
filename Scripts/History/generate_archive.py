import argparse
import csv
import datetime
import hashlib
import io
import json
import math
import os
from pathlib import Path
import re
import tempfile
import urllib.request


ROOT = Path(__file__).resolve().parents[2]
OUTPUT = ROOT / 'Domain/ExchangeRates/Sources/ExchangeRates/Resources/history-monthly-v1.json'
CATALOG = ROOT / 'Domain/ExchangeRates/Sources/ExchangeRates/CurrencyCode.swift'
CODES = 'btc eth usdc usdt doge ltc xrp ada link dot bch xlm uni etc aave algo icp'.split()
PROVIDERS = 'AMCM,BAM,BANREP,BCB,BCBO,BCC,BCCH,BCP,BCRA,BCT,BDI,BDP,BI,BIS,BNA,BNM,BNR,BOA,BOC,BOJA,BOM,BOT,BOTA,BOZ,BRB,CBA,CBAR,CBC,CBG,CBI,CBK,CBLLR,CBM,CBS,CBSL,CBU,DAB,DNB,ECB,HMRC,HNB,INFOREURO,JPC,LB,MAS,MMA,MNB,NBC,NBE,NBG,NBK,NBKR,NBM,NBP,NBRB,NBRM,NBT,NRB,NRBT,RB,RBF,RBM,RBV,SARB,SBI,UST'
STATIC_START = '2010-07-18'
STATIC_END = '2024-03-01'
EPOCH = datetime.date(1970, 1, 1)
SECTIONS = ('crypto', 'cryptoFX', 'fiat', 'fawaz')
VOLATILE_METADATA = {'acquired', 'cryptoInputSHA256', 'fiatInputSHA256', 'fawazInputSHA256'}


def publication_days(today):
    current = today.replace(day=1)
    cursor = datetime.date(2024, 3, 1)
    days = []
    while cursor < current:
        days.append('2024-03-02' if cursor == datetime.date(2024, 3, 1) else cursor.isoformat())
        cursor = (cursor.replace(day=28) + datetime.timedelta(days=4)).replace(day=1)
    return days


def positive(value):
    if isinstance(value, bool):
        raise ValueError('Boolean exchange rate')
    value = float(value)
    if not math.isfinite(value) or value <= 0:
        raise ValueError('Invalid exchange rate')
    return value


def valid_day(value):
    if datetime.date.fromisoformat(value).isoformat() != value:
        raise ValueError('Invalid observation date')
    return value


def canonical_hash(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True).encode()).hexdigest()


def packed(rows):
    return [[(datetime.date.fromisoformat(day) - EPOCH).days, value] for day, value in rows]


def build_archive(crypto, fiat, tables, allowed, today):
    days = publication_days(today)
    if not days:
        raise ValueError('No completed Fawaz months')
    fx = {}
    for row in fiat:
        day = valid_day(row['date'])
        if row['base'] != 'USD':
            raise ValueError('Unexpected Frankfurter base')
        rate = positive(row['rate'])
        if '2010-07-01' <= day < STATIC_END and row['quote'] in allowed:
            fx.setdefault(row['quote'], {})[day] = rate
    if not fx.get('EUR'):
        raise ValueError('Missing selected historical FX observations')
    fx['USD'] = {day: 1.0 for rows in fx.values() for day in rows}
    monthly = {}
    aligned = {}
    for code in CODES:
        observations = {}
        for day, value in crypto[code]:
            day = valid_day(day)
            value = positive(value)
            if STATIC_START <= day < STATIC_END:
                observations[day] = value
        if not observations:
            raise ValueError(f'Missing historical crypto observations: {code}')
        months = {}
        for day, value in sorted(observations.items()):
            months[day[:7]] = [day, value]
        monthly[code.upper()] = packed(months.values())
        aligned[code.upper()] = packed((day, observations[day]) for day in sorted(fx['USD']) if day in observations)
    fawaz = {}
    for day in days:
        table = tables[day]
        if table['date'] != day:
            raise ValueError(f'Wrong publication date: {day}')
        if positive(table['usd']['usd']) != 1:
            raise ValueError(f'Unexpected USD identity: {day}')
        positive(table['usd']['eur'])
        positive(table['usd']['btc'])
        for code, value in table['usd'].items():
            if code.upper() in allowed:
                fawaz.setdefault(code.upper(), []).append([day, positive(value)])
    cutoff = (today.replace(day=1) - datetime.timedelta(days=1)).strftime('%B%Y')
    return {
        'version': 1,
        'provenance': {
            'acquired': today.isoformat(),
            'cryptoSource': 'https://github.com/coinmetrics/data',
            'cryptoMetric': 'PriceUSD',
            'cryptoSampling': 'Last available positive daily observation per completed month; cryptoFX preserves observations matching FX monthly bucket dates.',
            'fiatSource': 'https://api.frankfurter.dev/v2/rates',
            'fiatSampling': 'group=month monthly reference buckets; cross-source joins are approximations.',
            'licenses': ['CC-BY-NC-4.0.txt', 'CC-BY-4.0.txt', 'Fawaz-CC0-1.0.txt'],
            'notice': 'DataSources.md',
            'fawazSource': 'https://github.com/fawazahmed0/exchange-api',
            'fawazSampling': f'First daily publication of each completed month March2024 through {cutoff}, March2024 uses earliest available March2; USD quote table; CC0-1.0.',
            'cryptoInputSHA256': canonical_hash(crypto),
            'fiatInputSHA256': canonical_hash(fiat),
            'fawazInputSHA256': canonical_hash(tables),
        },
        'providers': PROVIDERS.split(','),
        'crypto': monthly,
        'cryptoFX': aligned,
        'fiat': {code: packed(sorted(rows.items())) for code, rows in fx.items()},
        'fawaz': {code: packed(rows) for code, rows in fawaz.items()},
    }


def semantic_content(archive):
    result = dict(archive)
    result['provenance'] = {key: value for key, value in archive['provenance'].items() if key not in VOLATILE_METADATA}
    return result


def write_archive(output, archive):
    if output.exists():
        existing = json.loads(output.read_text())
        if semantic_content(existing) == semantic_content(archive):
            return False
        for section in SECTIONS:
            for code, rows in existing[section].items():
                new_rows = archive[section].get(code, [])
                if not {row[0] for row in rows}.issubset({row[0] for row in new_rows}):
                    raise ValueError(f'Historical coverage decreased: {section}/{code}')
    encoded = (json.dumps(archive, separators=(',', ':'), sort_keys=True, allow_nan=False) + '\n').encode()
    output.parent.mkdir(parents=True, exist_ok=True)
    temporary = None
    try:
        with tempfile.NamedTemporaryFile(dir=output.parent, prefix=f'.{output.name}.', delete=False) as stream:
            temporary = Path(stream.name)
            stream.write(encoded)
        temporary.replace(output)
    finally:
        if temporary is not None:
            temporary.unlink(missing_ok=True)
    return True


def fetch_json(url):
    with urllib.request.urlopen(url, timeout=120) as response:
        return json.load(response)


def load_sources(args, today):
    if args.crypto_input:
        crypto = json.loads(args.crypto_input.read_text())
    else:
        crypto = {}
        for code in CODES:
            url = f'https://raw.githubusercontent.com/coinmetrics/data/master/csv/{code}.csv'
            with urllib.request.urlopen(url, timeout=120) as response:
                rows = csv.DictReader(io.TextIOWrapper(response, encoding='utf-8'))
                crypto[code] = [[row['time'], row['PriceUSD']] for row in rows if row.get('PriceUSD') and STATIC_START <= row['time'] <= STATIC_END and positive(row['PriceUSD'])]
    fiat = json.loads(args.fiat_input.read_text()) if args.fiat_input else fetch_json(
        f'https://api.frankfurter.dev/v2/rates?base=USD&from=2010-07-01&to=2024-02-29&group=month&providers={PROVIDERS}')
    tables = {}
    for day in publication_days(today):
        if args.fawaz_input:
            tables[day] = json.loads((args.fawaz_input / f'{day}.json').read_text())
        else:
            try:
                tables[day] = fetch_json(f'https://cdn.jsdelivr.net/npm/@fawazahmed0/currency-api@{day}/v1/currencies/usd.min.json')
            except (OSError, ValueError):
                tables[day] = fetch_json(f'https://{day}.currency-api.pages.dev/v1/currencies/usd.min.json')
    return crypto, fiat, tables


def main(argv=None):
    parser = argparse.ArgumentParser()
    parser.add_argument('--crypto-input', type=Path)
    parser.add_argument('--fiat-input', type=Path)
    parser.add_argument('--fawaz-input', type=Path)
    parser.add_argument('--output', type=Path, default=OUTPUT)
    parser.add_argument('--today', type=datetime.date.fromisoformat, default=datetime.datetime.now(datetime.timezone.utc).date())
    args = parser.parse_args(argv)
    allowed = set(re.findall(r'case \w+ = "([A-Z]+)"', CATALOG.read_text()))
    crypto, fiat, tables = load_sources(args, args.today)
    archive = build_archive(crypto, fiat, tables, allowed, args.today)
    changed = write_archive(args.output, archive)
    print(f'{"Updated" if changed else "Unchanged"}: {args.output} ({args.output.stat().st_size} bytes)')
    if os.environ.get('GITHUB_OUTPUT'):
        with open(os.environ['GITHUB_OUTPUT'], 'a') as stream:
            stream.write(f'changed={str(changed).lower()}\n')
    return changed


if __name__ == '__main__':
    main()
