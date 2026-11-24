import { expect } from 'e2e';
import { revealWidget, unloadWidgetHelper, widgetSetupMethod } from '../simulator-widgets.js';
import { test, tapCalculatorControl } from '../widget-fixtures.js';

test('Settings omits widget feedback and Calculator shares input after restart', { tags: ['extended', 'widgets'] }, async ({ calculator, app, agent, device, screen }) => {
  async function expectNoWidgetFeedback() {
    await screen.getByTestId('converter.options').tap();
    await screen.getByTestId('converter.settings').tap();
    const metalUnit = screen.getByTestId('settings.metalUnit');
    await screen.scrollUntilVisible(metalUnit);
    await expect(metalUnit).toBeVisible();
    await expect(screen.getByTestId('settings.widgetHaptics')).toBeHidden();
    await expect(screen.getByText('Haptic feedback', { exact: true })).toBeHidden();
    const location = screen.getByTestId('settings.location');
    await screen.scrollUntilVisible(location);
    await expect(location).toBeVisible();
    await expect(screen.getByTestId('settings.widgetHaptics')).toBeHidden();
    await expect(screen.getByText('Haptic feedback', { exact: true })).toBeHidden();
  }

  await app.restart();
  await expectNoWidgetFeedback();
  await app.screenshot('settings-without-widget-feedback');
  await app.restart();
  await expectNoWidgetFeedback();
  await device.home();
  await device.openApp('com.apple.springboard');
  if (widgetSetupMethod() === 'private') await revealWidget('Currency Calculator', 'Medium');
  else await agent.act('Show the Home Screen page containing the installed Currency Calculator widget.');
  const dollars = calculator.getByRole('button', /^US Dollar, USD/i);
  await tapCalculatorControl(calculator, 'EUR');
  await tapCalculatorControl(calculator, 'Clear');
  await expect(dollars).toHaveValue('0');
  await tapCalculatorControl(calculator, '4');
  await expect(dollars).toHaveValue('8');
  await tapCalculatorControl(calculator, '2');
  await expect(dollars).toHaveValue('84');
  await expect(calculator).toBeVisible();
  await expect(screen.getByTestId('converter.source')).toBeHidden();
  await app.screenshot('calculator-shared-input');

  await app.restart();
  await expect(screen.getByRole('button', 'Edit amount in EUR')).toHaveValue('42');
  await expect(screen.getByRole('button', /^US Dollar,/i)).toHaveAccessibleName('US Dollar, 84.00');
});

test.afterAll(async () => {
  await unloadWidgetHelper();
});
