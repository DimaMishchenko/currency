import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { readFileSync, renameSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { expect } from 'e2e';
import { test } from '../fixtures.js';
import { configureWidget, placeWidget, prepareWidgetHelper, revealWidget, unloadWidgetHelper, widgetSetupMethod } from '../simulator-widgets.js';

type Quote = { value: number; observedAt?: number; retrievedAt?: number };
type Snapshot = { quotes: Record<string, Quote>; fetchedAt: number; checkedAt?: number };
type Context = { id: string; snapshot: Snapshot; base?: string; quote?: string; historyRange?: number };

const readJSON = <T>(path: string): T => JSON.parse(readFileSync(path, 'utf8')) as T;

test('tapping a captured widget quote opens its snapshot then adopts newer shared rates without fetching again', {
  tags: ['extended', 'widgets', 'widget-quote-handoff'],
  skip: widgetSetupMethod() === 'gallery' ? 'Requires device-targeted widget configuration.' : false,
}, async ({ start, app, device, screen, agent }) => {
  await prepareWidgetHelper();
  await start('ready-history-sync');
  await expect(screen.getByRole('button', 'Edit amount in BTC')).toHaveValue('1', { timeout: 30_000 });
  await expect(screen.getByRole('button', /^US Dollar,/i)).toHaveAccessibleName('US Dollar, 52,500.00', { timeout: 30_000 });
  await device.closeApp();
  await device.openApp('com.apple.springboard');
  await placeWidget('History', 'Medium');
  await configureWidget('History', 'Medium', parameters => {
    parameters.base = { identifier: 'BTC', title: { key: 'BTC' }, subtitle: { key: 'BTC' } };
    parameters.comparison = { identifier: 'USD', title: { key: 'USD' }, subtitle: { key: 'USD' } };
    parameters.range = { identifier: 'week', value: 'week', title: { key: '1 week' } };
  });
  await revealWidget('History', 'Medium');
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
    return context.base === 'BTC' && context.quote === 'USD' && context.historyRange === 7 && quotes.BTC && quotes.USD && Math.abs(quotes.USD.value / quotes.BTC.value - 52_500) < 0.01;
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
    await agent.waitFor('The Currency app Bitcoin details graph is visible, showing 1 BTC in USD and the One week (1W) period selected.', { vision: 'only', timeout: 30_000 });
    await device.openApp('com.dimasike.currency', { relaunch: false });
    await expect(screen.getByTestId('currency.details.BTC')).toBeVisible({ timeout: 30_000 });
    const rate = screen.getByTestId('currency.details.rate');
    await expect(rate).toHaveAccessibleName('1 BTC in USD');
    await expect(rate).toHaveValue('55,000 USD', { timeout: 30_000 });
    await expect(screen.getByTestId('currency.details.historyRange').getByRole('tab', 'One week', { exact: true })).toBeSelected();
    await app.screenshot('history-widget-opens-btc-usd-week-with-newer-shared-quote');
    await screen.getByTestId('currency.details.close').tap();
    await expect(screen.getByRole('button', 'Edit amount in BTC')).toHaveValue('1');
    await expect(screen.getByRole('button', /^US Dollar,/i)).toHaveAccessibleName('US Dollar, 55,000.00');
    const persisted = readJSON<Snapshot>(ratePath);
    assert.equal(persisted.checkedAt, newer.checkedAt, 'Opening the widget must reuse the fresh shared quote without another refresh attempt.');
    assert.equal(persisted.fetchedAt, newer.fetchedAt);
    assert.deepEqual(persisted.quotes.BTC, newer.quotes.BTC);
    assert.deepEqual(readJSON<Context>(contextPath), captured);
  } finally {
    writeRates(original);
  }
});

test('small History widget opens its day graph after a cold app launch', {
  tags: ['extended', 'widgets', 'widget-quote-handoff'],
  skip: widgetSetupMethod() === 'gallery' ? 'Requires device-targeted widget configuration.' : false,
}, async ({ start, app, device, screen, agent }) => {
  await prepareWidgetHelper();
  await start('ready-history-sync');
  await expect(screen.getByRole('button', 'Edit amount in BTC')).toHaveValue('1');
  await expect(screen.getByRole('button', /^US Dollar,/i)).toHaveAccessibleName('US Dollar, 52,500.00');
  await device.closeApp();
  await device.openApp('com.apple.springboard');
  await placeWidget('History', 'Small');
  await configureWidget('History', 'Small', parameters => {
    parameters.base = { identifier: 'BTC', title: { key: 'BTC' }, subtitle: { key: 'BTC' } };
    parameters.comparison = { identifier: 'USD', title: { key: 'USD' }, subtitle: { key: 'USD' } };
    parameters.range = { identifier: 'day', value: 'day', title: { key: '1 day' } };
  });
  await revealWidget('History', 'Small');
  const widget = device.locator('id=Currency value=Widget');
  await expect(widget.getByLabel('One day', { exact: true })).toBeVisible({ timeout: 30_000 });
  await widget.tap();
  await agent.waitFor('Bitcoin details is open in Currency with a history graph and One day (1D) selected.', { vision: 'only', timeout: 30_000 });
  await device.openApp('com.dimasike.currency', { relaunch: false });
  await expect(screen.getByTestId('currency.details.rate')).toHaveAccessibleName('1 BTC in USD');
  await expect(screen.getByTestId('currency.details.historyRange').getByRole('tab', 'One day', { exact: true })).toBeSelected();
  await app.screenshot('small-history-widget-opens-day-graph-cold');
  await screen.getByTestId('currency.details.close').tap();
  await expect(screen.getByRole('button', 'Edit amount in BTC')).toHaveValue('1');
});

test.afterAll(async () => {
  await unloadWidgetHelper();
});
