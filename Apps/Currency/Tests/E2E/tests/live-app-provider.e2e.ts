import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { existsSync, readFileSync, unlinkSync } from 'node:fs';
import { join } from 'node:path';
import { expect } from 'e2e';
import { test } from '../fixtures.js';

for (const quote of ['USD', 'EUR'] as const) {
test(`real provider refresh and ${quote} phone history survive a live-network relaunch`, { tags: ['extended', 'live-providers'] }, async ({ start, app, device, screen, agent }) => {
  await start('ready-crypto');
  if (quote === 'EUR') {
    await agent.act('Open the source currency picker. Search EUR, select Euro, and return to the converter without editing the amount.');
  }
  const udid = process.env.CURRENCY_E2E_UDID!;
  const directory = execFileSync('xcrun', ['simctl', 'get_app_container', udid, 'com.dimasike.currency', 'group.com.dimasike.currency.shared'], { encoding: 'utf8' }).trim();
  const ratesPath = join(directory, 'rates.json');
  const dayPath = join(directory, `history-v3-BTC-${quote}-1.json`);
  const allPath = join(directory, `history-v3-BTC-${quote}-0.json`);
  await device.closeApp();
  for (const file of [ratesPath, dayPath, allPath]) {
    if (existsSync(file)) unlinkSync(file);
    assert.equal(existsSync(file), false);
  }
  const started = Date.now();
  const openLive = () => device.openApp('com.dimasike.currency', {
    relaunch: true,
    launchArguments: ['-AppleLanguages', '(en)', '-AppleLocale', 'en_US'],
  });
  await openLive();
  await expect(screen.getByRole('button', `Edit amount in ${quote}`)).toHaveValue('1');
  await screen.getByTestId('converter.options').tap();
  await screen.getByTestId('converter.settings').tap();
  await screen.getByTestId('settings.rates').tap();
  await screen.getByRole('button', 'Refresh now', { exact: true }).tap();
  type Quote = { value: number; retrievedAt?: number; source: { provider: { coinMetrics?: object; fawaz?: object }; conversion?: { value: number } } };
  type Snapshot = { quotes: Record<string, Quote>; fetchedAt: number };
  const readRates = (): Snapshot | undefined => existsSync(ratesPath) ? JSON.parse(readFileSync(ratesPath, 'utf8')) : undefined;
  let rates: Snapshot | undefined;
  for (let attempt = 0; attempt < 180; attempt++) {
    rates = readRates();
    if (rates && Object.values(rates.quotes).filter(rate => rate.source.provider.coinMetrics && (Number(rate.retrievedAt) + 978_307_200) * 1000 >= started).length === 22) break;
    await new Promise(resolve => setTimeout(resolve, 500));
  }
  assert.ok(rates);
  assert.equal(Object.values(rates.quotes).filter(rate => rate.source.provider.coinMetrics && (Number(rate.retrievedAt) + 978_307_200) * 1000 >= started).length, 22);
  assert.ok(rates.quotes.USD?.source.provider.fawaz);
  assert.notEqual(Number(rates.quotes.USD?.value), 2, 'The actual dated feed must replace the fixture FX table.');
  assert.equal(Number(rates.quotes.BTC?.source.conversion?.value), Number(rates.quotes.USD?.value));
  assert.ok(Object.values(rates.quotes).every(rate => Number.isFinite(Number(rate.value)) && Number(rate.value) > 0));
  await agent.act('Scroll Rates until the BTC quote and its source information are visible. Keep Rates open.');
  await expect(screen.getByText(/Coin Metrics.*minute reference prices/i).first()).toBeVisible();
  if (quote === 'USD') {
    await expect(screen.getByText(/^Approximate conversion:/i)).toBeHidden();
  } else {
    await expect(screen.getByText(/^Approximate conversion:/i).first()).toBeVisible();
  }
  await app.screenshot(`live-phone-${quote.toLowerCase()}-refreshed-coin-metrics-rates`);
  await agent.act('Close Settings and return to the converter. Long-press the Bitcoin destination currency row, then choose Details & history in its context menu.');
  await expect(screen.getByTestId('currency.details.BTC')).toBeVisible();
  await expect(screen.getByTestId('currency.details.rate')).toHaveAccessibleName(`1 BTC in ${quote}`);
  const ranges = screen.getByTestId('currency.details.historyRange');
  const day = ranges.getByRole('tab', 'One day', { exact: true });
  await day.tap();
  await expect(day).toBeSelected();
  const source = screen.getByTestId('currency.details.sourceDisclosure');
  await expect(source.filter({ hasText: /Coin Metrics.*minute reference prices/i })).toBeVisible();
  type History = { points: { date: number; value: number }[]; fetchedAt: number; source: { provider: { coinMetrics?: object }; observation: string; conversion?: { base: string; quote: string; value: number; published: string } } };
  const readHistory = (file: string): History => JSON.parse(readFileSync(file, 'utf8'));
  for (let attempt = 0; attempt < 180 && !existsSync(dayPath); attempt++) {
    await new Promise(resolve => setTimeout(resolve, 500));
  }
  assert.ok(existsSync(dayPath), 'The phone must finish its live history fetch and persist a complete chart.');
  const savedDay = readHistory(dayPath);
  assert.ok(savedDay.source.provider.coinMetrics);
  assert.equal(savedDay.source.observation, 'minuteReference');
  if (quote === 'EUR') {
    assert.equal(savedDay.source.conversion?.base, 'USD');
    assert.equal(savedDay.source.conversion?.quote, 'EUR');
    assert.ok(Number(savedDay.source.conversion?.value) > 0);
    assert.match(savedDay.source.conversion!.published, /^\d{4}-\d{2}-\d{2}$/);
  } else {
    assert.equal(savedDay.source.conversion, undefined);
  }
  assert.ok((savedDay.fetchedAt + 978_307_200) * 1000 >= started);
  assert.ok(savedDay.points.length >= 270);
  assert.ok(savedDay.points.at(-1)!.date - savedDay.points[0]!.date >= 85_500);
  assert.ok(savedDay.points.every(point => point.value > 0 && Number.isFinite(point.value)));
  await agent.waitFor(`The Bitcoin ${quote} 1D chart is loaded with a visible price trend and values, with no History unavailable or placeholder dashes.`, { vision: 'only', timeout: 30_000 });
  await app.screenshot(`live-phone-bitcoin-${quote.toLowerCase()}-complete-day`);
  const all = ranges.getByRole('tab', 'All available history', { exact: true });
  await all.tap();
  await expect(all).toBeSelected();
  await expect(source.filter({ hasText: /Fawaz.*Coin Metrics.*monthly reference/i })).toBeVisible();
  const savedAll = readHistory(allPath);
  assert.ok(savedAll.points.length >= 190);
  assert.equal(new Date((savedAll.points[0]!.date + 978_307_200) * 1000).getUTCFullYear(), 2010);
  assert.ok(savedAll.points.every(point => point.value > 0 && Number.isFinite(point.value)));
  await app.screenshot(`live-phone-bitcoin-${quote.toLowerCase()}-all-archive-from-2010`);
  await openLive();
  await expect(screen.getByRole('button', `Edit amount in ${quote}`)).toHaveValue('1');
  await expect(screen.getByRole('button', /^Bitcoin,/i)).toBeVisible();
  await agent.act('Long-press the Bitcoin destination currency row, then choose Details & history in its context menu.');
  await expect(screen.getByTestId('currency.details.BTC')).toBeVisible();
  await expect(screen.getByTestId('currency.details.rate')).toHaveAccessibleName(`1 BTC in ${quote}`);
  await day.tap();
  await expect(day).toBeSelected();
  await expect(source.filter({ hasText: /Coin Metrics.*minute reference prices/i })).toBeVisible();
  await agent.waitFor(`After relaunch, the Bitcoin ${quote} 1D chart is loaded with a visible price trend and readable values. It does not show Loading history, History unavailable or placeholder dashes.`, { vision: 'only', timeout: 30_000 });
  assert.equal(readHistory(dayPath).fetchedAt, savedDay.fetchedAt);
  assert.deepEqual(readHistory(dayPath).points, savedDay.points);
  await app.screenshot(`live-phone-${quote.toLowerCase()}-relaunch-preserves-day-chart`);
});

}
