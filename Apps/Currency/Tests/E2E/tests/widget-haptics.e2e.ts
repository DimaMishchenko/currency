import { expect } from 'e2e';
import { revealWidget, unloadWidgetHelper, widgetSetupMethod } from '../simulator-widgets.js';
import { test, tapCalculatorControl } from '../widget-fixtures.js';

for (const enabled of [true, false]) {
  test(`widget feedback stays ${enabled ? 'on' : 'off'} after restart and Calculator shares input`, { tags: ['extended', 'widgets'] }, async ({ calculator, app, agent, device, screen }) => {
    const feedback = screen.getByTestId('settings.widgetHaptics');
    async function openSettings() {
      await screen.getByTestId('converter.options').tap();
      await screen.getByTestId('converter.settings').tap();
      await screen.scrollUntilVisible(feedback);
      await expect(feedback).toBeVisible();
    }

    await app.restart();
    await openSettings();
    await expect(feedback).toBeChecked({ checked: false });
    await feedback.tap();
    await expect(feedback).toBeChecked();
    if (!enabled) {
      await feedback.tap();
      await expect(feedback).toBeChecked({ checked: false });
    }
    await expect(screen.getByTestId('settings.widgetHaptics.error')).toBeHidden();
    await app.screenshot(`widget-haptics-settings-${enabled ? 'on' : 'off'}`);

    await app.restart();
    await openSettings();
    await expect(feedback).toBeChecked({ checked: enabled });
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
    await app.screenshot(`widget-haptics-calculator-${enabled ? 'on' : 'off'}`);

    await app.restart();
    await expect(screen.getByRole('button', 'Edit amount in EUR')).toHaveValue('42');
    await expect(screen.getByRole('button', /^US Dollar,/i)).toHaveAccessibleName('US Dollar, 84');
  });
}

test.afterAll(async () => {
  await unloadWidgetHelper();
});
