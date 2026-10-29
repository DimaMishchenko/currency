import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { existsSync, readFileSync } from 'node:fs';
import { join } from 'node:path';
import { setTimeout as delay } from 'node:timers/promises';
import { expect, type TestFixtures } from 'e2e';

type ReviewContext = Pick<TestFixtures, 'screen' | 'app' | 'agent'>;

export function reviewUsageCount(): number {
  const udid = process.env.CURRENCY_E2E_UDID?.trim();
  assert.ok(udid, 'Review usage must target the owned simulator');
  const directory = execFileSync('xcrun', ['simctl', 'get_app_container', udid,
    'com.dimasike.currency', 'group.com.dimasike.currency.shared'], { encoding: 'utf8' }).trim();
  const path = join(directory, 'conversion-usage.json');
  if (!existsSync(path)) return 0;
  const usage = JSON.parse(readFileSync(path, 'utf8')) as { version: number; count: number };
  assert.equal(usage.version, 1);
  assert.ok(Number.isSafeInteger(usage.count) && usage.count >= 0 && usage.count <= 3);
  return usage.count;
}

export async function completeConversion({ screen }: Pick<ReviewContext, 'screen'>, digit: '2' | '4') {
  await screen.getByRole('button', 'Edit amount in EUR', { exact: true }).tap();
  await screen.getByRole('button', digit, { exact: true }).tap();
  await expect(screen.getByRole('button', 'Edit amount in EUR', { exact: true })).toHaveValue(digit);
  await expect(screen.getByRole('button', /^US Dollar,/)).toHaveAccessibleName(`US Dollar, ${(Number(digit) * 2).toFixed(2)}`);
  await screen.getByTestId('checkmark').tap();
}

export async function expectNoReview({ screen }: Pick<ReviewContext, 'screen'>, count: number) {
  await delay(2_500);
  await expect(screen.getByRole('button', 'Not Now', { exact: true })).toBeHidden();
  assert.equal(reviewUsageCount(), count);
}

export async function dismissNativeReview({ screen, app, agent }: ReviewContext, screenshot: string) {
  await expect(screen.getByRole('button', 'Not Now', { exact: true })).toBeVisible({ timeout: 15_000 });
  await agent.assert('The native iOS App Store rating prompt for Currency is visible above the converter, with rating stars and the Not Now dismissal button.', { vision: 'only' });
  await app.screenshot(screenshot);
  await screen.getByRole('button', 'Not Now', { exact: true }).tap();
  await expect(screen.getByRole('button', 'Not Now', { exact: true })).toBeHidden();
  assert.equal(reviewUsageCount(), 0, 'The request consumes exactly one three-conversion batch');
}
