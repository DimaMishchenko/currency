import assert from 'node:assert/strict';
import { expect } from 'e2e';
import { test } from '../fixtures.js';
import { configureWidget, placeWidget, prepareWidgetHelper, revealWidget, unloadWidgetHelper, widgetSetupMethod } from '../simulator-widgets.js';

const configurations = [
  { family: 'Small', range: 'day', title: '1 day', exclusive: true },
  { family: 'Medium', range: 'week', title: '1 week', exclusive: false },
] as const;

test('simultaneous Bitcoin History ranges share their latest rate and date with distinct period changes', {
  tags: ['extended', 'widgets', 'widget-history-sync'],
  skip: widgetSetupMethod() === 'gallery' ? 'Requires device-targeted widget configuration.' : false,
}, async ({ start, app, device, screen, agent }) => {
  await prepareWidgetHelper();
  for (let attempt = 0; attempt < 2; attempt++) {
    const seededHour = Math.floor(Date.now() / 3_600_000);
    await start('ready-history-sync');
    await expect(screen.getByRole('button', 'Edit amount in BTC')).toHaveValue('1');
    await expect(screen.getByRole('button', /^US Dollar,/i)).toHaveAccessibleName('US Dollar, 52,500');
    await app.screenshot('app-home-bitcoin-one-usd-52500-shared-quote');
    await device.closeApp();
    await device.openApp('com.apple.springboard');
    for (const configuration of configurations) {
      if (attempt === 0) await placeWidget('History', configuration.family, configuration.exclusive);
      await configureWidget('History', configuration.family, parameters => {
        parameters.base = { identifier: 'BTC', title: { key: 'BTC' }, subtitle: { key: 'BTC' } };
        parameters.comparison = { identifier: 'USD', title: { key: 'USD' }, subtitle: { key: 'USD' } };
        parameters.range = { identifier: configuration.range, value: configuration.range, title: { key: configuration.title } };
      });
    }
    try {
      const latest = new Date(seededHour * 3_600_000);
      const observed = new Intl.DateTimeFormat('en-GB', { month: 'short', day: 'numeric', timeZone: 'UTC' }).format(latest);
      const alternativeDate = new Intl.DateTimeFormat('en-US', { month: 'short', day: 'numeric', timeZone: 'UTC' }).format(latest);
      for (const configuration of configurations) {
        await revealWidget('History', configuration.family);
        const isDay = configuration.range === 'day';
        const widget = device.locator('id=Currency value=Widget').filter({ has: screen.getByLabel(isDay ? 'One day' : 'One week', { exact: true }) });
        await expect(widget).toBeVisible();
        await expect(widget.getByLabel('Rate change over the selected range', { exact: true }))
          .toHaveValue(isDay ? /^\+5[.,]00%$/ : /^\+31[.,]25%$/, { timeout: 30_000 });
        await expect(widget.getByLabel(new RegExp(`^Rate as of (${observed}|${alternativeDate})$`))).toBeVisible();
        await agent.waitFor(`The visible ${configuration.family.toLowerCase()} Currency widget on the Home Screen has BTC and USD currency rows. The USD amount is exactly 52,500 (52 500 with a space grouping separator is equivalent). Its observation date is ${observed}; its selected range is ${isDay ? '1D and its displayed change is exactly +5.00%' : '1W and its displayed change is exactly +31.25%'} (decimal comma is equivalent). A line chart is drawn behind the values. The currency codes, amount, percentage, date and range are readable without clipping. There are no placeholders, missing values or History unavailable messages.`, { vision: 'only', timeout: 30_000 });
        await app.screenshot(`widget-history-${configuration.family.toLowerCase()}-${configuration.range}-shared-latest`);
      }
      assert.equal(seededHour, Math.floor(Date.now() / 3_600_000), 'The fixture must remain in its current UTC cache hour.');
      break;
    } catch (error) {
      if (attempt === 1 || seededHour === Math.floor(Date.now() / 3_600_000)) throw error;
    }
  }
});

test.afterAll(async () => {
  await unloadWidgetHelper();
});
