import assert from 'node:assert/strict';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { expect, type TestFixtures } from 'e2e';
import { test } from '../fixtures.js';

type PickerContext = Pick<TestFixtures, 'agent' | 'screen'>;

const currencies = [
  ['', 'Yen / Yuan'], ['Euro', 'Euro'], ['Pound', 'Pound'],
  ['Rupee', 'Rupee'], ['Won', 'Won'], ['Bitcoin', 'Bitcoin'],
] as const;

async function openPicker({ screen }: PickerContext) {
  await expect(screen.getByRole('button', 'Edit amount in EUR')).toHaveValue('1');
  await screen.getByTestId('converter.options').tap();
  await screen.getByTestId('converter.settings').tap();
  await screen.getByTestId('settings.appIcon').tap();
  await expect(screen.getByTestId('settings.appIcon.section.world')).toBeVisible();
}

async function revealIcon({ screen }: PickerContext, icon: string, direction: 'down' | 'up' = 'down') {
  const tile = screen.getByTestId(`settings.appIcon.${icon}`);
  await revealPickerItem({ screen }, tile, direction);
  await expect(tile).toBeVisible();
}

async function revealPickerItem(
  { screen }: Pick<PickerContext, 'screen'>,
  target: ReturnType<PickerContext['screen']['getByTestId']>,
  direction: 'down' | 'up' = 'down',
) {
  const viewport = await screen.getByLabel('Currency', { exact: true }).boundingBox();
  const navigation = await screen.getByRole('navigation').boundingBox();
  assert.ok(viewport && navigation, 'Picker scrolling requires actual viewport and navigation bounds');
  const top = navigation.y + navigation.height;
  const bottom = viewport.y + viewport.height;
  const centerY = (top + bottom) / 2;
  const distance = (bottom - top) * 0.15;
  for (let swipe = 0; swipe < 8; swipe++) {
    const bounds = await target.count() === 1 ? await target.boundingBox() : null;
    if (bounds && bounds.y >= top && bounds.y + bounds.height <= bottom) return;
    const above = bounds ? bounds.y < top : direction === 'up';
    await screen.swipe({
      from: { x: viewport.x + viewport.width / 2, y: centerY },
      to: { x: viewport.x + viewport.width / 2, y: centerY + (above ? distance : -distance) },
    });
  }
  throw new Error('App icon item did not become fully visible inside the picker');
}

async function assertCatalog(context: PickerContext) {
  const { screen } = context;
  for (const [style, title] of [['world', 'World'], ['grid', 'Grid']] as const) {
    const heading = screen.getByTestId(`settings.appIcon.section.${style}`);
    await revealPickerItem(context, heading);
    await expect(heading).toBeVisible();
    for (const [suffix, currency] of currencies) {
      await revealIcon(context, `${style}${suffix}`);
      await expect(screen.getByRole('button', `${currency} · ${title}`)).toBeVisible();
    }
  }
}

test('app icon picker shows both styles and twelve named currency tiles', { tags: ['core'] }, async ({ start, agent, app, screen }) => {
  await start('ready-converter');
  await openPicker({ agent, screen });
  await assertCatalog({ agent, screen });
  await app.screenshot('settings-app-icon-catalog');
});

test('named currency app icons survive restart and restore World Yen / Yuan', { tags: ['core'] }, async ({ start, agent, app, screen }) => {
  const context = { agent, screen };
  await start('ready-converter');
  await openPicker(context);
  await assertCatalog(context);
  for (const icon of ['worldEuro', 'gridBitcoin', 'world'] as const) {
    await revealIcon(context, icon, icon.startsWith('world') ? 'up' : 'down');
    await screen.getByTestId(`settings.appIcon.${icon}`).tap();
    await agent.act('If iOS shows an app icon change confirmation, tap its OK button. Stay on the App icon screen with the confirmation dismissed.');
    await expect(screen.getByTestId(`settings.appIcon.${icon}`)).toHaveValue('Selected');
    await expect(screen.getByTestId('settings.appIcon.error')).not.toBeVisible();
    await app.screenshot(`settings-app-icon-${icon}`);
    await app.restart();
    await openPicker(context);
    await revealIcon(context, icon, icon.startsWith('world') ? 'up' : 'down');
    await expect(screen.getByTestId(`settings.appIcon.${icon}`)).toHaveValue('Selected');
  }
});

test('app icon picker adapts when largest accessibility text and dark appearance change while open', { tags: ['accessibility'] }, async ({ start, agent, app, screen }) => {
  const udid = process.env.CURRENCY_E2E_UDID?.trim();
  assert.ok(udid, 'CURRENCY_E2E_UDID must identify this test’s owned simulator');
  const run = promisify(execFile);
  const ui = async (setting: 'content_size' | 'appearance', value?: string) => {
    const { stdout } = await run('/usr/bin/xcrun', ['simctl', 'ui', udid, setting, ...(value ? [value] : [])], {
      encoding: 'utf8', timeout: 15_000, maxBuffer: 4096,
    });
    return stdout.trim();
  };
  const originalSize = await ui('content_size');
  const originalAppearance = await ui('appearance');
  const sizes = [
    'extra-small', 'small', 'medium', 'large', 'extra-large', 'extra-extra-large', 'extra-extra-extra-large',
    'accessibility-medium', 'accessibility-large', 'accessibility-extra-large',
    'accessibility-extra-extra-large', 'accessibility-extra-extra-extra-large',
  ];
  assert.ok(sizes.includes(originalSize), `Cannot restore unknown content size: ${originalSize}`);
  assert.ok(['light', 'dark'].includes(originalAppearance), `Cannot restore unknown appearance: ${originalAppearance}`);
  try {
    await ui('content_size', 'large');
    await ui('appearance', 'light');
    await start('ready-converter');
    const context = { agent, screen };
    await openPicker(context);
    const firstTile = screen.getByTestId('settings.appIcon.world');
    const originalBounds = await firstTile.boundingBox();
    assert.ok(originalBounds, 'The normal-size first tile must have visible bounds');

    await ui('content_size', 'accessibility-extra-extra-extra-large');
    await ui('appearance', 'dark');
    await expect.poll(async () => (await firstTile.boundingBox())?.width ?? 0, { timeout: 15_000 })
      .toBeGreaterThan(originalBounds.width * 1.5);
    await assertCatalog(context);
    const selected = screen.getByTestId('settings.appIcon.world');
    const viewport = await screen.getByLabel('Currency', { exact: true }).boundingBox();
    const navigation = await screen.getByRole('navigation').boundingBox();
    assert.ok(viewport && navigation, 'Capture requires native viewport and navigation bounds');
    await revealPickerItem(context, selected, 'up');
    const selectedBounds = await selected.boundingBox();
    assert.ok(selectedBounds && selectedBounds.x >= viewport.x
      && selectedBounds.x + selectedBounds.width <= viewport.x + viewport.width
      && selectedBounds.y >= navigation.y + navigation.height
      && selectedBounds.y + selectedBounds.height <= viewport.y + viewport.height,
    'Selected tile must be fully inside the visible picker');
    await expect(selected).toBeVisible();
    await expect(selected).toHaveValue('Selected');
    await app.screenshot('settings-app-icon-live-accessibility-dark');
    await agent.assert('The App icon picker is in dark appearance with very large accessibility text. The selected World Yen / Yuan tile is fully on screen. Its name has complete readable glyphs, without clipping or words broken into one- or two-character fragments. Its small contrasting checkmark badge is clearly visible at the icon corner. The badge may overlap the rounded icon frame, but it does not obscure either currency symbol. Other fully visible tile names are readable; a row partially cut off at the viewport scroll edge is allowed.', { vision: 'only' });
  } catch (error) {
    await app.screenshot('settings-app-icon-accessibility-failure-before-restoration').catch(() => {});
    throw error;
  } finally {
    try {
      await ui('content_size', originalSize);
    } finally {
      await ui('appearance', originalAppearance);
    }
  }
});
