import { unloadWidgetHelper } from '../simulator-widgets.js';
import { expect } from 'e2e';
import { test } from '../widget-fixtures.js';

test('app amount and currency additions update the Home Screen calculator', { tags: ['extended', 'widgets'] }, async ({ calculator, app, agent, device, screen }) => {
  await app.restart();
  await expect(screen.getByTestId('converter.source')).toHaveAccessibleName(/Euro/i);
  await expect(screen.getByRole('button', 'Edit amount in EUR')).toHaveValue('1');
  await expect(screen.getByRole('button', /^US Dollar,/i)).toHaveAccessibleName('US Dollar, 2');

  await agent.act('Replace the Euro source amount with exactly 42 using the calculator keypad: enter 4 then 2. Finish with the keypad toolbar checkmark if it is shown. Stay on the converter.');
  await expect(screen.getByRole('button', 'Edit amount in EUR')).toHaveValue('42');
  await expect(screen.getByRole('button', /^US Dollar,/i)).toHaveAccessibleName('US Dollar, 84');

  await agent.act('Open Add currency, search for CHF, and select Swiss Franc (CHF). Return to the converter after the picker closes. Keep the Euro source amount 42 and the existing US Dollar destination.');
  await expect(screen.getByRole('button', 'Edit amount in EUR')).toHaveValue('42');
  await expect(screen.getByRole('button', /^US Dollar,/i)).toHaveAccessibleName('US Dollar, 84');
  await expect(screen.getByRole('button', /^Swiss Franc,/i)).toHaveAccessibleName(/^Swiss Franc, 21$/i);

  await device.home();
  await device.openApp('com.apple.springboard');
  await expect(calculator).toBeVisible();
  await expect(calculator.getByRole('button', /^Swiss Franc, CHF/i)).toHaveValue('21');
  await agent.assert('The Currency widget shows EUR with amount 42, USD with amount 84 and CHF with amount 21.', { vision: 'only' });
  await app.screenshot('app-to-widget-42-eur-84-usd-21-chf');
});

test.afterAll(async () => {
  await unloadWidgetHelper();
});
