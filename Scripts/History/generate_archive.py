import argparse, csv, datetime, hashlib, io, json, pathlib, re, urllib.request

parser = argparse.ArgumentParser()
parser.add_argument('--crypto-input', type=pathlib.Path)
parser.add_argument('--fiat-input', type=pathlib.Path)
parser.add_argument('--fawaz-input', type=pathlib.Path)
parser.add_argument('--output', type=pathlib.Path, default=pathlib.Path('Domain/ExchangeRates/Sources/ExchangeRates/Resources/history-monthly-v1.json'))
args = parser.parse_args()
allowed = set(re.findall(r'case \w+ = "([A-Z]+)"', pathlib.Path('Domain/ExchangeRates/Sources/ExchangeRates/CurrencyCode.swift').read_text()))
codes = 'btc eth usdc usdt doge ltc xrp ada link dot bch xlm uni etc aave algo icp'.split()
providers = 'AMCM,BAM,BANREP,BCB,BCBO,BCC,BCCH,BCP,BCRA,BCT,BDI,BDP,BI,BIS,BNA,BNM,BNR,BOA,BOC,BOJA,BOM,BOT,BOTA,BOZ,BRB,CBA,CBAR,CBC,CBG,CBI,CBK,CBLLR,CBM,CBS,CBSL,CBU,DAB,DNB,ECB,HMRC,HNB,INFOREURO,JPC,LB,MAS,MMA,MNB,NBC,NBE,NBG,NBK,NBKR,NBM,NBP,NBRB,NBRM,NBT,NRB,NRBT,RB,RBF,RBM,RBV,SARB,SBI,UST'
def fetch(url):
    with urllib.request.urlopen(url, timeout=120) as response:
        return response.read()
if args.crypto_input:
    crypto = json.loads(args.crypto_input.read_text())
else:
    crypto = {}
    for code in codes:
        rows = csv.DictReader(io.StringIO(fetch(f'https://raw.githubusercontent.com/coinmetrics/data/master/csv/{code}.csv').decode()))
        crypto[code] = [(row['time'], row['PriceUSD']) for row in rows if row.get('PriceUSD') and '2010-07-18' <= row['time'] <= '2024-03-01' and float(row['PriceUSD']) > 0]
fiat = json.loads(args.fiat_input.read_text()) if args.fiat_input else json.loads(fetch(f'https://api.frankfurter.dev/v2/rates?base=USD&from=2010-07-01&to=2024-02-29&group=month&providers={providers}'))
fx = {}
for row in fiat:
    if row['date'] < '2024-03-01' and row['quote'] in allowed:
        fx.setdefault(row['quote'], {})[row['date']] = float(row['rate'])
fx['USD'] = {row['date']: 1.0 for row in fiat if row['date'] < '2024-03-01'}
crypto_monthly = {}
for code, rows in crypto.items():
    months = {}
    for day, price in sorted(rows):
        if day < '2024-03-01':
            months[day[:7]] = [day, float(price)]
    crypto_monthly[code.upper()] = list(months.values())
crypto_fx = {}
for code, rows in crypto.items():
    by_date = dict(rows)
    crypto_fx[code.upper()] = [[day, float(by_date[day])] for day in sorted(fx['USD']) if day in by_date]
def packed(rows):
    epoch = datetime.date(1970, 1, 1)
    return [[(datetime.date.fromisoformat(day)-epoch).days, value] for day,value in rows]
fawaz = {}
days = ['2024-03-02'] + [f'{year:04}-{month:02}-01' for year in range(2024, 2027) for month in range(1, 13) if '2024-04' <= f'{year:04}-{month:02}' <= '2026-09']
for day in days:
    if args.fawaz_input:
        table = json.loads((args.fawaz_input / f'{day}.json').read_text())
    else:
        table = json.loads(fetch(f'https://cdn.jsdelivr.net/npm/@fawazahmed0/currency-api@{day}/v1/currencies/usd.min.json'))
    if table['date'] != day:
        raise ValueError(f'Wrong publication date: {day}')
    for code, value in table['usd'].items():
        if code.upper() in allowed and float(value) > 0:
            fawaz.setdefault(code.upper(), []).append([day, float(value)])
archive = {'version': 1, 'provenance': {'acquired': '2026-10-15', 'cryptoSource': 'https://github.com/coinmetrics/data', 'cryptoMetric': 'PriceUSD', 'cryptoSampling': 'Last available positive daily observation per completed month; cryptoFX preserves observations matching FX monthly bucket dates.', 'fiatSource': 'https://api.frankfurter.dev/v2/rates', 'fiatSampling': 'group=month monthly reference buckets; cross-source joins are approximations.', 'licenses': ['CC-BY-NC-4.0.txt', 'CC-BY-4.0.txt', 'Fawaz-CC0-1.0.txt'], 'notice': 'DataSources.md', 'fawazSource': 'https://github.com/fawazahmed0/exchange-api', 'fawazSampling': 'First daily publication of each completed month March2024 through September2026, March2024 uses earliest available March2; USD quote table; CC0-1.0.', 'cryptoInputSHA256': hashlib.sha256(json.dumps(crypto, sort_keys=True).encode()).hexdigest(), 'fiatInputSHA256': hashlib.sha256(json.dumps(fiat, sort_keys=True).encode()).hexdigest()}, 'fawaz': {code: packed(rows) for code,rows in fawaz.items()}, 'providers': providers.split(','), 'crypto': {code: packed(rows) for code, rows in crypto_monthly.items()}, 'cryptoFX': {code: packed(rows) for code,rows in crypto_fx.items()}, 'fiat': {code: packed(sorted(rows.items())) for code,rows in fx.items()}}
args.output.parent.mkdir(parents=True, exist_ok=True)
args.output.write_text(json.dumps(archive, separators=(',', ':'), sort_keys=True)+'\n')
print(f'{args.output}: {args.output.stat().st_size} bytes')
