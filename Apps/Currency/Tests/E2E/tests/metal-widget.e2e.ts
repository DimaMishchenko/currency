import { expect } from 'e2e';
import { test, tapCalculatorControl } from '../widget-fixtures.js';
import { unloadWidgetHelper, revealWidget, widgetSetupMethod } from '../simulator-widgets.js';

test('metal unit preference reaches calculator and widget edits return in that unit', { tags: ['extended', 'widgets'] }, async ({ calculator, start, app, agent, device, screen }) => {
  await start('ready-metals');
  await screen.getByTestId('converter.options').tap();
  await screen.getByTestId('converter.settings').tap();
  await screen.getByTestId('settings.metalUnit').getByText('Troy ounces').tap();
  await screen.getByTestId('settings.metalUnit.gram').tap();
  await screen.getByRole('button', 'Back', { exact: true }).tap();
  await expect(screen.getByRole('button', /^Gold,/i)).toHaveAccessibleName('Gold, 0.31103477 g');
  await device.home();
  await device.openApp('com.apple.springboard');
  if (widgetSetupMethod() === 'private') await revealWidget('Currency Calculator', 'Medium');
  const gold = calculator.getByRole('button', /^Gold, XAU/i);
  await expect(gold).toHaveValue(/^0[.,]31103477$/, { timeout: 30_000 });
  await agent.assert('The Currency Calculator Gold row visibly shows the measurement unit g.', { vision: 'only' });
  await app.screenshot('calculator-metal-grams');
  await tapCalculatorControl(calculator, 'EUR-three-currencies');
  await tapCalculatorControl(calculator, 'Clear');
  await tapCalculatorControl(calculator, '4');
  await expect(gold).toHaveValue(/^1[.,]24413907$/);
  await app.restart();
  await expect(screen.getByRole('button', 'Edit amount in EUR')).toHaveValue('4');
  await expect(screen.getByRole('button', /^Gold,/i)).toHaveAccessibleName('Gold, 1.24413907 g');
  await app.screenshot('converter-widget-metal-grams');
});

test.afterAll(async () => {
  await unloadWidgetHelper();
});
