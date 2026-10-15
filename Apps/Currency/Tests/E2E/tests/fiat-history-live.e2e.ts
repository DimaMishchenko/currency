import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { existsSync, readFileSync, unlinkSync } from 'node:fs';
import { join } from 'node:path';
import { expect } from 'e2e';
import { test } from '../fixtures.js';

for (const quote of [{ code: 'USD' }, { code: 'AED' }]) {
test(`live ${quote.code}/EUR yearly history loads, All uses the archive and relaunch reuses the year`, { tags: ['extended', 'live-providers'] }, async ({ start, app, device, screen, agent }) => {
  await start('ready-converter');
  const udid = process.env.CURRENCY_E2E_UDID!;
  const directory = execFileSync('xcrun', ['simctl', 'get_app_container', udid, 'com.dimasike.currency', 'group.com.dimasike.currency.shared'], { encoding: 'utf8' }).trim();
  const ratesPath = join(directory, 'rates.json');
  const yearPath = join(directory, `history-v3-${quote.code}-EUR-365.json`);
  const allPath = join(directory, `history-v3-${quote.code}-EUR-0.json`);
  await device.closeApp();
  for (const file of [ratesPath, yearPath, allPath]) {
    if (existsSync(file)) unlinkSync(file);
    assert.equal(existsSync(file), false);
  }
  const started = Date.now();
  const milliseconds = (appleDate: number) => (appleDate + 978_307_200) * 1000;
  const openLive = () => device.openApp('com.dimasike.currency', {
    relaunch: true,
    launchArguments: ['-AppleLanguages', '(en)', '-AppleLocale', 'en_US'],
  });
  await openLive();
  await expect(screen.getByRole('button', 'Edit amount in EUR')).toHaveValue('1');
  await screen.getByTestId('converter.options').tap();
  await screen.getByTestId('converter.settings').tap();
  await screen.getByTestId('settings.rates').tap();
  await screen.getByRole('button', 'Refresh now', { exact: true }).tap();
  type Quote = { value: number; retrievedAt?: number; source: { provider: { coinMetrics?: object; fawaz?: object } } };
  type Snapshot = { quotes: Record<string, Quote> };
  let rates: Snapshot | undefined;
  for (let attempt = 0; attempt < 180; attempt++) {
    rates = existsSync(ratesPath) ? JSON.parse(readFileSync(ratesPath, 'utf8')) as Snapshot : undefined;
    if (rates?.quotes.USD?.source.provider.fawaz
      && Object.values(rates.quotes).filter(rate => rate.source.provider.coinMetrics && milliseconds(Number(rate.retrievedAt)) >= started).length === 22) break;
    await new Promise(resolve => setTimeout(resolve, 500));
  }
  assert.ok(rates?.quotes.USD?.source.provider.fawaz, 'Production refresh must persist the actual daily FX feed.');
  assert.notEqual(Number(rates.quotes.USD.value), 2, 'Live rates must replace the fixture FX table.');
  assert.equal(Object.values(rates.quotes).filter(rate => rate.source.provider.coinMetrics && milliseconds(Number(rate.retrievedAt)) >= started).length, 22);
  await agent.act(`Close Settings and return to the converter. ${quote.code === 'AED' ? 'Add AED (UAE Dirham) as a destination currency using the currency picker Search field. ' : ''}Open Details & history for the ${quote.code} destination currency.`);
  await expect(screen.getByTestId(`currency.details.${quote.code}`)).toBeVisible();
  const rate = screen.getByTestId('currency.details.rate');
  await expect(rate).toHaveAccessibleName(`1 ${quote.code} in EUR`);
  const ranges = screen.getByTestId('currency.details.historyRange');
  const year = ranges.getByRole('tab', 'One year', { exact: true });
  const all = ranges.getByRole('tab', 'All available history', { exact: true });
  const source = screen.getByTestId('currency.details.sourceDisclosure');
  type History = {
    points: { date: number; value: number }[];
    fetchedAt: number;
    source: { provider: { frankfurter?: object }; observation: string };
  };
  const readHistory = (file: string): History => JSON.parse(readFileSync(file, 'utf8'));
  const waitForHistory = async (file: string) => {
    for (let attempt = 0; attempt < 180 && !existsSync(file); attempt++) {
      await new Promise(resolve => setTimeout(resolve, 500));
    }
    assert.ok(existsSync(file), 'The requested history must finish and persist within 90 seconds.');
    return readHistory(file);
  };
  const assertPositiveOrdered = (history: History) => {
    assert.ok(history.points.every((point, index) => Number.isFinite(point.value) && point.value > 0
      && Number.isFinite(point.date) && (index === 0 || point.date > history.points[index - 1]!.date)));
  };
  const coldStarted = Date.now();
  await year.tap();
  await expect(year).toBeSelected();
  const savedYear = await waitForHistory(yearPath);
  const coldYearMs = Date.now() - coldStarted;
  assert.ok(savedYear.source.provider.frankfurter);
  assert.equal(savedYear.source.observation, 'dailyReference');
  assert.ok(savedYear.points.length > 200);
  assertPositiveOrdered(savedYear);
  assert.ok(milliseconds(savedYear.fetchedAt) >= started);
  const dayMs = 86_400_000;
  const first = milliseconds(savedYear.points[0]!.date);
  const last = milliseconds(savedYear.points.at(-1)!.date);
  assert.ok(first >= started - 366 * dayMs && first <= started - 357 * dayMs, 'The daily series must cover the beginning of the last year.');
  assert.ok(last >= started - 7 * dayMs && last <= Date.now(), 'The last daily observation must be recent.');
  await expect(source.filter({ hasText: /Frankfurter.*daily reference rates/i })).toBeVisible();
  await expect(rate).toHaveAccessibleName(`1 ${quote.code} in EUR`);
  await agent.waitFor(`The ${quote.code} 1Y chart in EUR is loaded with a visible historical trend and readable values. It does not show Loading history, History unavailable or placeholder dashes.`, { vision: 'only', timeout: 30_000 });
  await app.screenshot(`live-fiat-${quote.code.toLowerCase()}-eur-year-cold-loaded`);

  const allStarted = Date.now();
  await all.tap();
  await expect(all).toBeSelected();
  const savedAll = await waitForHistory(allPath);
  const allMs = Date.now() - allStarted;
  assert.equal(savedAll.source.observation, 'monthlyReference');
  assert.ok(savedAll.points.length > 150);
  assertPositiveOrdered(savedAll);
  assert.equal(new Date(milliseconds(savedAll.points[0]!.date)).getUTCFullYear(), 2010);
  assert.ok(milliseconds(savedAll.fetchedAt) >= started);
  await expect(source.filter({ hasText: /Frankfurter.*monthly reference rates/i })).toBeVisible();
  await expect(rate).toHaveAccessibleName(`1 ${quote.code} in EUR`);
  await agent.waitFor(`The ${quote.code} All history chart in EUR is loaded with a visible historical trend and readable values. It does not show Loading history, History unavailable or placeholder dashes.`, { vision: 'only', timeout: 30_000 });
  await app.screenshot(`live-fiat-${quote.code.toLowerCase()}-eur-all-bundled-archive`);

  await openLive();
  await expect(screen.getByTestId('converter.source')).toHaveAccessibleName(/Euro/i);
  await expect(screen.getByRole('button', 'Edit amount in EUR')).toHaveValue('1');
  await agent.act(`Open Details & history for the ${quote.code} destination currency.`);
  await expect(screen.getByTestId(`currency.details.${quote.code}`)).toBeVisible();
  await expect(rate).toHaveAccessibleName(`1 ${quote.code} in EUR`);
  const warmStarted = Date.now();
  await year.tap();
  await expect(year).toBeSelected();
  await expect(source.filter({ hasText: /Frankfurter.*daily reference rates/i })).toBeVisible();
  const warmYearMs = Date.now() - warmStarted;
  await agent.waitFor(`After relaunch, the ${quote.code} 1Y chart in EUR is loaded with a visible historical trend and readable values. It does not show Loading history, History unavailable or placeholder dashes.`, { vision: 'only', timeout: 30_000 });
  assert.equal(readHistory(yearPath).fetchedAt, savedYear.fetchedAt);
  assert.deepEqual(readHistory(yearPath).points, savedYear.points);
  await app.screenshot(`live-fiat-${quote.code.toLowerCase()}-eur-year-warm-reuse`);
  console.info(`${quote.code}/EUR history wall times (ms): cold 1Y=${coldYearMs}, bundled All=${allMs}, warm 1Y=${warmYearMs}`);
});

}
