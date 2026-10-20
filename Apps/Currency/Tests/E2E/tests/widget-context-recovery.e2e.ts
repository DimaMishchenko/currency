import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { execFileSync } from 'node:child_process';
import { readFileSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { expect } from 'e2e';
import { test } from '../fixtures.js';
import { tapCalculatorControl } from '../widget-fixtures.js';
import { placeWidget, prepareWidgetHelper, unloadWidgetHelper, widgetSetupMethod } from '../simulator-widgets.js';

test('widgets load and calculator remains interactive with a full legacy quote-context cache', {
  tags: ['extended', 'widgets', 'widget-context-recovery'],
  skip: widgetSetupMethod() === 'gallery' ? 'Requires device-targeted widget placement.' : false,
}, async ({ start, app, device, screen, agent }) => {
  await prepareWidgetHelper();
  await start('ready-converter');
  await expect(screen.getByRole('button', 'Edit amount in EUR')).toHaveValue('1');
  const directory = execFileSync('xcrun', ['simctl', 'get_app_container', process.env.CURRENCY_E2E_UDID!,
    'com.dimasike.currency', 'group.com.dimasike.currency.shared'], { encoding: 'utf8' }).trim();
  const snapshot = JSON.parse(readFileSync(join(directory, 'rates.json'), 'utf8'));
  const catalog = readFileSync('../../../../Domain/ExchangeRates/Sources/ExchangeRates/CurrencyCode.swift', 'utf8');
  const codes = [...catalog.matchAll(/case \w+ = "([A-Z0-9]+)"/g)].map(match => match[1]);
  assert.ok(codes.length >= 180, 'Use a full production-sized currency catalogue.');
  const quotes = Object.fromEntries(codes.map(code => [code, snapshot.quotes[code] ?? snapshot.quotes.USD]));
  const now = Date.now() / 1000 - 978_307_200;
  const legacy = Array.from({ length: 128 }, (_, index) => ({
    id: randomUUID().toUpperCase(), digest: index.toString(16).padStart(64, '0'), createdAt: now - index,
    snapshot: { ...snapshot, quotes, dailyQuotes: quotes, fiatQuotes: quotes, supplementalQuotes: quotes },
  }));
  const path = join(directory, 'widget-quote-contexts.json');
  const original = JSON.stringify(legacy);
  writeFileSync(path, original);
  console.log(`Legacy widget cache fixture: ${codes.length} currencies, ${Buffer.byteLength(original)} bytes.`);
  await device.closeApp();
  await device.openApp('com.apple.springboard');
  await placeWidget('Currency Calculator', 'Medium');
  const calculator = device.locator('id=Currency value=Widget');
  const dollars = calculator.getByRole('button', /^US Dollar, USD/i);
  await expect(dollars).toHaveValue('2', { timeout: 30_000 });
  await tapCalculatorControl(calculator, 'USD');
  await tapCalculatorControl(calculator, 'Clear');
  await tapCalculatorControl(calculator, '4');
  await tapCalculatorControl(calculator, '2');
  await expect(dollars).toHaveValue('42', { timeout: 30_000 });
  await agent.assert('The Calculator widget has loaded currency values and keypad labels, with USD exactly 42 and EUR exactly 21. There are no redacted placeholders.', { vision: 'only' });
  await app.screenshot('calculator-loaded-and-interactive-with-full-legacy-cache');
  await placeWidget('Pocket Rate', 'Small');
  await agent.waitFor('The Pocket Rate widget shows EUR 5 and approximately USD 10, with readable values and no redacted placeholders.', { vision: 'only', timeout: 30_000 });
  await app.screenshot('pocket-rate-loaded-with-full-legacy-cache');
  await placeWidget('Currency Calculator', 'Medium');
  await expect(dollars).toHaveValue('42', { timeout: 30_000 });
  assert.equal(readFileSync(path, 'utf8'), original, 'Timeline rendering must leave the legacy aggregate untouched.');
});

test.afterAll(async () => {
  await unloadWidgetHelper();
});
