import { expect, type Locator } from 'e2e';
import { test as base } from './fixtures.js';
import { placeWidget, prepareWidgetHelper, widgetSetupMethod } from './simulator-widgets.js';

export const test = base.extend<{
  installedWidget: (title: string, family: 'Small' | 'Medium' | 'Large') => Promise<Locator>;
}>({
  installedWidget: async ({ start, device, screen }, use) => {
    await use(async (title, family) => {
      if (widgetSetupMethod() === 'private') await prepareWidgetHelper();
      await start('ready-converter');
      await expect(screen.getByRole('button', 'Edit amount in EUR')).toHaveValue('1');
      await expect(screen.getByRole('button', /^US Dollar,/i)).toHaveAccessibleName('US Dollar, 2');
      await device.home();
      await device.openApp('com.apple.springboard');
      const widget = device.locator('id=Currency value=Widget');
      if (widgetSetupMethod() === 'private') {
        await placeWidget(title, family);
      } else {
        while (await widget.count() > 0) {
          if (await widget.count() !== 1) throw new Error('Use one Currency widget at a time on the owned Home Screen.');
          await widget.longPress({ duration: 1500 });
          if (await screen.getByRole('button', 'Remove', { exact: true }).count() === 0) {
            await screen.getByRole('button', 'Remove Widget', { exact: true }).tap();
          }
          await screen.getByRole('button', 'Remove', { exact: true }).tap();
          await expect(widget).toBeHidden();
        }
        await screen.getByTestId('Home screen icons').longPress({ duration: 1500 });
        await screen.getByRole('button', 'Edit', { exact: true }).tap();
        await screen.getByRole('button', 'Add Widget', { exact: true }).tap();
        await screen.getByRole('textbox', 'Search Widgets', { exact: true }).fill('Currency');
        await device.dismissKeyboard();
        await screen.getByRole('listitem', 'Currency', { exact: true }).tap();
        const selected = screen.getByRole('button', `Currency, ${title}`);
        const preview = screen.getByRole('button', /^Currency, /);
        for (let page = 0; page < 10; page++) {
          if (await selected.count() === 1 && await selected.inputValue() === `Widget, ${family}`) break;
          await preview.swipe({ direction: 'right' });
        }
        await expect(selected).toHaveValue(`Widget, ${family}`);
        await screen.getByRole('button', 'Add Widget', { exact: true }).tap();
        await screen.getByRole('button', 'Done', { exact: true }).tap();
      }
      await expect(widget).toBeVisible();
      await expect(screen.getByRole('button', 'Done')).toBeHidden();
      if (await widget.count() !== 1) throw new Error('Expected exactly one installed Currency widget.');
      return widget;
    });
  },
});
