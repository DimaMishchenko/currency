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
  const week = screen.getByTestId('currency.details.historyRange').getByRole('tab', '1週間', { exact: true });
  await week.tap();
  await expect(week).toBeSelected();
  await expect(screen.getByTestId('currency.details.sourceDisclosure')
    .filter({ hasText: /Coin Metrics.*1時間ごとの参考価格/ })).toBeVisible();
  await app.screenshot('japanese-bitcoin-hourly-week-provenance');
});
