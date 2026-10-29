import assert from 'node:assert/strict';
import { readFileSync, renameSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { expect } from 'e2e';
import { assertHourlyWeek, readHistory, sharedDirectory } from './history-cache.js';
import { test } from '../fixtures.js';
import { configureWidget, placeWidget, prepareWidgetHelper, revealWidget, unloadWidgetHelper, widgetSetupMethod } from '../simulator-widgets.js';

type Quote = { value: number; observedAt?: number; retrievedAt?: number };
type Snapshot = { quotes: Record<string, Quote>; fetchedAt: number; checkedAt?: number };
type Context = { id: string; snapshot: Snapshot; base?: string; quote?: string };
const readJSON = <T>(path: string): T => JSON.parse(readFileSync(path, 'utf8')) as T;

const configurations = [
  { family: 'Small', range: 'day', title: '1 day', exclusive: true },
  { family: 'Medium', range: 'week', title: '1 week', exclusive: false },
] as const;

test('simultaneous Bitcoin History ranges converge after one widget refreshes with distinct period changes', {
  tags: ['extended', 'widgets', 'widget-history-sync'],
  skip: widgetSetupMethod() === 'gallery' ? 'Requires device-targeted widget configuration.' : false,
}, async ({ start, app, device, screen, agent }) => {
  await prepareWidgetHelper();
  for (let attempt = 0; attempt < 2; attempt++) {
    const seededHour = Math.floor(Date.now() / 3_600_000);
    await start('ready-history-sync');
    const weekly = readHistory(join(sharedDirectory(), 'history-v3-BTC-USD-7.json'));
    assertHourlyWeek(weekly);
    assert.equal(weekly.points[0]!.value, 40_000);
    assert.equal(weekly.points.at(-1)!.value, 52_500);
    const changes = weekly.points.slice(1).map((point, index) => Math.sign(point.value - weekly.points[index]!.value));
    assert.ok(changes.slice(1).filter((direction, index) => direction !== changes[index]).length >= 8);
    await expect(screen.getByRole('button', 'Edit amount in BTC')).toHaveValue('1');
    await expect(screen.getByRole('button', /^US Dollar,/i)).toHaveAccessibleName('US Dollar, 52,500.00');
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
        await agent.waitFor(`The visible ${configuration.family.toLowerCase()} Currency widget on the Home Screen has BTC and USD currency rows. The USD amount is exactly 52,500 (52 500 with a space grouping separator is equivalent). Its observation date is ${observed}; its selected range is ${isDay ? '1D and its displayed change is exactly +5.00%' : '1W and its displayed change is exactly +31.25%'} (decimal comma is equivalent). ${isDay ? 'A line chart is drawn behind the values.' : 'The weekly line chart has multiple visible rises and dips across the whole week, retaining intraday detail instead of a few straight daily segments.'} The currency codes, amount, percentage, date and range are readable without clipping. There are no placeholders, missing values or History unavailable messages.`, { vision: 'only', timeout: 30_000 });
        await app.screenshot(`widget-history-${configuration.family.toLowerCase()}-${configuration.range}-shared-latest`);
      }
      const directory = sharedDirectory();
      const contextDirectory = join(directory, 'widget-quote-contexts-v2');
      const contexts = () => readJSON<{ id: string }[]>(join(contextDirectory, 'index.json'))
        .map(({ id }) => readJSON<Context>(join(contextDirectory, `${id}.json`)));
      const matchesRate = (context: Context, rate: number) => context.base === 'BTC' && context.quote === 'USD'
        && Math.abs(context.snapshot.quotes.USD!.value / context.snapshot.quotes.BTC!.value - rate) < 0.01;
      const captured = contexts().find(context => matchesRate(context, 52_500));
      assert.ok(captured, 'The installed widgets must persist their rendered 52,500 quote context.');
      const contextPath = join(contextDirectory, `${captured.id}.json`);
      const ratePath = join(directory, 'rates.json');
      const original = readFileSync(ratePath, 'utf8');
      const newer = JSON.parse(original) as Snapshot;
      const observedAt = Date.now() / 1000 - 978_307_200;
      assert.ok(observedAt > captured.snapshot.quotes.BTC!.observedAt!);
      newer.quotes.BTC = { ...newer.quotes.BTC!, value: newer.quotes.USD!.value / 55_000, observedAt, retrievedAt: observedAt };
      newer.fetchedAt = observedAt;
      newer.checkedAt = observedAt;
      const temporary = join(directory, 'history-sync-rates.tmp');
      const writeRates = (content: string) => {
        writeFileSync(temporary, content);
        renameSync(temporary, ratePath);
      };
      try {
        writeRates(JSON.stringify(newer));
        await configureWidget('History', 'Small', parameters => {
          parameters.range = { identifier: 'month', value: 'month', title: { key: '1 month' } };
        });
        const revealInstalled = async (widget: ReturnType<typeof device.locator>) => {
          const bounds = await device.locator('role=Application').boundingBox();
          assert.ok(bounds, 'Home Screen navigation requires the simulator viewport.');
          for (const direction of [1, 1, 1, -1, -1, -1, -1, -1, -1]) {
            if (await widget.isVisible()) break;
            await screen.swipe({
              from: { x: bounds.width * (direction > 0 ? 0.8 : 0.2), y: bounds.height * 0.75 },
              to: { x: bounds.width * (direction > 0 ? 0.2 : 0.8), y: bounds.height * 0.75 },
            });
          }
          await expect(widget).toBeVisible({ timeout: 30_000 });
        };
        const month = device.locator('id=Currency value=Widget')
          .filter({ has: screen.getByLabel('One month', { exact: true }) });
        await revealInstalled(month);
        await configureWidget('History', 'Small', parameters => {
          parameters.range = { identifier: 'day', value: 'day', title: { key: '1 day' } };
        });
        for (const configuration of configurations) {
          const isDay = configuration.range === 'day';
          const widget = device.locator('id=Currency value=Widget')
            .filter({ has: screen.getByLabel(isDay ? 'One day' : 'One week', { exact: true }) });
          await revealInstalled(widget);
          await expect(widget.getByLabel('Rate change over the selected range', { exact: true }))
            .toHaveValue(isDay ? /^\+10[.,]00%$/ : /^\+37[.,]50%$/, { timeout: 30_000 });
          await agent.waitFor(`The visible ${configuration.family.toLowerCase()} Currency History widget shows BTC 1 and USD exactly 55,000 (55 000 with a space grouping separator is equivalent), ${isDay ? '1D and +10.00%' : '1W and +37.50%'} (decimal comma is equivalent), with its line chart visible and no placeholders or missing values.`, { vision: 'only', timeout: 30_000 });
          await app.screenshot(`widget-history-${configuration.family.toLowerCase()}-${configuration.range}-converged-55000`);
        }
        const updated = contexts().find(context => matchesRate(context, 55_000));
        assert.ok(updated, 'The converged widgets must persist the newer rendered quote context.');
        assert.equal(updated.snapshot.quotes.BTC!.observedAt, observedAt);
        assert.deepEqual(readJSON<Context>(contextPath), captured, 'Previously rendered quote contexts remain immutable.');
        const persisted = readJSON<Snapshot>(ratePath);
        assert.equal(persisted.checkedAt, observedAt, 'The convergence must reuse the fresh shared quote without another provider refresh.');
        assert.deepEqual(persisted.quotes.BTC, newer.quotes.BTC);
      } finally {
        writeRates(original);
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
