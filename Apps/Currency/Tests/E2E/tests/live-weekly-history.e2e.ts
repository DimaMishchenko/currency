import assert from 'node:assert/strict';
import { existsSync, unlinkSync } from 'node:fs';
import { join } from 'node:path';
import { expect } from 'e2e';
import { test } from '../fixtures.js';
import { assertHourlyWeek, readHistory, sharedDirectory } from './history-cache.js';

for (const quote of ['USD', 'EUR'] as const) {
  test(`real ${quote} weekly Bitcoin history retains hourly detail after relaunch`, {
    tags: ['extended', 'live-providers', 'weekly-history'],
  }, async ({ start, app, device, screen, agent }) => {
    await start('ready-crypto');
    if (quote === 'EUR') {
      await agent.act('Open the source currency picker. Search EUR, select Euro, and return to the converter without editing the amount.');
    }
    const directory = sharedDirectory();
    const weekPath = join(directory, `history-v3-BTC-${quote}-7.json`);
    await device.closeApp();
    for (const file of [join(directory, 'rates.json'), weekPath]) {
      if (existsSync(file)) unlinkSync(file);
      assert.equal(existsSync(file), false);
    }
    const started = Date.now();
    const openLive = () => device.openApp('com.dimasike.currency', {
      relaunch: true,
      launchArguments: ['-AppleLanguages', '(en)', '-AppleLocale', 'en_US'],
    });
    await openLive();
    await expect(screen.getByRole('button', `Edit amount in ${quote}`)).toHaveValue('1');
    await agent.act('Long-press the Bitcoin destination currency row, then choose Details & history in its context menu.');
    await expect(screen.getByTestId('currency.details.BTC')).toBeVisible();
    await expect(screen.getByTestId('currency.details.rate')).toHaveAccessibleName(`1 BTC in ${quote}`);
    const week = screen.getByTestId('currency.details.historyRange').getByRole('tab', 'One week', { exact: true });
    await week.tap();
    await expect(week).toBeSelected();
    const source = screen.getByTestId('currency.details.sourceDisclosure');
    await expect(source.filter({ hasText: /Coin Metrics.*hourly reference prices/i })).toBeVisible();
    for (let attempt = 0; attempt < 180 && !existsSync(weekPath); attempt++) {
      await new Promise(resolve => setTimeout(resolve, 500));
    }
    assert.ok(existsSync(weekPath), 'The production hourly provider must persist a complete weekly chart.');
    const savedWeek = readHistory(weekPath);
    assertHourlyWeek(savedWeek);
    assert.ok((savedWeek.fetchedAt + 978_307_200) * 1000 >= started);
    if (quote === 'EUR') {
      assert.equal(savedWeek.source.conversion?.base, 'USD');
      assert.equal(savedWeek.source.conversion?.quote, 'EUR');
      assert.ok(Number(savedWeek.source.conversion?.value) > 0);
      assert.match(savedWeek.source.conversion!.published, /^\d{4}-\d{2}-\d{2}$/);
    } else {
      assert.equal(savedWeek.source.conversion, undefined);
    }
    await agent.waitFor(`The Bitcoin ${quote} 1W chart shows a price line across the whole week with visible hourly price variations, readable values and hourly Coin Metrics source credit. It has no Loading history, History unavailable or placeholder dashes.`, { vision: 'only', timeout: 30_000 });
    await app.screenshot(`live-phone-bitcoin-${quote.toLowerCase()}-hourly-week`);
    const fetchedHour = Math.floor((savedWeek.fetchedAt + 978_307_200) / 3600);
    await openLive();
    await expect(screen.getByRole('button', `Edit amount in ${quote}`)).toHaveValue('1');
    await agent.act('Long-press the Bitcoin destination currency row, then choose Details & history in its context menu.');
    await week.tap();
    await expect(week).toBeSelected();
    await expect(source.filter({ hasText: /Coin Metrics.*hourly reference prices/i })).toBeVisible();
    await agent.waitFor(`After relaunch, the Bitcoin ${quote} 1W chart retains its detailed weekly price trend and readable values with no Loading history, History unavailable or placeholder dashes.`, { vision: 'only', timeout: 30_000 });
    const restartedWeek = readHistory(weekPath);
    assertHourlyWeek(restartedWeek);
    if (fetchedHour === Math.floor(Date.now() / 3_600_000)) {
      assert.equal(restartedWeek.fetchedAt, savedWeek.fetchedAt);
      assert.deepEqual(restartedWeek.points, savedWeek.points);
      assert.deepEqual(restartedWeek.source, savedWeek.source);
    } else {
      assert.ok(restartedWeek.fetchedAt >= savedWeek.fetchedAt);
      assert.ok(restartedWeek.points.at(-1)!.date >= savedWeek.points.at(-1)!.date);
    }
    await app.screenshot(`live-phone-bitcoin-${quote.toLowerCase()}-relaunch-preserves-hourly-week`);
  });
}
