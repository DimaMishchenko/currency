import { expect } from 'e2e';
import { test } from '../widget-gallery-fixtures.js';
import { configureWidget, revealWidget, unloadWidgetHelper, widgetParameters, widgetSetupMethod } from '../simulator-widgets.js';

const options = {
  tags: ['extended', 'widgets', 'widget-configuration'],
  skip: widgetSetupMethod() === 'gallery' ? 'Direct configuration coverage requires private simulator setup.' : false,
};

function reversePair(parameters: Record<string, unknown>) {
  if (!parameters.base || !parameters.comparison) throw new Error('Expected the full configured currency pair.');
  [parameters.base, parameters.comparison] = [parameters.comparison, parameters.base];
}

test('Pocket Rate renders a configured reverse pair and restores its default pair', options, async ({ installedWidget, app, agent }) => {
  const pocket = await installedWidget('Pocket Rate', 'Small');
  await configureWidget('Pocket Rate', 'Small', reversePair);
  await expect(pocket).toBeVisible();
  await agent.waitFor('The Home Screen Pocket Rate widget shows USD with exactly 20 in its upper entry and EUR with exactly approximately 10 in its lower entry. Both currency codes, complete amounts and flags are readable, with no placeholder or permission prompt.', { vision: 'only', timeout: 30_000 });
  await app.screenshot('widget-pocket-configured-usd-20-eur-10');
  await configureWidget('Pocket Rate', 'Small', reversePair);
  await agent.waitFor('The Home Screen Pocket Rate widget now shows EUR with exactly 5 in its upper entry and USD with exactly approximately 10 in its lower entry. Both codes and amounts are readable. It no longer shows USD 20 as its source.', { vision: 'only', timeout: 30_000 });
  await app.screenshot('widget-pocket-restored-eur-5-usd-10');
});

test('Mental Math renders the division rule for its configured reverse pair', options, async ({ installedWidget, app, agent }) => {
  const mental = await installedWidget('Mental Math', 'Small');
  await configureWidget('Mental Math', 'Small', reversePair);
  await expect(mental).toBeVisible();
  await agent.waitFor('The Home Screen Mental Math widget shows source USD, the complete words "Divide by", factor exactly 2, and target "≈ EUR". All content is readable with no placeholder or permission prompt.', { vision: 'only', timeout: 30_000 });
  await app.screenshot('widget-mental-configured-usd-divide-2-eur');
});

test('Custom Board retains its configured amount when the app amount changes', options, async ({ installedWidget, app, agent, device, screen }) => {
  await installedWidget('Pocket Rate', 'Small');
  const pair = await widgetParameters('Pocket Rate', 'Small');
  if (!pair.comparison) throw new Error('Expected the full canonical USD entity.');
  const board = await installedWidget('Currency board', 'Medium');
  await configureWidget('Currency board', 'Medium', (parameters) => {
    parameters.amount = '7';
    parameters.list = 'selected';
    parameters.currencies = [pair.comparison];
  });
  await expect(board).toBeVisible();
  const expectedBoard = 'The medium Home Screen Currency Board shows EUR with exactly 7 and USD with exactly 14. Both entries and complete amounts are readable. Empty space below these entries is expected; there is no missing-value or setup message.';
  await agent.waitFor(expectedBoard, { vision: 'only', timeout: 30_000 });
  await app.restart();
  await agent.act('Replace the Euro source amount with exactly 42 using the calculator keypad: enter 4 then 2. Finish with the keypad toolbar checkmark if it is shown. Stay on the converter.');
  await expect(screen.getByRole('button', 'Edit amount in EUR')).toHaveValue('42');
  await expect(screen.getByRole('button', /^US Dollar,/i)).toHaveAccessibleName('US Dollar, 84');
  await device.home();
  await device.openApp('com.apple.springboard');
  await revealWidget('Currency board', 'Medium');
  await agent.waitFor(expectedBoard, { vision: 'only', timeout: 30_000 });
  await app.screenshot('widget-board-custom-eur-7-usd-14-app-42');
  await configureWidget('Currency board', 'Medium', (parameters) => {
    parameters.amount = '8';
  });
  await agent.waitFor('The medium Home Screen Currency Board now shows EUR with exactly 8 and USD with exactly 16. It no longer shows 7 and 14 or the app amounts 42 and 84. Both entries and complete amounts are readable; empty space below them is expected.', { vision: 'only', timeout: 30_000 });
  await app.screenshot('widget-board-custom-eur-8-usd-16-app-42');
});

test.afterAll(async () => {
  await unloadWidgetHelper();
});
