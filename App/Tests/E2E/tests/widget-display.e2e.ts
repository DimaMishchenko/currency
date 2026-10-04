import { expect } from 'e2e';
import { test } from '../widget-gallery-fixtures.js';

const displayTags = ['extended', 'widgets', 'widget-display'];
const sizeTags = ['extended', 'widget-sizes'];
const loadedContent = 'The installed Currency widget is on the normal Home Screen and has fully loaded content. It has no redacted placeholders, missing-value dashes, "Open app to load rates", "History unavailable", "Add a currency in the app", or Local currency setup or permission prompt.';

test('medium Currency board displays default amounts and follows app amount changes', { tags: displayTags }, async ({ installedWidget, app, agent, device, screen }) => {
  const board = await installedWidget('Currency board', 'Medium');
  await expect(board).toBeVisible();
  await agent.waitFor(`${loadedContent} The medium Currency board shows an EUR row with exactly 1 and a USD row with exactly 2. Both rows and their complete amounts are readable.`, { vision: 'only', timeout: 30_000 });
  await app.screenshot('widget-board-medium-eur-1-usd-2');

  await app.restart();
  await expect(screen.getByRole('button', 'Edit amount in EUR')).toHaveValue('1');
  await agent.act('Replace the Euro source amount with exactly 42 using the calculator keypad: enter 4 then 2. Finish with the keypad toolbar checkmark if it is shown. Stay on the converter.');
  await expect(screen.getByRole('button', 'Edit amount in EUR')).toHaveValue('42');
  await expect(screen.getByRole('button', /^US Dollar,/i)).toHaveAccessibleName('US Dollar, 84');

  await device.home();
  await device.openApp('com.apple.springboard');
  await expect(board).toBeVisible();
  await agent.waitFor(`${loadedContent} The medium Currency board now shows an EUR row with exactly 42 and a USD row with exactly 84. It no longer shows the old EUR 1 and USD 2 amounts.`, { vision: 'only', timeout: 30_000 });
  await app.screenshot('widget-board-medium-eur-42-usd-84');

  await app.restart();
  await expect(screen.getByRole('button', 'Edit amount in EUR')).toHaveValue('42');
  await expect(screen.getByRole('button', /^US Dollar,/i)).toHaveAccessibleName('US Dollar, 84');
});

test('medium Know Your Cash displays the CZK 100 banknote estimate in EUR', { tags: displayTags }, async ({ installedWidget, app, agent }) => {
  const cash = await installedWidget('Know Your Cash', 'Medium');
  await expect(cash).toBeVisible();
  await agent.waitFor(`${loadedContent} The medium Know Your Cash widget is configured with base CZK and target EUR. Its main banknote amount is exactly 100 CZK and the adjacent converted estimate is exactly approximately 4 EUR, shown with the approximation sign. This is the main estimate, not just a preset button.`, { vision: 'only', timeout: 30_000 });
  await app.screenshot('widget-cash-medium-czk-100-eur-4');
});

test('small Pocket Rate displays the EUR 5 to approximately USD 10 anchor', { tags: displayTags }, async ({ installedWidget, app, agent }) => {
  const pocket = await installedWidget('Pocket Rate', 'Small');
  await expect(pocket).toBeVisible();
  await agent.waitFor(`${loadedContent} The small Pocket Rate widget shows EUR with exactly 5 in its upper row and USD with exactly approximately 10 in its lower row. The lower amount includes the approximation sign, and both currency codes and amounts are readable.`, { vision: 'only', timeout: 30_000 });
  await app.screenshot('widget-pocket-small-eur-5-usd-10');
});

test('small Mental Math displays the EUR multiply by 2 rule for USD', { tags: displayTags }, async ({ installedWidget, app, agent }) => {
  const mental = await installedWidget('Mental Math', 'Small');
  await expect(mental).toBeVisible();
  await agent.waitFor(`${loadedContent} The small Mental Math widget shows the source EUR, the complete words "Multiply by", the factor exactly 2, and the target "≈ USD". It is a multiplication rule with all of that content readable.`, { vision: 'only', timeout: 30_000 });
  await app.screenshot('widget-mental-small-eur-multiply-2-usd');
});

test('medium History displays the actual seeded EUR USD rate and one month graph', { tags: displayTags }, async ({ installedWidget, app, agent }) => {
  const history = await installedWidget('History', 'Medium');
  await expect(history).toBeVisible();
  await expect(history.getByLabel('Rate change over the selected range', { exact: true })).toHaveValue(/^\+11[.,]11%$/, { timeout: 30_000 });
  await expect(history.getByLabel('One month', { exact: true })).toBeVisible();
  await agent.waitFor(`${loadedContent} The medium History widget shows the EUR row with exactly 1 and the USD row with current rate exactly 2 (the formatted value of 2.0). It shows exactly +11.11% (or +11,11% with a decimal comma) and the one month range label 1M. A rising historical graph is visibly drawn behind the loaded currency data. Its displayed observation date is ${new Intl.DateTimeFormat('en-US', { month: 'long', day: 'numeric', timeZone: 'UTC' }).format(new Date(Date.now() - 86_400_000))}.`, { vision: 'only', timeout: 30_000 });
  await app.screenshot('widget-history-medium-eur-usd-2-plus-11-11');
});

test('large Currency Calculator displays default EUR 1 and USD 2 with its keypad', { tags: sizeTags }, async ({ installedWidget, app, agent }) => {
  const calculator = await installedWidget('Currency Calculator', 'Large');
  await expect(calculator).toBeVisible();
  await expect(calculator.getByRole('button', /^Euro, EUR/i)).toHaveValue('1', { timeout: 30_000 });
  await expect(calculator.getByRole('button', /^US Dollar, USD/i)).toHaveValue('2', { timeout: 30_000 });
  await agent.waitFor(`${loadedContent} The large Currency Calculator widget shows EUR with exactly 1 and USD with exactly 2. The calculator keypad is visible below the currency tiles, and the tiles and keypad fit within the widget without clipping.`, { vision: 'only', timeout: 30_000 });
  await app.screenshot('widget-calculator-large-eur-1-usd-2');
});

test('small Currency board keeps default EUR 1 and USD 2 readable', { tags: sizeTags }, async ({ installedWidget, app, agent }) => {
  const board = await installedWidget('Currency board', 'Small');
  await expect(board).toBeVisible();
  await agent.waitFor(`${loadedContent} The small Currency board shows an EUR row with exactly 1 and a USD row with exactly 2. Both currency codes and their complete amounts fit inside the small widget and are readable without clipping.`, { vision: 'only', timeout: 30_000 });
  await app.screenshot('widget-board-small-eur-1-usd-2');
});

test('large Currency board keeps default EUR 1 and USD 2 readable', { tags: sizeTags }, async ({ installedWidget, app, agent }) => {
  const board = await installedWidget('Currency board', 'Large');
  await expect(board).toBeVisible();
  await agent.waitFor(`${loadedContent} The large Currency board shows an EUR row with exactly 1 and a USD row with exactly 2. Both currency codes and their complete amounts fit inside the large widget and are readable without clipping.`, { vision: 'only', timeout: 30_000 });
  await app.screenshot('widget-board-large-eur-1-usd-2');
});

test('small History keeps the actual EUR USD rate and percentage change readable', { tags: sizeTags }, async ({ installedWidget, app, agent }) => {
  const history = await installedWidget('History', 'Small');
  await expect(history).toBeVisible();
  await expect(history.getByLabel('Rate change over the selected range', { exact: true })).toHaveValue(/^\+11[.,]11%$/, { timeout: 30_000 });
  await expect(history.getByLabel('One month', { exact: true })).toBeVisible();
  await agent.waitFor(`${loadedContent} The small History widget shows EUR with exactly 1, USD with current rate exactly 2 (the formatted value of 2.0), change exactly +11.11% (or +11,11% with a decimal comma), and the range 1M. The rising graph is visible behind the content, and the codes, amounts, change and range remain readable within the small widget without clipping.`, { vision: 'only', timeout: 30_000 });
  await app.screenshot('widget-history-small-eur-usd-2-plus-11-11');
});
