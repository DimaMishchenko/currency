import { expect, type Locator } from 'e2e';
import { test as base } from './widget-gallery-fixtures.js';
import { widgetSetupMethod } from './simulator-widgets.js';

export const test = base.extend<{ calculator: Locator }>({
  calculator: async ({ start, device, installedWidget, screen }, use) => {
    let calculator: Locator;
    if (widgetSetupMethod() === 'private') {
      calculator = await installedWidget('Currency Calculator', 'Medium');
    } else {
      calculator = device.locator('id=Currency value=Widget');
      await start('ready-converter');
      await expect(screen.getByRole('button', 'Edit amount in EUR')).toHaveValue('1');
      await expect(screen.getByRole('button', /^US Dollar,/i)).toHaveAccessibleName('US Dollar, 2');
      await device.home();
      await device.openApp('com.apple.springboard');
      const box = await calculator.count() === 1 ? await calculator.boundingBox() : null;
      if (!box || box.width / box.height < 1.7 || box.width / box.height > 2
        || await calculator.getByRole('button', /^US Dollar, USD/i).count() === 0) {
        calculator = await installedWidget('Currency Calculator', 'Medium');
      }
    }
    await expect(calculator).toBeVisible();
    await expect(calculator).toHaveValue('Widget');
    await expect(screen.getByRole('button', 'Done')).toBeHidden();
    await expect(calculator.getByRole('button', /^US Dollar, USD/i)).toHaveValue('2', { timeout: 30_000 });
    if (await calculator.count() !== 1) throw new Error('Use exactly one owned Default medium Calculator widget.');
    await use(calculator);
  },
});

export async function tapCalculatorControl(calculator: Locator, control: 'EUR' | 'EUR-three-currencies' | 'Clear' | '4' | '2') {
  const positions = { EUR: [0.26, 0.27], 'EUR-three-currencies': [0.15, 0.27], Clear: [0.89, 0.36], '4': [0.54, 0.36], '2': [0.66, 0.53] } as const;
  const box = await calculator.boundingBox();
  if (!box || box.width / box.height < 1.7 || box.width / box.height > 2) {
    throw new Error('Widget taps require the verified medium Calculator layout.');
  }
  const [x, y] = positions[control];
  await calculator.tap({ position: { x: box.width * x, y: box.height * y } });
}
