import assert from 'node:assert/strict';
import { execFile } from 'node:child_process';
import { mkdirSync, readFileSync, renameSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { promisify } from 'node:util';
import { expect } from 'e2e';
import { test } from '../fixtures.js';
import { configureWidget, placeWidget, prepareWidgetHelper, revealWidget, unloadWidgetHelper, widgetSetupMethod } from '../simulator-widgets.js';
import { readHistory, sharedDirectory } from './history-cache.js';

const cases = [
  { name: 'positive', first: 1.8, expected: /^\+11[.,]11%$/, display: '+11.11%' },
  { name: 'negative', first: 2.25, expected: /^[-−]11[.,]11%$/, display: '−11.11%' },
  { name: 'wide', first: 2 / 13.3456, expected: /^\+1[.,\u00a0\u202f ]234[.,]56%$/, display: '+1,234.56%' },
] as const;

for (const example of cases) {
  test(`medium History ${example.name} percentage enlarges its complete signed value at AX5`, {
    tags: ['extended', 'widgets', 'widget-larger-text'],
  }, async ({ start, app, device, screen, agent }) => {
    assert.equal(widgetSetupMethod(), 'private', 'Controlled History configuration requires device-targeted widget setup');
    const udid = process.env.CURRENCY_E2E_UDID?.trim();
    assert.ok(udid, 'CURRENCY_E2E_UDID must identify the owned simulator');
    const run = promisify(execFile);
    const ui = async (setting: string, value?: string) => (await run('/usr/bin/xcrun',
      ['simctl', 'ui', udid, setting, ...(value ? [value] : [])], { encoding: 'utf8', timeout: 15_000 })).stdout.trim();
    const original = { size: await ui('content_size'), appearance: await ui('appearance'), contrast: await ui('increase_contrast') };
    assert.match(original.size, /^(extra-small|small|medium|large|extra-large|extra-extra-large|extra-extra-extra-large|accessibility-medium|accessibility-large|accessibility-extra-large|accessibility-extra-extra-large|accessibility-extra-extra-extra-large)$/);
    assert.ok(['light', 'dark'].includes(original.appearance));
    assert.ok(['enabled', 'disabled'].includes(original.contrast));
    const { name, expected, display } = example;
    const pixelDirectory = join(process.cwd(), '.e2e', 'widget-larger-text-pixels', udid, `${Date.now()}-${name}`);
    mkdirSync(pixelDirectory, { recursive: true });
    const capture = async (size: string) => {
      await app.screenshot(`history-percentage-${name}-${size}`);
      const file = join(pixelDirectory, `${size}.png`);
      await run('/usr/bin/xcrun', ['simctl', 'io', udid, 'screenshot', file], { encoding: 'utf8', timeout: 15_000 });
      return file;
    };
    let cachePath: string | undefined;
    let originalCache: string | undefined;
    try {
      await ui('content_size', 'large');
      await ui('appearance', 'light');
      await ui('increase_contrast', 'enabled');
      await prepareWidgetHelper();
      await start('ready-converter');
      await expect(screen.getByRole('button', 'Edit amount in EUR', { exact: true })).toHaveValue('1');
      await expect(screen.getByRole('button', /^US Dollar,/i)).toHaveAccessibleName('US Dollar, 2.00');
      cachePath = join(sharedDirectory(), 'history-v3-EUR-USD-30.json');
      originalCache = readFileSync(cachePath, 'utf8');
      const history = readHistory(cachePath);
      const payload = JSON.parse(originalCache);
      payload.points[0].value = example.first;
      const temporary = `${cachePath}.larger-text.tmp`;
      writeFileSync(temporary, JSON.stringify(payload)); renameSync(temporary, cachePath);
      await device.closeApp();
      await device.openApp('com.apple.springboard');
      await placeWidget('History', 'Medium');
      await configureWidget('History', 'Medium', parameters => {
        parameters.base = { identifier: 'EUR', title: { key: 'EUR' }, subtitle: { key: 'EUR' } };
        parameters.comparison = { identifier: 'USD', title: { key: 'USD' }, subtitle: { key: 'USD' } };
        parameters.range = { identifier: 'month', value: 'month', title: { key: '1 month' } };
      });
      await revealWidget('History', 'Medium');
      const widget = device.locator('id=Currency value=Widget');
      await expect(widget).toBeVisible();
      const change = widget.getByLabel('Rate change over the selected range', { exact: true });
      const date = new Date((history.points.at(-1)!.date + 978_307_200) * 1000);
      const dates = ['en-US', 'en-GB'].map(locale => new Intl.DateTimeFormat(locale, {
        month: 'short', day: 'numeric', timeZone: 'UTC',
      }).format(date));
      const check = async () => {
        await expect(change).toHaveValue(expected, { timeout: 30_000 });
        await expect(widget.getByLabel('One month', { exact: true })).toBeVisible();
        await expect(widget.getByLabel(new RegExp(`^Rate as of (${dates.join('|')})$`))).toBeVisible();
      };
      await check();
      await agent.assert(`Read the actual text in the medium History widget. Confirm every glyph of EUR, USD, 1, 2, ${display}, ${dates.join(' or ')} and 1M is present and legible. Localized decimal/grouping separators are allowed. The displayed date intentionally has no year. The line chart is a background layer; evaluate the text glyphs themselves, not whether a graph line crosses the label's surrounding area.`, { vision: 'only' });
      const baselineBounds = await change.boundingBox();
      assert.ok(baselineBounds);
      const baselinePath = await capture('large');
      await ui('content_size', 'accessibility-extra-extra-extra-large');
      await check();
      await expect.poll(async () => (await change.boundingBox())?.height ?? 0, { timeout: 30_000 })
        .toBeGreaterThanOrEqual(baselineBounds.height * 1.8);
      await agent.assert(`The installed medium History widget retains complete readable EUR 1, USD 2, signed ${display} (localized decimal and grouping separators are allowed), ${dates.join(' or ')} (no year is drawn), 1M range and graph. The percentage is prominently enlarged, with its sign, every digit and percent symbol present. The graph intentionally fills the background; fail only if actual text glyphs are clipped, obscured or collide with other text, not merely because the graph occupies the same widget.`, { vision: 'only' });
      const enlargedBounds = await change.boundingBox();
      assert.ok(enlargedBounds);
      const enlargedPath = await capture('ax5');
      writeFileSync(`${enlargedPath}.bounds.json`, JSON.stringify({ baselinePath, enlargedPath, baselineBounds, enlargedBounds }, null, 2));
      await widget.tap();
      await agent.waitFor('The Currency app converter is visibly foreground after the actual widget tap, showing source EUR amount 1 and US Dollar 2. The Home Screen and widget are no longer foreground.', { vision: 'only', timeout: 30_000 });
      await device.openApp('com.dimasike.currency', { relaunch: false });
      await expect(screen.getByRole('button', 'Edit amount in EUR', { exact: true })).toHaveValue('1');
      await expect(screen.getByRole('button', /^US Dollar,/i)).toHaveAccessibleName('US Dollar, 2.00');
    } catch (error) {
      await app.screenshot(`history-percentage-${name}-failure-before-restoration`);
      throw error;
    } finally {
      if (cachePath && originalCache) writeFileSync(cachePath, originalCache);
      try { await ui('content_size', original.size); }
      finally {
        try { await ui('appearance', original.appearance); }
        finally {
          await ui('increase_contrast', original.contrast);
        }
      }
    }
  });
}

test.afterAll(async () => {
  await unloadWidgetHelper();
});
