import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { readFileSync } from 'node:fs';

export type SavedHistory = {
  points: { date: number; value: number }[];
  fetchedAt: number;
  source: {
    provider: { coinMetrics?: object };
    observation: string;
    conversion?: { base: string; quote: string; value: number; published: string };
  };
};

export function sharedDirectory(): string {
  const udid = process.env.CURRENCY_E2E_UDID!;
  return execFileSync('xcrun', ['simctl', 'get_app_container', udid, 'com.dimasike.currency', 'group.com.dimasike.currency.shared'], { encoding: 'utf8' }).trim();
}

export function readHistory(file: string): SavedHistory {
  return JSON.parse(readFileSync(file, 'utf8'));
}

export function assertHourlyWeek(history: SavedHistory, now = Date.now()): void {
  assert.ok(history.source.provider.coinMetrics, 'Weekly observations must come from Coin Metrics.');
  assert.equal(history.source.observation, 'hourlyReference');
  assert.ok(history.points.length >= 160, 'A week must retain hourly detail.');
  const first = history.points[0]!;
  const last = history.points.at(-1)!;
  assert.ok(last.date - first.date >= 163 * 3600, 'The graph must span nearly seven complete days.');
  assert.ok(last.date - first.date <= 169 * 3600);
  const current = now / 1000 - 978_307_200;
  assert.ok(first.date <= current - 166 * 3600, 'The chart must include the start of the week.');
  assert.ok(first.date >= current - 170 * 3600);
  assert.ok(last.date >= current - 3 * 3600, 'The last hourly observation must be recent.');
  assert.ok(last.date <= current + 60);
  assert.ok(history.points.every(point => Number.isFinite(point.value) && point.value > 0));
  assert.ok(new Set(history.points.map(point => point.value)).size > 2, 'The chart must retain price changes.');
  for (let index = 1; index < history.points.length; index++) {
    const gap = history.points[index]!.date - history.points[index - 1]!.date;
    assert.ok(gap > 0 && gap <= 3 * 3600, 'Hourly observations must be ordered without long gaps.');
  }
}
