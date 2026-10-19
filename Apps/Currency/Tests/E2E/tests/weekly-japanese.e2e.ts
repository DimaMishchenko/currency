import { expect } from 'e2e';
import { test } from '../fixtures.js';

test('Japanese weekly crypto history uses natural hourly provenance', {
  tags: ['extended', 'weekly-history'],
}, async ({ start, app, device, screen, agent }) => {
  await start('ready-crypto');
  await device.openApp('com.dimasike.currency', {
    relaunch: true,
    launchArguments: ['-AppleLanguages', '(ja)', '-AppleLocale', 'ja_JP', '-CurrencyE2E'],
  });
  await agent.act('Open Details & history for the Bitcoin destination currency. The app is in Japanese. Keep the Bitcoin details open.');
  await expect(screen.getByTestId('currency.details.BTC')).toBeVisible();
  const range = screen.getByTestId('currency.details.historyRange');
  await range.getByText('1か月', { exact: true }).tap();
  await agent.act('Choose the history menu item labelled 1週間 (one week). Keep Bitcoin details open.');
  await expect(range).toHaveValue('1週間');
  const source = screen.getByTestId('currency.details.sourceDisclosure');
  await expect(source).toBeVisible();
  await expect(source).toHaveAccessibleName('Coin Metrics · 1時間ごとの参考価格 · GMT');
  await app.screenshot('japanese-bitcoin-hourly-week-provenance');
});
