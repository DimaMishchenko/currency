import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { existsSync, readFileSync, unlinkSync } from 'node:fs';
import { join } from 'node:path';
import { expect } from 'e2e';
import { test } from '../fixtures.js';
import { configureWidget, placeWidget, prepareWidgetHelper, unloadWidgetHelper, widgetSetupMethod } from '../simulator-widgets.js';

test('History widget fetches a complete live Coin Metrics day with the app terminated', { tags: ['extended', 'live-providers'] }, async ({ start, app, device, screen, agent }) => {
  if (widgetSetupMethod() !== 'private') {
    test.skip('Requires device-targeted widget configuration.');
    return;
  }
  await prepareWidgetHelper();
  await start('ready-crypto');
  await expect(screen.getByRole('button', /^Bitcoin,/i)).toHaveAccessibleName('Bitcoin, 0.00002');
  const udid = process.env.CURRENCY_E2E_UDID!;
  const directory = execFileSync('xcrun', ['simctl', 'get_app_container', udid, 'com.dimasike.currency', 'group.com.dimasike.currency.shared'], { encoding: 'utf8' }).trim();
  const cache = join(directory, 'history-v2-intradayEnhanced-BTC-USD-1.json');
  await device.closeApp();
  if (existsSync(cache)) unlinkSync(cache);
  assert.equal(existsSync(cache), false);
  const started = Date.now();
  await device.openApp('com.apple.springboard');
  await placeWidget('History', 'Medium');
  await configureWidget('History', 'Medium', parameters => {
    parameters.base = { identifier: 'BTC', title: { key: 'BTC' }, subtitle: { key: 'BTC' } };
    parameters.comparison = { identifier: 'USD', title: { key: 'USD' }, subtitle: { key: 'USD' } };
    parameters.range = { identifier: 'day', value: 'day', title: { key: '1 day' } };
  });
  const widget = device.locator('id=Currency value=Widget');
  await expect(widget).toBeVisible();
  for (let attempt = 0; attempt < 180 && !existsSync(cache); attempt++) {
    await new Promise(resolve => setTimeout(resolve, 500));
  }
  assert.ok(existsSync(cache), 'The independent widget must persist the fetched live chart.');
  const saved = JSON.parse(readFileSync(cache, 'utf8')) as {
    points: { date: number; value: number }[];
    fetchedAt: number;
    source: { provider: { coinMetrics?: object }; observation: string };
  };
  assert.ok(saved.source.provider.coinMetrics);
  assert.equal(saved.source.observation, 'minuteReference');
  assert.ok(saved.points.length >= 270);
  assert.ok(saved.points.at(-1)!.date - saved.points[0]!.date >= 85_500);
  assert.ok(saved.points.every(point => point.value > 0 && Number.isFinite(point.value)));
  assert.ok((saved.fetchedAt + 978_307_200) * 1000 >= started);
  await expect(widget.getByLabel('One day', { exact: true })).toBeVisible();
  await agent.waitFor('The installed History widget shows BTC and USD, a loaded 1D chart with a visible trend and readable values. It does not show History unavailable or missing-value dashes.', { vision: 'only', timeout: 30_000 });
  await app.screenshot('widget-live-coin-metrics-day-app-terminated');
});

test.afterAll(async () => {
  await unloadWidgetHelper();
});
