import assert from 'node:assert/strict';
import { execFile } from 'node:child_process';
import { join } from 'node:path';
import { promisify } from 'node:util';
import { expect } from 'e2e';
import { test } from '../fixtures.js';
import { readHistory, sharedDirectory } from './history-cache.js';

const appearance = process.env.CURRENCY_A11Y_APPEARANCE ?? 'dark';
if (appearance !== 'light' && appearance !== 'dark') {
  throw new Error('CURRENCY_A11Y_APPEARANCE must be light or dark');
}
const orientation = process.env.CURRENCY_A11Y_ORIENTATION ?? 'portrait';
if (orientation !== 'portrait' && orientation !== 'landscape-left') {
  throw new Error('CURRENCY_A11Y_ORIENTATION must be portrait or landscape-left');
}

const scope = process.env.CURRENCY_A11Y_SCOPE ?? 'full';
if (scope !== 'full' && scope !== 'settings-history') {
  throw new Error('CURRENCY_A11Y_SCOPE must be full or settings-history');
}

test(`${scope === 'full' ? 'converter and supporting screens' : 'Settings and History'} remain readable at AX5 in ${appearance} increased contrast ${orientation}`, {
  tags: ['accessibility-visual'],
}, async ({ start, screen, agent, app, device }) => {
  const udid = process.env.CURRENCY_E2E_UDID?.trim();
  assert.ok(udid, 'CURRENCY_E2E_UDID must identify this test’s owned simulator');
  const run = promisify(execFile);
  const ui = async (setting: 'content_size' | 'appearance' | 'increase_contrast', value?: string) => {
    const { stdout } = await run('/usr/bin/xcrun', ['simctl', 'ui', udid, setting, ...(value ? [value] : [])], {
      encoding: 'utf8', timeout: 15_000, maxBuffer: 4096,
    });
    return stdout.trim();
  };
  const originalSize = await ui('content_size');
  const originalAppearance = await ui('appearance');
  const originalContrast = await ui('increase_contrast');
  const sizes = [
    'extra-small', 'small', 'medium', 'large', 'extra-large', 'extra-extra-large', 'extra-extra-extra-large',
    'accessibility-medium', 'accessibility-large', 'accessibility-extra-large',
    'accessibility-extra-extra-large', 'accessibility-extra-extra-extra-large',
  ];
  assert.ok(sizes.includes(originalSize), `Cannot restore unknown content size: ${originalSize}`);
  assert.ok(['light', 'dark'].includes(originalAppearance), `Cannot restore unknown appearance: ${originalAppearance}`);
  assert.ok(['enabled', 'disabled'].includes(originalContrast), `Cannot restore unknown contrast: ${originalContrast}`);
  try {
    await ui('content_size', 'large');
    await ui('appearance', 'light');
    await ui('increase_contrast', 'disabled');
    await start('ready-converter');
    await device.setOrientation(orientation);
    const amount = screen.getByRole('button', 'Edit amount in EUR', { exact: true });
    if (scope === 'full') {
      await amount.tap();
      for (const digit of '42') await screen.getByRole('button', digit, { exact: true }).tap();
      await expect(amount).toHaveValue('42');
      const normalBounds = await amount.boundingBox();
      assert.ok(normalBounds, 'The default-size source amount must have visible bounds');
      await app.screenshot('accessibility-converter-default-light-42');

      await ui('content_size', 'accessibility-extra-extra-extra-large');
      await ui('appearance', appearance);
      await ui('increase_contrast', 'enabled');
      await expect.poll(async () => (await amount.boundingBox())?.height ?? 0, { timeout: 15_000 })
        .toBeGreaterThan(normalBounds.height * 1.2);
      await expect(amount).toHaveValue('42');
      await agent.assert(`The converter is in ${appearance} appearance with very large text. The actual source number 42 and its EUR currency code are readable without clipping or overlap. The custom keypad digits remain identifiable. Judge rendered glyphs, not only accessibility labels.`, { vision: 'only' });
      await app.screenshot(`accessibility-converter-ax5-${appearance}-contrast-42-editing`);
      await amount.tap();
      await expect(amount).toHaveValue('42');
      await expect(screen.getByRole('button', 'US Dollar, 84', { exact: true })).toBeVisible();

      await amount.tap();
      for (const digit of '12345678901234') await screen.getByRole('button', digit, { exact: true }).tap();
      await expect(amount).toHaveValue('12,345,678,901,234');
      await agent.assert('The EUR source amount uses very large digits, with its ending digits 234 readable in the horizontal amount viewport. The EUR code remains separately readable, and the amount does not overlap the keypad or currency code. Horizontal overflow and partial digits at the horizontal scroll edge are allowed; tiny shrunken digits or vertically clipped digits are not.', { vision: 'only' });
      await app.screenshot('accessibility-converter-ax5-long-amount-end');
      const longAmountBounds = await amount.boundingBox();
      assert.ok(longAmountBounds, 'The long source amount must have visible bounds for horizontal exploration');
      for (let swipe = 0; swipe < 8; swipe++) {
        await screen.swipe({
          from: { x: longAmountBounds.x + longAmountBounds.width * 0.2, y: longAmountBounds.y + longAmountBounds.height * 0.35 },
          to: { x: longAmountBounds.x + longAmountBounds.width * 0.75, y: longAmountBounds.y + longAmountBounds.height * 0.35 },
        });
      }
      await expect(amount).toHaveValue('12,345,678,901,234');
      await agent.assert('The source number begins with 12 in large readable glyphs. The EUR code is separately readable. Later digits may be outside the horizontal viewport.', { vision: 'only' });
      await app.screenshot('accessibility-converter-ax5-long-amount-start');

      await app.restart();
      await screen.getByTestId('converter.source').tap();
      await expect(screen.getByTestId('currency.picker.category')).toBeVisible();
      await agent.assert(`The source currency chooser uses ${appearance} appearance with very large readable text and identifiable category/search controls. Fully visible currency names and codes are readable without overlapping or clipped glyphs; rows cut off at the scroll edge are allowed.`, { vision: 'only' });
      await app.screenshot(`accessibility-chooser-ax5-${appearance}-contrast`);
      const closeBounds = await screen.getByTestId('currency.picker.close').boundingBox();
      assert.ok(closeBounds, 'The currency chooser must expose its Close control');
      await screen.tapAt({ x: closeBounds.x + closeBounds.width / 2, y: closeBounds.y + closeBounds.height / 2 });
      await expect(screen.getByTestId('currency.picker.close')).toBeHidden();
    } else {
      await ui('content_size', 'accessibility-extra-extra-extra-large');
      await ui('appearance', appearance);
      await ui('increase_contrast', 'enabled');
    }
    await screen.getByTestId('converter.options').tap();
    const settings = screen.getByTestId('converter.settings');
    await expect(settings).toBeVisible();
    const viewport = await screen.getByLabel('Currency', { exact: true }).boundingBox();
    assert.ok(viewport, 'Menu navigation requires the actual app viewport');
    let settingsBounds = await settings.boundingBox();
    for (let swipe = 0; swipe < 4; swipe++) {
      assert.ok(settingsBounds, 'The Settings menu item must expose its actual bounds');
      if (settingsBounds.y >= viewport.y + 44
        && settingsBounds.y + settingsBounds.height <= viewport.y + viewport.height - 16) break;
      const x = Math.max(viewport.x + 12,
        Math.min(viewport.x + viewport.width - 12, settingsBounds.x + settingsBounds.width / 2));
      await screen.swipe({
        from: { x, y: viewport.y + viewport.height * 0.75 },
        to: { x, y: viewport.y + viewport.height * 0.25 },
      });
      settingsBounds = await settings.boundingBox();
    }
    assert.ok(settingsBounds && settingsBounds.y >= viewport.y + 44
      && settingsBounds.y + settingsBounds.height <= viewport.y + viewport.height - 16,
    'Settings must be fully inside the visible app viewport before tapping');
    await app.screenshot(`accessibility-options-${appearance}-${orientation}`);
    await screen.tapAt({ x: settingsBounds.x + settingsBounds.width / 2, y: settingsBounds.y + settingsBounds.height / 2 });
    await expect(screen.getByTestId('settings.theme')).toHaveAccessibleName('Theme, System');
    await expect(screen.getByTestId('settings.accent')).toHaveValue('Default');
    const settingsColors = appearance === 'light' ? 'light backgrounds and dark text' : 'dark backgrounds and light text';
    await agent.assert(`Settings has ${settingsColors}. The fully visible Theme row has legible letters without glyph collisions. Its value System is expected because it inherits the device appearance. Multiline titles and values stacked on separate lines are allowed.`, { vision: 'only' });
    await app.screenshot(`accessibility-settings-theme-ax5-${appearance}-contrast`);
    const accent = screen.getByTestId('settings.accent');
    let accentBounds = await accent.boundingBox();
    for (let swipe = 0; swipe < 8; swipe++) {
      if (accentBounds && accentBounds.y >= viewport.y + 72
        && accentBounds.y + accentBounds.height <= viewport.y + viewport.height - 16) break;
      const below = accentBounds && accentBounds.y >= viewport.y + 72;
      await screen.swipe({
        from: { x: viewport.x + viewport.width / 2, y: viewport.y + viewport.height * 0.65 },
        to: { x: viewport.x + viewport.width / 2, y: viewport.y + viewport.height * (below ? 0.55 : 0.75) },
      });
      accentBounds = await accent.count() ? await accent.boundingBox() : null;
    }
    assert.ok(accentBounds && accentBounds.y >= viewport.y + 72
      && accentBounds.y + accentBounds.height <= viewport.y + viewport.height - 16,
    'The Accent color row must be fully visible before its glyph check');
    await expect(accent).toHaveValue('Default');
    await agent.assert(`Settings has ${settingsColors}. The fully visible Accent color row and its Default value have legible letters without glyph collisions or clipping. Multiline titles and values stacked on separate lines are allowed.`, { vision: 'only' });
    await app.screenshot(`accessibility-settings-ax5-${appearance}-contrast`);

    await app.restart();
    await amount.tap();
    await screen.getByTestId('converter.history').tap();
    await agent.act('Use the History range control to choose One month. Keep Details open.');
    const history = readHistory(join(sharedDirectory(), 'history-v3-EUR-USD-30.json'));
    const latest = history.points.at(-1)!;
    const date = new Intl.DateTimeFormat('en-US', {
      year: 'numeric', month: 'short', day: 'numeric', timeZone: 'UTC',
    }).format(new Date((latest.date + 978_307_200) * 1000));
    const value = `${new Intl.NumberFormat('en-US', { maximumFractionDigits: 6 }).format(latest.value)} USD`;
    const detailsBounds = await screen.getByTestId('currency.details.EUR').boundingBox();
    assert.ok(detailsBounds, 'Details must expose its actual sheet bounds');
    const reveal = async (target: ReturnType<typeof screen.getByTestId>) => {
      for (let swipe = 0; swipe < 8; swipe++) {
        const bounds = await target.count() ? await target.boundingBox() : null;
        if (bounds && bounds.y >= detailsBounds.y + 72
          && bounds.y + bounds.height <= detailsBounds.y + detailsBounds.height - 16) return bounds;
        await screen.swipe({
          from: { x: detailsBounds.x + 8, y: detailsBounds.y + detailsBounds.height * 0.8 },
          to: { x: detailsBounds.x + 8, y: detailsBounds.y + detailsBounds.height * 0.35 },
        });
      }
      throw new Error('History content did not become fully visible inside the Details sheet');
    };
    const selectedValue = screen.getByTestId('currency.details.selectedValue');
    await reveal(selectedValue);
    await expect(selectedValue).toHaveText(value);
    await expect(screen.getByTestId('currency.details.selectedDate')).toHaveText(date);
    await agent.assert(`The selected history value ${value} and date ${date} are readable in large text without glyph collisions or clipping. The screen has ${settingsColors}.`, { vision: 'only' });
    await app.screenshot(`accessibility-history-header-ax5-${appearance}-contrast`);
    const chart = screen.getByLabel('EUR to USD exchange-rate history · One month', { exact: true }).first();
    await reveal(chart);
    await expect(chart).toBeVisible();
    await agent.assert(`The existing exchange-rate history chart is visible on ${appearance} surfaces. Its line, rate-axis numbers and displayed dates are distinguishable and readable without glyph collisions.`, { vision: 'only' });
    await app.screenshot(`accessibility-history-chart-ax5-${appearance}-contrast`);
    await screen.getByTestId('currency.details.close').tap();
  } catch (error) {
    await app.screenshot(`accessibility-${scope}-${appearance}-${orientation}-failure-before-restoration`)
      .catch(captureError => console.error('Could not capture accessibility failure before restoration', captureError));
    throw error;
  } finally {
    try {
      await ui('content_size', originalSize);
    } finally {
      try {
        await ui('appearance', originalAppearance);
      } finally {
        try {
          await ui('increase_contrast', originalContrast);
        } finally {
          await device.setOrientation('portrait');
        }
      }
    }
  }
});
