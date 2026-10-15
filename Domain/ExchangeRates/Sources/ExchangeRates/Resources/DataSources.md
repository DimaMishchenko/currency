# Data sources and licences

Currency uses third-party reference data for informational estimates. Providers do not endorse Currency or its calculations. These notices apply to data displayed in the app, widgets and Apple Watch, retained in caches, and distributed as bundled history. The repository’s MIT licence applies to project code, not third-party data.

## Coin Metrics

Crypto reference data: **Coin Metrics, Inc.**, [Community API](https://docs.coinmetrics.io/api-reference) and [Community data archives](https://github.com/coinmetrics/data), licensed under [Creative Commons Attribution–NonCommercial 4.0 International](https://creativecommons.org/licenses/by-nc/4.0/) ([full text](https://github.com/DimaMishchenko/currency/blob/main/LICENSES/CC-BY-NC-4.0.txt)). The archive’s [source licence notice](https://github.com/coinmetrics/data/blob/master/LICENSE) applies to its data. The API specification’s separate software licence is not a licence for commercial use of Community data.

Coin Metrics publishes its data without warranty; use is at your own risk. See the licence’s disclaimer of warranties and limitation of liability. Currency selects asset/date subsets, reformats values into app resources, samples historical observations, calculates cross-rates and chart changes, and may convert USD crypto prices using a separately dated fiat reference rate. These changes are made by Currency / Dmytro Mishchenko. Calculated prices and charts are Currency’s reference estimates. Original asset, metric, date and source metadata identify the underlying data; gaps are not evidence of a zero price. The bundled `history-monthly-v1.json` records its source, acquisition date, input hashes and sampling metadata. Pre-March-2024 crypto history selects each month’s last available Coin Metrics daily observation, with additional dated samples used to join the available monthly fiat reference observations. These monthly fiat references do not establish the exact FX rate at every crypto observation time.

Recipients receive the licensor’s offer to reuse the licensed data under CC BY-NC 4.0, including its noncommercial, attribution and modification-notice conditions. Currency’s contributions to adapted Coin Metrics datasets are offered under the same licence. Preserve supplied source, copyright, licence and warranty notices and identify further modifications. No app EULA or repository MIT licence restricts these licensed rights. Distributors must not apply additional legal restrictions or effective technological measures to this material that restrict recipients’ licensed rights. Packaging and distribution must preserve these rights; a separate source download does not by itself resolve restrictions applied to another distributed copy.

The source archives are publicly downloadable at the link above. Bundled data files and manifests are available with this repository. CC BY-NC 4.0 does not promise future data access, unchanged coverage, or a particular rolling intraday history window. Currency remains free and noncommercial without advertising; commercial reuse of the licensed data requires a separate permission or another applicable legal basis.

## Fawaz Exchange API

Daily rates, fallback history and bundled monthly references: [Fawaz Ahmed’s Exchange API](https://github.com/fawazahmed0/exchange-api), distributed through its documented CDN and Cloudflare endpoints. Its repository declares [CC0 1.0 Universal](https://github.com/fawazahmed0/exchange-api/blob/main/LICENSE) ([full text](https://github.com/DimaMishchenko/currency/blob/main/LICENSES/Fawaz-CC0-1.0.txt)). The bundled completed-month history samples March 2, 2024 (the archive boundary), then the first day of each completed month from April 2024. The incomplete current month is omitted. Later missing completed months may be fetched as month-end references. Currency selects dates/assets and calculates cross-rates and reference conversions. CC0 applies only to rights the affirmer can waive or license; it does not warrant third-party source rights or grant trademark rights.

## Frankfurter and original fiat sources

[Frankfurter](https://frankfurter.dev/) aggregates institutional reference rates. Its [provider and licensing inventory](https://frankfurter.dev/license/) identifies the original sources; its software licence does not replace their data terms. Currency uses an explicit selection of provider IDs. A displayed calculation or blend is produced by Currency, rather than an official quote from any contributing institution. Dates refer to the source observations; monthly samples are reference observations, not market closes. Bundled metadata records the selected source IDs. The pre-March-2024 fiat archive requests USD-based monthly reference buckets from July 2010 through February 2024; actual coverage differs by currency. GGP, IMP and JEP use an explicit GBP-parity assumption. These are Currency’s reference calculations.

The following notices accompany data from these sources, where present:

- **Banco Central de la República Argentina (BCRA)**: source [BCRA](https://www.bcra.gob.ar/); [informational reuse terms](https://www.bcra.gob.ar/aviso-legal/). Currency’s noncommercial estimates preserve the source context; conversions, selection and formatting are Currency’s work.
- **Bank for International Settlements (BIS)**: underlying statistics sourced from [BIS Data Portal](https://data.bis.org/), under its [statistical-data terms](https://data.bis.org/help/legal). Currency’s calculations are identified as such; no additional charge is made for the included statistics.
- **Bank of Canada**: underlying data sourced from [Bank of Canada](https://www.bankofcanada.ca/), under its [terms](https://www.bankofcanada.ca/terms/). Currency selects/reformats reference observations and calculates cross-rates; the Bank of Canada does not endorse these changes.
- **Bank of Jamaica**: source [Bank of Jamaica](https://boj.org.jm/), used for noncommercial general reference with source acknowledgment under its [notice](https://boj.org.jm/disclaimer/).
- **European Central Bank (ECB)**: underlying reference rates sourced from [ECB](https://www.ecb.europa.eu/stats/policy_and_exchange_rates/euro_reference_exchange_rates/html/index.en.html), under its [copyright and reuse terms](https://www.ecb.europa.eu/services/using-our-site/disclaimer/html/index.en.html). Selection, reformatting, cross-rates and converted prices are modifications by Currency.
- **HM Revenue & Customs**: [monthly customs exchange rates](https://www.trade-tariff.service.gov.uk/exchange_rates/monthly). Contains public sector information licensed under the [Open Government Licence v3.0](https://www.nationalarchives.gov.uk/doc/open-government-licence/version/3/). Currency’s calculated reference conversions are not HMRC customs assessments.
- **European Commission / InforEuro**: underlying data from [InforEuro](https://commission.europa.eu/funding-tenders/procedures-guidelines-tenders/information-contractors-and-beneficiaries/exchange-rate-inforeuro_en), © European Union, under [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/) ([full text](https://github.com/DimaMishchenko/currency/blob/main/LICENSES/CC-BY-4.0.txt)) as described in the [Commission legal notice](https://commission.europa.eu/legal-notice_en), except separately identified third-party material. Currency selects/reformats observations and calculates reference cross-rates. Retain the source/licence/warranty notices and identify changes; no additional legal or effective technological restriction may obstruct the licensed rights. See the licence for its warranty disclaimer.
- **Japan Customs**: underlying [customs exchange rates](https://www.customs.go.jp/english/kawase/index_e.htm); [copyright notice](https://www.customs.go.jp/copyright_e.htm) and [Public Data Licence 1.0](https://www.digital.go.jp/en/resources/open_data/public_data_license_v1.0). Numerical data are freely usable as described there. Selection, formatting and calculated estimates are by Currency / Dmytro Mishchenko; they are not unedited government publications.
- **Sveriges riksbank**: original statistics and their observation dates are identified through the source metadata and [original series](https://www.riksbank.se/en-gb/statistics/search-interest--exchange-rates/). See [open-data reuse terms](https://www.riksbank.se/sv/om-riksbanken/om-webbplatsen/oppna-data--information-tillganglig-for-vidareutnyttjande/). Processed/blended statistics and cross-rates are Currency’s calculations; Sveriges riksbank is credited only for the underlying original statistics, not as the source of those processed results.
- **U.S. Department of the Treasury**: underlying [Treasury reporting rates](https://fiscaldata.treasury.gov/datasets/treasury-reporting-rates-exchange/treasury-reporting-rates-of-exchange), available for copying, adaptation and redistribution under its [data authorization](https://fiscaldata.treasury.gov/api-documentation/#license-and-authorization). Currency’s calculations do not imply Treasury endorsement.

### Source directory

The selected source directory below links each original dataset. Source-specific notices and third-party exclusions continue to apply. Inclusion here is attribution and provenance, not a claim that every source uses the same licence. No linked licence in an aggregator’s inventory is not a public-domain dedication.

| ID | Original institution and dataset |
| --- | --- |
| AMCM | [Autoridade Monetária de Macau](https://www.amcm.gov.mo/en/financial-information/interbank-midpoint) |
| BAM | [Bank Al-Maghrib](https://apihelpdesk.centralbankofmorocco.ma/apis) |
| BANREP | [Banco de la República](https://www.datos.gov.co/Econom-a-y-Finanzas/Tasa-de-Cambio-Representativa-del-Mercado-TRM/32sa-8pi3/about_data) |
| BCB | [Banco Central do Brasil](https://olinda.bcb.gov.br/olinda/servico/PTAX/versao/v1/odata/) |
| BCBO | [Banco Central de Bolivia](https://www.bcb.gob.bo/?q=cotizaciones_tc) |
| BCC | [Banco Central de Cuba](https://api.bc.gob.cu/v1/tasas-de-cambio/activas) |
| BCCH | [Banco Central de Chile](https://si3.bcentral.cl/Siete/es/Siete/API) |
| BCP | [Banco Central del Paraguay](https://www.bcp.gov.py/webapps/web/cotizacion/monedas) |
| BCRA | [Banco Central de la República Argentina](https://www.bcra.gob.ar/en/monetary-and-financial-statistics/exchange-statistics/) |
| BCT | [Banque Centrale de Tunisie](https://www.bct.gov.tn/bct/siteprod/cours_archive.jsp) |
| BDI | [Banca d'Italia](https://tassidicambio.bancaditalia.it/) |
| BDP | [Banco de Portugal](https://bpstat.bportugal.pt/) |
| BI | [Bank Indonesia](https://www.bi.go.id/en/statistik/informasi-kurs/transaksi-bi/default.aspx) |
| BIS | [Bank for International Settlements](https://data.bis.org/topics/XRU) |
| BNA | [Banco Nacional de Angola](https://www.bna.ao/Conteudos/Mercados/listaTaxasCambioReferencia.aspx) |
| BNM | [Bank Negara Malaysia](https://www.bnm.gov.my/exchange-rates) |
| BNR | [Banca Națională a României](https://www.bnr.ro/en/561-exchange-rates) |
| BOA | [Bank of Algeria](https://www.bank-of-algeria.dz/donnees-historiques/) |
| BOC | [Bank of Canada](https://www.bankofcanada.ca/rates/exchange/daily-exchange-rates/) |
| BOJA | [Bank of Jamaica](https://boj.org.jm/market/foreign-exchange/counter-rates/) |
| BOM | [Bank of Mongolia](https://www.mongolbank.mn/en/currency-rate-movement) |
| BOT | [Bank of Thailand](https://www.bot.or.th/en/statistics/exchange-rate.html) |
| BOTA | [Bank of Tanzania](https://www.bot.go.tz/exchangerate/excrates) |
| BOZ | [Bank of Zambia](https://www.boz.zm/average-exchange-rates) |
| BRB | [Banque de la Republique du Burundi](https://www.brb.bi/en/affichagetoustauxchange) |
| CBA | [Central Bank of Armenia](https://www.cba.am/en/SitePage/ExchangeArchive.aspx) |
| CBAR | [Central Bank of the Republic of Azerbaijan](https://www.cbar.az/currency/rates) |
| CBC | [Central Bank of the Republic of China (Taiwan)](https://www.cbc.gov.tw/en/lp-4237-2.html) |
| CBG | [Central Bank of The Gambia](https://www.cbg.gm/indicative-exchange-rates-latest) |
| CBI | [Central Bank of Iraq](https://cbi.iq/page/144) |
| CBK | [Central Bank of Kenya](https://www.centralbank.go.ke/forex/) |
| CBLLR | [Central Bank of Liberia](https://www.cbl.org.lr/research/buying-selling-rates) |
| CBM | [Central Bank of Myanmar](https://forex.cbm.gov.mm/api/latest) |
| CBS | [Central Bank of Samoa](https://cbs.gov.ws/daily-exchange-rates) |
| CBSL | [Central Bank of Sri Lanka](https://www.cbsl.gov.lk/en/rates-and-indicators/exchange-rates/daily-indicative-exchange-rates) |
| CBU | [Central Bank of Uzbekistan](https://cbu.uz/en/arkhiv-kursov-valyut/json/) |
| DAB | [Da Afghanistan Bank](https://www.dab.gov.af/exchange-rates) |
| DNB | [Danmarks Nationalbank](https://www.nationalbanken.dk/en/what-we-do/stable-prices-monetary-policy-and-the-danish-economy/exchange-rates) |
| ECB | [European Central Bank](https://www.ecb.europa.eu/stats/policy_and_exchange_rates/euro_reference_exchange_rates/html/index.en.html) |
| HMRC | [HM Revenue & Customs](https://www.trade-tariff.service.gov.uk/exchange_rates/monthly) |
| HNB | [Hrvatska Narodna Banka](https://api.hnb.hr/) |
| INFOREURO | [European Commission](https://commission.europa.eu/funding-and-tenders/procedures-guidelines-tenders/information-contractors-and-beneficiaries/exchange-rate-inforeuro_en) |
| JPC | [Japan Customs](https://www.customs.go.jp/tetsuzuki/kawase/) |
| LB | [Lietuvos Bankas](https://www.lb.lt/webservices/FxRates/FxRates.asmx) |
| MAS | [Monetary Authority of Singapore](https://eservices.mas.gov.sg/statistics/msb/ExchangeRates.aspx) |
| MMA | [Maldives Monetary Authority](https://www.mma.gov.mv/JSON/referencerates.json) |
| MNB | [Magyar Nemzeti Bank](https://www.mnb.hu/en/monetary-policy/the-mpc/exchange-rates) |
| NBC | [National Bank of Cambodia](https://www.nbc.gov.kh/english/economic_research/exchange_rate.php) |
| NBE | [National Bank of Ethiopia](https://nbe.gov.et/exchange-rate/) |
| NBG | [National Bank of Georgia](https://nbg.gov.ge/en/monetary-policy/currency) |
| NBK | [National Bank of Kazakhstan](https://nationalbank.kz/en/exchangerates/ezhednevnye-oficialnye-rynochnye-kursy-valyut) |
| NBKR | [National Bank of the Kyrgyz Republic](https://www.nbkr.kg/index1.jsp?item=1562&lang=ENG) |
| NBM | [National Bank of Moldova](https://www.bnm.md/en/official_exchange_rates) |
| NBP | [Narodowy Bank Polski](https://nbp.pl/en/statistic-and-financial-reporting/rates/) |
| NBRB | [Natsyyanalny Bank Respubliki Belarus](https://www.nbrb.by/engl/statistics/rates/ratesdaily.asp) |
| NBRM | [Narodna Banka na Republika Severna Makedonija](https://www.nbrm.mk) |
| NBT | [National Bank of Tajikistan](https://www.nbt.tj/en/kurs/) |
| NRB | [Nepal Rastra Bank](https://www.nrb.org.np/api/forex/v1/rates) |
| NRBT | [National Reserve Bank of Tonga](https://www.reservebank.to/index.php/financial-system/financial-markets/exchange-rates) |
| RB | [Sveriges Riksbank](https://www.riksbank.se/en-gb/statistics/) |
| RBF | [Reserve Bank of Fiji](https://www.rbf.gov.fj/statistics/economic-and-financial-statistics/) |
| RBM | [Reserve Bank of Malawi](https://www.rbm.mw/Statistics/MajorRates) |
| RBV | [Reserve Bank of Vanuatu](https://www.rbv.gov.vu/index.php/en/exchange-rates) |
| SARB | [South African Reserve Bank](https://custom.resbank.co.za/SarbWebApi/WebIndicators/HistoricalExchangeRatesDaily) |
| SBI | [Seðlabanki Íslands](https://www.sedlabanki.is/hagtolur/opinbert-gengi/) |
| UST | [U.S. Department of the Treasury](https://fiscaldata.treasury.gov/datasets/treasury-reporting-rates-exchange/treasury-reporting-rates-of-exchange) |
