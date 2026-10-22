import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { expect } from 'e2e';
import { test } from '../fixtures.js';
import { readHistory, sharedDirectory } from './history-cache.js';

const bundleId = 'com.dimasike.currency';
const zones = [
  { id: 'America/Los_Angeles', label: 'Pacific Time' },
  { id: 'Asia/Tokyo', label: 'Japan Standard Time' },
];
const swiftDate = (seconds: number) => new Date((seconds + 978_307_200) * 1000);
const escape = (text: string) => text.replace(/[.*+?^${}()|[\]\\]/g, '\\$&').replace(/\s+/g, '\\s+');
const dateText = (seconds: number, zone: string) => new Intl.DateTimeFormat('en-US', {
  year: 'numeric', month: 'short', day: 'numeric', timeZone: zone,
}).format(swiftDate(seconds));
const timestampFragment = (seconds: number, zone: string) => {
  const time = new Intl.DateTimeFormat('en-US', {
    hour: 'numeric', minute: '2-digit', timeZone: zone,
  }).format(swiftDate(seconds));
  return `${escape(dateText(seconds, zone))}.*${escape(time)}`;
};
const timestampPattern = (seconds: number, zone: string, prefix = '') =>
  new RegExp(`^${escape(prefix)}${timestampFragment(seconds, zone)}$`);

function launchInTimeZone(zone: string): void {
  execFileSync('xcrun', [
    'simctl', 'launch', '--terminate-running-process', process.env.CURRENCY_E2E_UDID!, bundleId,
    '-AppleLanguages', '(en)', '-AppleLocale', 'en_US', '-CurrencyE2E',
  ], { env: { ...process.env, SIMCTL_CHILD_TZ: zone } });
}

test('minute and hourly history use the local chart zone and local saved timestamps', {
  tags: ['core', 'history-time-zone'],
}, async ({ start, device, screen, agent, app }) => {
  await start('ready-crypto');
  const directory = sharedDirectory();
  for (const zone of zones) {
    launchInTimeZone(zone.id);
    await device.openApp(bundleId);
    for (const range of [
      { title: 'One day', key: 1, observation: 'minuteReference' },
      { title: 'One week', key: 7, observation: 'hourlyReference' },
    ]) {
      await screen.getByRole('button', /^Bitcoin,/i).tap();
      await screen.getByTestId('converter.history').tap();
      await expect(screen.getByTestId('currency.details.BTC')).toBeVisible();
      const ranges = screen.getByTestId('currency.details.historyRange');
      const period = ranges.getByRole('tab', range.title, { exact: true });
      await period.tap();
      await expect(period).toBeSelected();
      await expect(screen.getByTestId('currency.details.chartTimeZone'))
        .toHaveText(`Chart times: ${zone.label}`);
      const history = readHistory(join(directory, `history-v3-BTC-USD-${range.key}.json`));
      assert.equal(history.source.observation, range.observation);
      const rates = JSON.parse(readFileSync(join(directory, 'rates.json'), 'utf8')) as {
        fetchedAt: number; quotes: { BTC: { observedAt: number } };
      };
      const latest = rates.quotes.BTC.observedAt;
      assert.ok(Number.isFinite(latest));
      await expect(screen.getByText(timestampPattern(latest, zone.id))).toBeVisible();
      const source = screen.getByTestId('currency.details.sourceDisclosure')
        .filter({ hasText: /^(?:Coin Metrics|Fawaz)/ });
      await expect(source).toHaveAccessibleName(
        `Coin Metrics · ${range.key === 1 ? 'minute' : 'hourly'} reference prices`,
      );
      await expect(source).toHaveValue('Collapsed');
      await source.tap();
      await expect(source).toHaveValue('Expanded');
      await expect(screen.getByText(timestampPattern(
        Math.max(history.fetchedAt, rates.fetchedAt), zone.id, 'Saved ',
      ))).toBeVisible();
      await expect(screen.getByText(new RegExp(
        `^${timestampFragment(history.points[0]!.date, zone.id)} – ${timestampFragment(latest, zone.id)}$`,
      ))).toBeVisible();
      await expect(screen.getByText(/^Observed /)).toBeHidden();
      await expect(screen.getByText(/^Retrieved /)).toBeHidden();
      await expect(screen.getByText(/source sampling:/i)).toBeHidden();
      await agent.act('Scroll in Details until the crypto history explanation is visible. Keep the source details expanded.');
      await expect(screen.getByText(
        'Crypto history combines daily and monthly reference data with intraday prices when available. Converted prices may be approximate. Historical and current sources can differ.',
        { exact: true },
      )).toBeVisible();
      await expect(screen.getByText(/^Observed /)).toBeHidden();
      await expect(screen.getByText(/^Retrieved /)).toBeHidden();
      await expect(screen.getByText(/^Approximate conversion:/i)).toBeHidden();
      await app.screenshot(`history-${range.key}-${zone.id.replaceAll('/', '-')}`);
      await screen.getByTestId('currency.details.close').tap();
    }
  }
});

test('monthly reference dates retain their provider calendar day in west and east zones', {
  tags: ['core', 'history-time-zone'],
}, async ({ start, device, screen, agent, app }) => {
  await start('ready-converter');
  const directory = sharedDirectory();
  for (const zone of zones) {
    launchInTimeZone(zone.id);
    await device.openApp(bundleId);
    await screen.getByRole('button', 'Edit amount in EUR', { exact: true }).tap();
    await screen.getByTestId('converter.history').tap();
    await expect(screen.getByTestId('currency.details.EUR')).toBeVisible();
    const all = screen.getByTestId('currency.details.historyRange')
      .getByRole('tab', 'All available history', { exact: true });
    await all.tap();
    await expect(all).toBeSelected();
    await expect(screen.getByTestId('currency.details.chartTimeZone')).toBeHidden();
    const history = readHistory(join(directory, 'history-v3-EUR-USD-0.json'));
    assert.equal(history.source.observation, 'monthlyReference');
    const source = screen.getByTestId('currency.details.sourceDisclosure')
      .filter({ hasText: /^(?:Coin Metrics|Fawaz)/ });
    await expect(source).toHaveValue('Collapsed');
    await source.tap();
    await expect(source).toHaveValue('Expanded');
    const first = dateText(history.points[0]!.date, 'UTC');
    const last = dateText(history.points.at(-1)!.date, 'UTC');
    await expect(screen.getByText(`${first} – ${last}`, { exact: true })).toBeVisible();
    await expect(screen.getByText(last, { exact: true })).toBeVisible();
    await app.screenshot(`reference-calendar-dates-${zone.id.replaceAll('/', '-')}`);
    await screen.getByTestId('currency.details.close').tap();
  }
});
