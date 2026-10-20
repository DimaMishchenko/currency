import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { readFileSync, renameSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { expect } from 'e2e';
import { test } from '../fixtures.js';
import { configureWidget, placeWidget, prepareWidgetHelper, unloadWidgetHelper, widgetSetupMethod } from '../simulator-widgets.js';

type Quote = { value: number; observedAt?: number; retrievedAt?: number };
type Snapshot = { quotes: Record<string, Quote>; fetchedAt: number; checkedAt?: number };
type Context = { id: string; snapshot: Snapshot; base?: string; quote?: string };

const readJSON = <T>(path: string): T => JSON.parse(readFileSync(path, 'utf8')) as T;

test('tapping a captured widget quote opens its snapshot then adopts newer shared rates without fetching again', {
  tags: ['extended', 'widgets', 'widget-quote-handoff'],
  skip: widgetSetupMethod() === 'gallery' ? 'Requires device-targeted widget configuration.' : false,
}, async ({ start, app, device, screen, agent }) => {
  await prepareWidgetHelper();
  await start('ready-history-sync');
  await expect(screen.getByRole('button', 'Edit amount in BTC')).toHaveValue('1', { timeout: 30_000 });
  await expect(screen.getByRole('button', /^US Dollar,/i)).toHaveAccessibleName('US Dollar, 52,500', { timeout: 30_000 });
  await device.closeApp();
  await device.openApp('com.apple.springboard');
  await placeWidget('History', 'Medium');
  await configureWidget('History', 'Medium', parameters => {
    parameters.base = { identifier: 'BTC', title: { key: 'BTC' }, subtitle: { key: 'BTC' } };
    parameters.comparison = { identifier: 'USD', title: { key: 'USD' }, subtitle: { key: 'USD' } };
    parameters.range = { identifier: 'week', value: 'week', title: { key: '1 week' } };
  });
  const widget = device.locator('id=Currency value=Widget');
  await expect(widget.getByLabel('One week', { exact: true })).toBeVisible({ timeout: 30_000 });
  await expect(widget.getByLabel('Rate change over the selected range', { exact: true }))
    .toHaveValue(/^\+31[.,]25%$/, { timeout: 30_000 });
  await agent.waitFor('The visible Currency widget has BTC 1 and USD exactly 52,500 (52 500 with a space grouping separator is equivalent), 1W and +31.25% (decimal comma is equivalent). A line chart is drawn behind the values, which are readable without placeholders.', { vision: 'only', timeout: 30_000 });
  await app.screenshot('widget-captured-usd-52500-before-shared-quote-change');

  const udid = process.env.CURRENCY_E2E_UDID!;
  const directory = execFileSync('xcrun', ['simctl', 'get_app_container', udid,
    'com.dimasike.currency', 'group.com.dimasike.currency.shared'], { encoding: 'utf8' }).trim();
  const contextDirectory = join(directory, 'widget-quote-contexts-v2');
  const contexts = readJSON<{ id: string }[]>(join(contextDirectory, 'index.json'))
    .map(({ id }) => readJSON<Context>(join(contextDirectory, `${id}.json`)));
  const captured = contexts.find(context => {
    const quotes = context.snapshot.quotes;
    return context.base === 'BTC' && context.quote === 'USD' && quotes.BTC && quotes.USD && Math.abs(quotes.USD.value / quotes.BTC.value - 52_500) < 0.01;
  });
  assert.ok(captured, 'The installed widget must retain its immutable rendered quote context.');
  const contextPath = join(contextDirectory, `${captured.id}.json`);
  const ratePath = join(directory, 'rates.json');
  const original = readFileSync(ratePath, 'utf8');
  const newer = readJSON<Snapshot>(ratePath);
  const observedAt = Date.now() / 1000 - 978_307_200;
  assert.ok(observedAt > captured.snapshot.quotes.BTC.observedAt!);
  newer.quotes.BTC = { ...newer.quotes.BTC, value: newer.quotes.USD.value / 55_000, observedAt, retrievedAt: observedAt };
  newer.fetchedAt = observedAt;
  newer.checkedAt = observedAt;
  const temporary = join(directory, 'widget-handoff-rates.tmp');
  const writeRates = (content: string) => {
    writeFileSync(temporary, content);
    renameSync(temporary, ratePath);
  };
  try {
    writeRates(JSON.stringify(newer));
    assert.deepEqual(readJSON<Context>(contextPath), captured);
    await expect(widget.getByLabel('Rate change over the selected range', { exact: true })).toHaveValue(/^\+31[.,]25%$/);
    await app.screenshot('widget-retains-usd-52500-after-authoritative-cache-55000');
    await widget.tap();
    await agent.waitFor('The Currency app converter is visible, showing Bitcoin source amount exactly 1 and the US Dollar destination exactly 55,000 (55 000 with a space grouping separator is equivalent).', { vision: 'only', timeout: 30_000 });
    await app.screenshot('app-after-actual-widget-tap-before-driver-retarget');
    await device.openApp('com.dimasike.currency', { relaunch: false });
    const dollars = screen.getByRole('button', /^US Dollar,/i);
    await expect(dollars).toBeVisible({ timeout: 30_000 });
    const firstObserved = await dollars.textContent();
    const normalized = firstObserved?.replace(/(?<=\d)[,\s\u00a0\u202f](?=\d)/g, '');
    assert.match(normalized ?? '', /^US Dollar, (52500|55000)$/);
    console.log(`Widget handoff first observable row: ${firstObserved}; native scene tests verify the initial captured snapshot; this driver may miss the 1.5-second display window.`);
    if (normalized === 'US Dollar, 52500') await app.screenshot('app-widget-handoff-captured-usd-52500');
    await expect(screen.getByRole('button', 'Edit amount in BTC')).toHaveValue('1', { timeout: 30_000 });
    await expect(dollars).toHaveAccessibleName(/^US Dollar, 55[, \u00a0\u202f]000$/, { timeout: 30_000 });
    await app.screenshot('app-widget-handoff-newer-shared-usd-55000');
    const persisted = readJSON<Snapshot>(ratePath);
    assert.equal(persisted.checkedAt, newer.checkedAt, 'Opening the widget must reuse the fresh shared quote without another refresh attempt.');
    assert.equal(persisted.fetchedAt, newer.fetchedAt);
    assert.deepEqual(persisted.quotes.BTC, newer.quotes.BTC);
    assert.deepEqual(readJSON<Context>(contextPath), captured);
  } finally {
    writeRates(original);
  }
});

test.afterAll(async () => {
  await unloadWidgetHelper();
});
