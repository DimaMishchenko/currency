import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { readFileSync, renameSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { expect } from 'e2e';
import { test, tapCalculatorControl } from '../widget-fixtures.js';
import { revealWidget, unloadWidgetHelper, widgetSetupMethod } from '../simulator-widgets.js';

test('calculator keeps its entered amount when reloaded with a new exchange rate', {
  tags: ['extended', 'widgets'],
  skip: widgetSetupMethod() === 'gallery' ? 'Requires device-targeted widget setup and reveal.' : false,
}, async ({ calculator, app, agent, screen, device }) => {
  const dollars = calculator.getByRole('button', /^US Dollar, USD/i);
  await tapCalculatorControl(calculator, 'USD');
  await tapCalculatorControl(calculator, 'Clear');
  await expect(dollars).toHaveValue('0');
  await tapCalculatorControl(calculator, '4');
  await expect(dollars).toHaveValue('4');
  await tapCalculatorControl(calculator, '2');
  await expect(dollars).toHaveValue('42');
  await agent.assert('The selected USD tile shows exactly 42 and the EUR tile shows exactly 21.', { vision: 'only' });
  await app.screenshot('calculator-entered-usd-42-before-refresh');

  const udid = process.env.CURRENCY_E2E_UDID!;
  const directory = execFileSync('xcrun', ['simctl', 'get_app_container', udid,
    'com.dimasike.currency', 'group.com.dimasike.currency.shared'], { encoding: 'utf8' }).trim();
  const path = join(directory, 'rates.json');
  const original = readFileSync(path, 'utf8');
  const snapshot = JSON.parse(original) as Record<string, unknown> & {
    quotes: Record<string, { value: number }>;
  };
  assert.equal(snapshot.quotes.USD.value, 2);
  for (const key of ['quotes', 'dailyQuotes', 'fiatQuotes', 'supplementalQuotes']) {
    const quotes = snapshot[key] as Record<string, { value: number }> | undefined;
    if (quotes?.USD) quotes.USD.value = 3;
  }
  snapshot.checkedAt = Date.now() / 1000 - 978_307_200;
  const temporary = join(directory, 'calculator-refresh-rates.tmp');
  try {
    writeFileSync(temporary, JSON.stringify(snapshot));
    renameSync(temporary, path);
    await app.restart();
    await expect(screen.getByRole('button', 'Edit amount in EUR')).toHaveValue('21');
    await expect(screen.getByRole('button', /^US Dollar,/i)).toHaveAccessibleName('US Dollar, 63');
    await device.home();
    await device.openApp('com.apple.springboard');
    await revealWidget('Currency Calculator', 'Medium');
    await expect(dollars).toHaveValue('42', { timeout: 30_000 });
    await agent.waitFor('The selected USD tile still shows exactly 42 and the EUR tile now shows exactly 14. Both complete amounts are visibly readable.', { vision: 'only', timeout: 30_000 });
    await app.screenshot('calculator-entered-usd-42-after-refresh-eur-14');
  } finally {
    writeFileSync(temporary, original);
    renameSync(temporary, path);
  }
});

test.afterAll(async () => {
  await unloadWidgetHelper();
});
