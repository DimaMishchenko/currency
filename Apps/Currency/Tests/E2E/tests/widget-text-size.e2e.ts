import assert from 'node:assert/strict';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { expect } from 'e2e';
import { test } from '../widget-gallery-fixtures.js';
import { tapCalculatorControl } from '../widget-fixtures.js';
import { revealWidget, unloadWidgetHelper, widgetSetupMethod } from '../simulator-widgets.js';

const examples = [
  ['History', 'Small'], ['History', 'Medium'],
  ['Currency board', 'Small'], ['Currency board', 'Medium'],
  ['Currency Calculator', 'Medium'], ['Currency Calculator', 'Large'],
] as const;

for (const [title, family] of examples) {
  test(`${family} ${title} enlarges existing text and preserves its normal interaction`, {
    tags: ['extended', 'widgets', 'widget-text-size'],
  }, async ({ installedWidget, app, device, screen, agent }) => {
    const udid = process.env.CURRENCY_E2E_UDID?.trim();
    assert.ok(udid, 'CURRENCY_E2E_UDID must identify the owned simulator');
    const run = promisify(execFile);
    const size = async (value?: string) => {
      const { stdout } = await run('/usr/bin/xcrun', ['simctl', 'ui', udid, 'content_size', ...(value ? [value] : [])], {
        encoding: 'utf8', timeout: 15_000, maxBuffer: 4096,
      });
      return stdout.trim();
    };
    const originalSize = await size();
    assert.match(originalSize, /^(extra-small|small|medium|large|extra-large|extra-extra-large|extra-extra-extra-large|accessibility-medium|accessibility-large|accessibility-extra-large|accessibility-extra-extra-large|accessibility-extra-extra-extra-large)$/);
    const name = `${title.toLowerCase().replaceAll(' ', '-')}-${family.toLowerCase()}`;
    try {
      await size('large');
      const widget = await installedWidget(title, family);
      await agent.waitFor(`The installed Currency widget on the Home Screen shows complete readable EUR 1 and USD 2, without missing data or clipped glyphs. ${title === 'History' ? 'It has a line graph, +11.11% (decimal comma equivalent), and 1M. The Home Screen title below it is Currency.' : ''}`, { vision: 'only', timeout: 30_000 });
      const range = title === 'History' ? widget.getByLabel('One month', { exact: true }) : undefined;
      const baseline = await range?.boundingBox();
      await app.screenshot(`widget-text-${name}-large`);

      if (title !== 'Currency Calculator') {
        await widget.tap();
        await agent.waitFor(title === 'History'
          ? 'The Currency app Euro details history graph is visible with 1 EUR in USD and One month selected.'
          : 'The Currency app normal converter is visible with source EUR amount 1 and US Dollar 2.', { vision: 'only', timeout: 30_000 });
        await device.openApp('com.dimasike.currency', { relaunch: false });
        if (title === 'History') {
          await expect(screen.getByTestId('currency.details.rate')).toHaveAccessibleName('1 EUR in USD');
          await expect(screen.getByTestId('currency.details.historyRange').getByRole('tab', 'One month', { exact: true })).toBeSelected();
          await screen.getByTestId('currency.details.close').tap();
        }
        await expect(screen.getByRole('button', 'Edit amount in EUR', { exact: true })).toHaveValue('1');
        await expect(screen.getByRole('button', /^US Dollar,/i)).toHaveAccessibleName('US Dollar, 2');
        await device.home();
        await device.openApp('com.apple.springboard');
        if (widgetSetupMethod() === 'private') await revealWidget(title, family);
        else await agent.act(`Show the Home Screen page containing the installed ${family} ${title} widget.`);
        await expect(widget).toBeVisible();
      }

      await size('accessibility-extra-extra-extra-large');
      if (range) {
        assert.ok(baseline, 'The range label must have native bounds before text enlargement');
        await expect.poll(async () => (await range.boundingBox())?.height ?? 0, { timeout: 30_000 })
          .toBeGreaterThan(baseline.height);
      }
      await agent.waitFor(`The installed Currency widget on the Home Screen has readable EUR 1 and USD 2 after larger text was selected. Judge actual drawn glyphs: both complete currency codes and amounts must be visible without clipping or collisions between labels. ${title === 'Currency Calculator' ? 'Every keypad label remains readable inside its button.' : title === 'History' ? 'The percentage change and 1M range remain readable, with the graph present behind the text as designed.' : 'The original currency rows remain visible.'}`, { vision: 'only', timeout: 30_000 });
      await app.screenshot(`widget-text-${name}-ax5`);

      if (title === 'Currency Calculator' && family === 'Medium') {
        await tapCalculatorControl(widget, 'EUR');
        await tapCalculatorControl(widget, 'Clear');
        await tapCalculatorControl(widget, '4');
        await tapCalculatorControl(widget, '2');
        await expect(widget.getByRole('button', /^US Dollar, USD/i)).toHaveValue('84', { timeout: 30_000 });
        await agent.assert('The installed Currency widget shows complete readable EUR 42 and USD 84, with its existing keypad visible and no clipped glyphs.', { vision: 'only' });
        await app.restart();
        await expect(screen.getByRole('button', 'Edit amount in EUR', { exact: true })).toHaveValue('42');
        await expect(screen.getByRole('button', /^US Dollar,/i)).toHaveAccessibleName('US Dollar, 84');
      } else if (title !== 'Currency Calculator') {
        await widget.tap();
        await agent.waitFor(title === 'History'
          ? 'The Currency app Euro details history graph is visible with 1 EUR in USD and One month selected.'
          : 'The Currency app normal converter is visible with source EUR amount 1 and US Dollar 2. Its normal amount editing control is present.', { vision: 'only', timeout: 30_000 });
        await device.openApp('com.dimasike.currency', { relaunch: false });
        if (title === 'History') {
          await expect(screen.getByTestId('currency.details.rate')).toHaveAccessibleName('1 EUR in USD');
          await expect(screen.getByTestId('currency.details.historyRange').getByRole('tab', 'One month', { exact: true })).toBeSelected();
          await screen.getByTestId('currency.details.close').tap();
        }
        await expect(screen.getByRole('button', 'Edit amount in EUR', { exact: true })).toHaveValue('1');
        await expect(screen.getByRole('button', /^US Dollar,/i)).toHaveAccessibleName('US Dollar, 2');
      }
    } catch (error) {
      await app.screenshot(`widget-text-${name}-failure-before-restoration`);
      throw error;
    } finally {
      await size(originalSize);
    }
  });
}

test.afterAll(async () => {
  await unloadWidgetHelper();
});
