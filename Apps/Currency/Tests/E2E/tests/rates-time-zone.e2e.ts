import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { expect } from 'e2e';
import { test } from '../fixtures.js';
import { sharedDirectory } from './history-cache.js';

const bundleId = 'com.dimasike.currency';
const zones = [
  { id: 'America/Los_Angeles', label: 'Pacific Time' },
  { id: 'Asia/Tokyo', label: 'Japan Standard Time' },
];
const swiftDate = (seconds: number) => new Date((seconds + 978_307_200) * 1000);
const escape = (text: string) => text.replace(/[.*+?^${}()|[\]\\]/g, '\\$&').replace(/\s+/g, '\\s+');
const timestampPattern = (seconds: number, zone: string, prefix = '') => {
  const date = new Intl.DateTimeFormat('en-US', {
    year: 'numeric', month: 'short', day: 'numeric', timeZone: zone,
  }).format(swiftDate(seconds));
  const time = new Intl.DateTimeFormat('en-US', {
    hour: 'numeric', minute: '2-digit', timeZone: zone,
  }).format(swiftDate(seconds));
  return new RegExp(`${escape(prefix)}${escape(date)}.*${escape(time)}`);
};

test('Rates uses one explicit local time zone while daily publication dates stay unchanged', {
  tags: ['core', 'rates-time-zone'],
}, async ({ start, device, screen, agent, app }) => {
  await start('ready-crypto');
  const directory = sharedDirectory();
  for (const zone of zones) {
    execFileSync('xcrun', [
      'simctl', 'launch', '--terminate-running-process', process.env.CURRENCY_E2E_UDID!, bundleId,
      '-AppleLanguages', '(en)', '-AppleLocale', 'en_US', '-CurrencyE2E',
    ], { env: { ...process.env, SIMCTL_CHILD_TZ: zone.id } });
    await device.openApp(bundleId);
    await screen.getByTestId('converter.options').tap();
    await screen.getByTestId('converter.settings').tap();
    await screen.getByTestId('settings.rates').tap();
    const rates = JSON.parse(readFileSync(join(directory, 'rates.json'), 'utf8')) as {
      fetchedAt: number;
      checkedAt: number;
      quotes: { BTC: { observedAt: number }; USD: { published: string } };
    };
    assert.ok(Number.isFinite(rates.fetchedAt));
    assert.ok(Number.isFinite(rates.checkedAt));
    assert.ok(Number.isFinite(rates.quotes.BTC.observedAt));
    await expect(screen.getByTestId('settings.rates.timeZone')).toHaveText(`Times: ${zone.label}`);
    await expect(screen.getByTestId('settings.rates.retrievedAt'))
      .toHaveText(timestampPattern(rates.fetchedAt, zone.id));
    await expect(screen.getByTestId('settings.rates.checkedAt'))
      .toHaveText(timestampPattern(rates.checkedAt, zone.id));
    await agent.act('Scroll Rates until the USD quote and its Published date are visible. Keep Rates open.');
    const publicationDate = new Intl.DateTimeFormat('en-US', {
      year: 'numeric', month: 'short', day: 'numeric', timeZone: 'UTC',
    }).format(new Date(`${rates.quotes.USD.published}T00:00:00Z`));
    await expect(screen.getByTestId('settings.rates.quote.USD'))
      .toHaveText(new RegExp(`Published ${escape(publicationDate)}`));
    await expect(screen.getByTestId('settings.rates.quote.USD'))
      .toHaveText(/Fawaz/);
    await expect(screen.getByTestId('settings.rates.quote.USD').filter({ hasText: /GMT/ })).toBeHidden();
    await agent.act('Scroll Rates until the BTC quote and its source information are visible. Keep Rates open.');
    const bitcoin = screen.getByTestId('settings.rates.quote.BTC');
    await expect(bitcoin).toHaveText(timestampPattern(rates.quotes.BTC.observedAt, zone.id, 'Observed '));
    await expect(bitcoin).toHaveText(/Coin Metrics.*minute reference prices/);
    await expect(bitcoin.filter({ hasText: /GMT/ })).toBeHidden();
    await app.screenshot(`rates-local-time-${zone.id.replaceAll('/', '-')}`);
    await screen.getByRole('button', 'Settings', { exact: true }).tap();
    await agent.act('Close Settings and return to the converter.');
  }
});
