import { expect } from 'e2e';
import { test } from '../widget-gallery-fixtures.js';
import { configureWidget, revealWidget, unloadWidgetHelper, widgetSetupMethod } from '../simulator-widgets.js';

const cases = [
  { title: 'Currency board', family: 'Medium', screenshot: 'board-metal-grams', expected: 'EUR 1, USD 2, and XAU with a visible g unit and exactly 0.31103477 (decimal comma is also valid)' },
  { title: 'Know Your Cash', family: 'Medium', screenshot: 'cash-metal-weights', expected: 'XAU to EUR with main weight 1 g, estimate approximately 3.22 EUR, and weight preset buttons 1 g, 10 g, and 1 kg' },
  { title: 'Pocket Rate', family: 'Small', screenshot: 'pocket-metal-grams', expected: 'source EUR with exactly 50 and target XAU with a visible g unit and approximately 15.5517384 (decimal comma is also valid)' },
  { title: 'Mental Math', family: 'Small', screenshot: 'mental-metal-grams', expected: 'source EUR, Divide by, factor exactly 3.2, and target XAU with a visible g unit (decimal comma is also valid)' },
  { title: 'History', family: 'Medium', screenshot: 'history-metal-grams', expected: 'source EUR with 1, target XAU with a visible g unit and current rate 0.311035 (decimal comma is also valid), a rising chart, +11.11 percent change, and one month range 1M' },
] as const;

function goldEntity(entity: unknown, originalCode: string): unknown {
  if (!entity) throw new Error('Expected a canonical comparison entity.');
  const encoded = JSON.stringify(entity);
  if (!encoded.includes(originalCode)) throw new Error(`Expected the default ${originalCode} entity.`);
  return JSON.parse(encoded.replaceAll(originalCode, 'XAU'));
}

for (const item of cases) {
  test(`${item.title} displays metal measurement and loaded amounts`, {
    tags: ['extended', 'widgets', 'metal-widget-display'],
    skip: widgetSetupMethod() === 'gallery' ? 'Metal pair configuration requires private simulator setup.' : false,
  }, async ({ installedWidget, start, app, agent, device, screen }) => {
    const widget = await installedWidget(item.title, item.family);
    await start('ready-metals');
    await screen.getByTestId('converter.options').tap();
    await screen.getByTestId('converter.settings').tap();
    await screen.getByTestId('settings.metalUnit').getByText('Troy ounces').tap();
    await screen.getByTestId('settings.metalUnit.gram').tap();
    await screen.getByRole('button', 'Back', { exact: true }).tap();
    await expect(screen.getByRole('button', /^Gold,/i)).toHaveAccessibleName('Gold, 0.31103477 g');
    await device.home();
    await device.openApp('com.apple.springboard');
    if (item.title !== 'Currency board') {
      await configureWidget(item.title, item.family, parameters => {
        console.log('Metal widget configuration', item.title, JSON.stringify(parameters));
        if (item.title === 'Know Your Cash') {
          parameters.base = goldEntity(parameters.base, 'CZK');
        } else {
          parameters.comparison = goldEntity(parameters.comparison, 'USD');
        }
      });
    }
    await revealWidget(item.title, item.family);
    await expect(widget).toBeVisible();
    await agent.waitFor(`The installed ${item.title} widget is on the Home Screen and visibly shows ${item.expected}. All amounts and units fit and are readable. It has no placeholder, missing-value dash, unavailable history, or setup prompt.`, { vision: 'only', timeout: 30_000 });
    await app.screenshot(item.screenshot);
  });
}

test.afterAll(async () => {
  await unloadWidgetHelper();
});
