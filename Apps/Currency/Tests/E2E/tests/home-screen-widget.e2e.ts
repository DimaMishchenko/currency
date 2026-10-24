import { setTimeout as delay } from 'node:timers/promises';
import { revealWidget, unloadWidgetHelper, widgetSetupMethod } from '../simulator-widgets.js';
import { test, tapCalculatorControl } from '../widget-fixtures.js';
import { expect } from 'e2e';

test('Home Screen calculator shares input and starts fresh after one minute of inactivity', { tags: ['extended', 'widgets'] }, async ({ calculator, app, agent, screen, device }) => {
  const dollars = calculator.getByRole('button', /^US Dollar, USD/i);
  await tapCalculatorControl(calculator, 'EUR');
  await tapCalculatorControl(calculator, 'Clear');
  await expect(dollars).toHaveValue('0');
  await tapCalculatorControl(calculator, '4');
  await expect(dollars).toHaveValue('8');
  await tapCalculatorControl(calculator, '2');
  await expect(calculator.getByRole('button', /^US Dollar, USD/i)).toHaveValue('84');
  await agent.assert('The Currency widget shows EUR with amount 42 and USD with amount 84.', { vision: 'only' });
  await app.screenshot('home-screen-widget-42-eur-84-usd');

  await app.restart();
  await expect(screen.getByTestId('converter.source')).toHaveAccessibleName(/Euro/i);
  await expect(screen.getByRole('button', 'Edit amount in EUR')).toHaveValue('42');
  await expect(screen.getByRole('button', /^US Dollar,/i)).toHaveAccessibleName('US Dollar, 84');
  await app.screenshot('converter-shared-widget-amount');

  await device.home();
  await device.openApp('com.apple.springboard');
  if (widgetSetupMethod() === 'private') await revealWidget('Currency Calculator', 'Medium');
  else await agent.act('Show the Home Screen page containing the installed Currency Calculator widget.');
  await expect(dollars).toHaveValue('84');
  await delay(61_000);
  await expect(dollars).toHaveValue('84');
  await tapCalculatorControl(calculator, '2');
  await expect(dollars).toHaveValue('4');
  await tapCalculatorControl(calculator, '4');
  await expect(dollars).toHaveValue('48');
  await agent.assert('The Currency calculator widget visibly shows EUR 24 and USD 48, with both complete amounts readable.', { vision: 'only' });
  await app.screenshot('home-screen-widget-after-inactivity-eur-24-usd-48');

  await app.restart();
  await expect(screen.getByRole('button', 'Edit amount in EUR')).toHaveValue('24');
  await expect(screen.getByRole('button', /^US Dollar,/i)).toHaveAccessibleName('US Dollar, 48');
});

test.afterAll(async () => {
  await unloadWidgetHelper();
});
