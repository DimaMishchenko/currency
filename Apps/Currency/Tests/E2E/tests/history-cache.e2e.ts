import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { readFileSync, unlinkSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { expect } from 'e2e';
import { test } from '../fixtures.js';

type History = {
  points: { date: number; value: number }[];
  fetchedAt: number;
  fiatHistoryPolicyVersion?: number;
  source: { provider: { fawaz?: object; frankfurter?: object }; observation: string };
};

for (const scenario of ['legacy daily source', 'wrong month'] as const) {
  test(`USD/AED month repairs a ${scenario} cache and persists the real history`, { tags: ['extended', 'live-providers'] }, async ({ start, app, device, screen, agent }) => {
    await start('ready-converter');
    const directory = execFileSync('xcrun', ['simctl', 'get_app_container', process.env.CURRENCY_E2E_UDID!, 'com.dimasike.currency', 'group.com.dimasike.currency.shared'], { encoding: 'utf8' }).trim();
    const openLive = () => device.openApp('com.dimasike.currency', {
      relaunch: true,
      launchArguments: ['-AppleLanguages', '(en)', '-AppleLocale', 'en_US'],
    });
    await device.closeApp();
    unlinkSync(join(directory, 'rates.json'));
    await openLive();
    await screen.getByTestId('converter.options').tap();
    await screen.getByTestId('converter.settings').tap();
    await screen.getByTestId('settings.rates').tap();
    await screen.getByRole('button', 'Refresh now', { exact: true }).tap();
    type Rates = { quotes: Record<string, { value: number; source: { provider: { fawaz?: object } } }> };
    const readRates = (): Rates => JSON.parse(readFileSync(join(directory, 'rates.json'), 'utf8'));
    for (let attempt = 0; attempt < 180; attempt++) {
      if (readRates().quotes.AED?.source.provider.fawaz && Number(readRates().quotes.USD?.value) !== 2) break;
      await new Promise(resolve => setTimeout(resolve, 500));
    }
    assert.ok(readRates().quotes.AED?.source.provider.fawaz, 'The actual FX feed must contain AED.');
    assert.notEqual(Number(readRates().quotes.USD!.value), 2);
    await agent.act('Close Settings and return to the converter. Leave the amount at 1.');
    await screen.getByTestId('converter.source').tap();
    await screen.getByRole('textbox', 'Search', { exact: true }).fill('AED');
    await screen.getByTestId('currency.picker.AED').tap();
    await expect(screen.getByRole('button', 'Edit amount in AED')).toHaveValue('1');
    await device.closeApp();

    const now = Date.now();
    const appleDate = (milliseconds: number) => milliseconds / 1000 - 978_307_200;
    const day = 86_400_000;
    const today = Math.floor(now / day) * day;
    const file = join(directory, 'history-v3-USD-AED-30.json');
    const seeded: History = {
      points: Array.from({ length: 31 }, (_, index) => ({
        date: appleDate(today - (30 - index) * day - (scenario === 'wrong month' ? 366 * day : 0)),
        value: scenario === 'wrong month' ? 777 : 3.6725,
      })),
      fetchedAt: appleDate(now),
      source: { provider: scenario === 'wrong month' ? { frankfurter: {} } : { fawaz: {} }, observation: 'dailyReference' },
    };
    writeFileSync(file, JSON.stringify(seeded));
    await openLive();
    await agent.act('Open Details & history for the US Dollar destination currency.');
    await expect(screen.getByTestId('currency.details.USD')).toBeVisible();
    await expect(screen.getByTestId('currency.details.rate')).toHaveAccessibleName('1 USD in AED');
    const month = screen.getByTestId('currency.details.historyRange').getByRole('tab', 'One month', { exact: true });
    await month.tap();
    await expect(month).toBeSelected();
    await app.screenshot(`usd-aed-${scenario.replaceAll(' ', '-')}-opened`);
    await expect(screen.getByTestId('currency.details.sourceDisclosure').filter({ hasText: /Frankfurter.*daily reference rates/i })).toBeVisible();
    const readHistory = (): History => JSON.parse(readFileSync(file, 'utf8'));
    for (let attempt = 0; attempt < 180 && readHistory().fetchedAt === seeded.fetchedAt; attempt++) {
      await new Promise(resolve => setTimeout(resolve, 500));
    }
    const saved = readHistory();
    assert.ok(saved.source.provider.frankfurter);
    assert.equal(saved.source.observation, 'dailyReference');
    assert.equal(saved.fiatHistoryPolicyVersion, 1);
    assert.ok(saved.fetchedAt >= seeded.fetchedAt);
    assert.ok(saved.points.length >= 15, 'The production daily provider must supply a full month of publication dates.');
    assert.ok(saved.points.every((point, index) => Number.isFinite(point.value) && point.value > 0 && point.value !== 777
      && point.date >= appleDate(today - 30 * day) && point.date <= saved.fetchedAt
      && (index === 0 || point.date > saved.points[index - 1]!.date)));
    assert.equal(new Set(saved.points.map(point => Math.floor((point.date + 978_307_200) / 86_400))).size, saved.points.length);
    await agent.waitFor('The USD monthly history chart in AED is loaded with a readable rate near 3.67, dates from the recent month, and Frankfurter daily reference source. It has no Loading history or History unavailable message and does not show 777.', { vision: 'only', timeout: 30_000 });
    await app.screenshot(`usd-aed-${scenario.replaceAll(' ', '-')}-repaired`);
    await openLive();
    await expect(screen.getByRole('button', 'Edit amount in AED')).toHaveValue('1');
    await agent.act('Open Details & history for the US Dollar destination currency.');
    await expect(month).toBeSelected();
    await expect(screen.getByTestId('currency.details.sourceDisclosure').filter({ hasText: /Frankfurter.*daily reference rates/i })).toBeVisible();
    assert.equal(readHistory().fetchedAt, saved.fetchedAt);
    assert.deepEqual(readHistory().points, saved.points);
    assert.deepEqual(readHistory().source, saved.source);
    assert.equal(readHistory().fiatHistoryPolicyVersion, 1);
    await app.screenshot(`usd-aed-${scenario.replaceAll(' ', '-')}-after-relaunch`);
  });
}
