import assert from 'node:assert/strict';
import { execFile } from 'node:child_process';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { promisify } from 'node:util';
import { expect } from 'e2e';
import { test } from '../fixtures.js';
import { configureWidget, placeWidget, prepareWidgetHelper, unloadWidgetHelper, widgetParameters, widgetSetupMethod } from '../simulator-widgets.js';
import { sharedDirectory } from './history-cache.js';

test('largest-text widget tap reads captured custom Board amounts without replacing app input', {
  tags: ['extended', 'widgets', 'accessibility', 'widget-readout'],
  skip: widgetSetupMethod() === 'gallery' ? 'Requires device-targeted custom widget configuration.' : false,
}, async ({ start, app, device, screen, agent }) => {
  const udid = process.env.CURRENCY_E2E_UDID?.trim();
  assert.ok(udid, 'CURRENCY_E2E_UDID must identify this test’s owned simulator.');
  const run = promisify(execFile);
  const ui = async (setting: 'content_size' | 'appearance', value?: string) => {
    const { stdout } = await run('/usr/bin/xcrun', ['simctl', 'ui', udid, setting, ...(value ? [value] : [])], {
      encoding: 'utf8', timeout: 15_000, maxBuffer: 4096,
    });
    return stdout.trim();
  };
  const originalSize = await ui('content_size');
  const originalAppearance = await ui('appearance');
  assert.ok([
    'extra-small', 'small', 'medium', 'large', 'extra-large', 'extra-extra-large', 'extra-extra-extra-large',
    'accessibility-medium', 'accessibility-large', 'accessibility-extra-large',
    'accessibility-extra-extra-large', 'accessibility-extra-extra-extra-large',
  ].includes(originalSize), `Cannot restore unknown content size: ${originalSize}`);
  assert.ok(['light', 'dark'].includes(originalAppearance), `Cannot restore unknown appearance: ${originalAppearance}`);
  try {
    await ui('content_size', 'accessibility-extra-extra-extra-large');
    await ui('appearance', 'light');
    await prepareWidgetHelper();
    await start('ready-converter');
    await expect(screen.getByRole('button', 'Edit amount in EUR')).toHaveValue('1');
    const inputPath = join(sharedDirectory(), 'input.json');
    const savedInput = JSON.parse(readFileSync(inputPath, 'utf8'));
    await device.home();
    await device.openApp('com.apple.springboard');
    await placeWidget('Pocket Rate', 'Small');
    const pair = await widgetParameters('Pocket Rate', 'Small');
    assert.ok(pair.base && pair.comparison, 'The widget must export full canonical EUR and USD entities.');
    await placeWidget('Currency board', 'Medium');
    await configureWidget('Currency board', 'Medium', parameters => {
      parameters.base = pair.comparison;
      parameters.amount = '42.5';
      parameters.list = 'selected';
      parameters.currencies = [pair.base];
    });
    const widget = device.locator('id=Currency value=Widget');
    await expect(widget).toBeVisible();
    await agent.waitFor('The medium Currency Board on the Home Screen shows USD exactly 42.5 and EUR exactly 21.25. Decimal comma 42,5 and 21,25 is equivalent and accepted. Both codes and complete amounts are visible, with no placeholders or permission prompt.', { vision: 'only', timeout: 30_000 });
    await app.screenshot('widget-readout-custom-usd-42-5-eur-21-25');
    await widget.tap();
    await agent.waitFor('The Currency app has opened a sheet titled Widget amounts, with a Done button. It shows captured US Dollar USD 42.5 and Euro EUR 21.25 in very large text. Decimal comma 42,5 and 21,25 is equivalent and accepted. It has not opened only the ordinary converter.', { vision: 'only', timeout: 30_000 });
    await device.openApp('com.dimasike.currency', { relaunch: false });
    const dollars = screen.getByTestId('widget.readout.USD');
    const euros = screen.getByTestId('widget.readout.EUR');
    await expect(dollars).toHaveAccessibleName(/US Dollar[\s\S]*USD[\s\S]*42[.,]5/);
    await expect(euros).toHaveAccessibleName(/Euro[\s\S]*EUR[\s\S]*21[.,]25/);
    const enlargedBounds = await dollars.boundingBox();
    assert.ok(enlargedBounds, 'The captured amount row must have accessibility-text bounds.');
    await ui('content_size', 'large');
    await expect.poll(async () => (await dollars.boundingBox())?.height ?? enlargedBounds.height, { timeout: 15_000 })
      .toBeLessThan(enlargedBounds.height / 1.5);
    await expect(dollars).toBeVisible();
    const standardBounds = await dollars.boundingBox();
    assert.ok(standardBounds, 'The captured amount row must have normal-text bounds.');
    await ui('content_size', 'accessibility-extra-extra-extra-large');
    await expect.poll(async () => (await dollars.boundingBox())?.height ?? 0, { timeout: 15_000 })
      .toBeGreaterThan(standardBounds.height * 1.5);
    await agent.assert('The visible Widget amounts sheet shows very large text: US Dollar, USD, 42.5; Euro, EUR, 21.25. All labels and digits are complete and readable, with no clipping or overlap. The Done button is visible.', { vision: 'only' });
    await app.screenshot('widget-readout-largest-accessibility-text');
    await expect(dollars).toHaveAccessibleName(/42[.,]5/);
    await expect(euros).toHaveAccessibleName(/21[.,]25/);
    await screen.getByTestId('widget.readout.done').tap();
    await expect(screen.getByTestId('widget.readout.done')).toBeHidden();
    await expect(screen.getByRole('button', 'Edit amount in EUR')).toHaveValue('1');
    assert.deepEqual(JSON.parse(readFileSync(inputPath, 'utf8')), savedInput,
      'Reading captured custom widget amounts must preserve authoritative app input and favorites.');
  } finally {
    try {
      await ui('content_size', originalSize);
    } finally {
      try {
        await ui('appearance', originalAppearance);
      } finally {
        await unloadWidgetHelper();
      }
    }
  }
});
