import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { expect, type TestFixtures } from 'e2e';
import type { Device } from '@e2e-dev/mobile';
import { test } from '../fixtures.js';

type TutorialContext = Pick<TestFixtures, 'screen'> & { device: Device };

async function settings({ screen }: TutorialContext) {
  await expect(screen.getByRole('button', 'Edit amount in EUR')).toHaveValue('1');
  await screen.getByTestId('converter.options').tap();
  await screen.getByTestId('converter.settings').tap();
}

async function selectIcon(context: TutorialContext, icon: 'world' | 'gridBitcoin') {
  const { screen, device } = context;
  await settings(context);
  await screen.getByTestId('settings.appIcon').tap();
  const tile = screen.getByTestId(`settings.appIcon.${icon}`);
  await screen.scrollUntilVisible(tile, { direction: 'down', momentum: 'slow', timeout: 15_000 });
  if (await tile.inputValue() !== 'Selected') {
    await tile.tap();
    await device.alert('accept');
  }
  await expect(tile).toHaveValue('Selected');
}

async function openTutorialSearch({ screen }: TutorialContext) {
  const primary = screen.getByTestId('onboarding.primary');
  for (const identifier of [
    'onboarding.base', 'onboarding.recommendations', 'onboarding.homeScreen',
    'onboarding.preview.calculator', 'onboarding.guide.next',
  ]) {
    const destination = screen.getByTestId(identifier);
    await expect.poll(async () => {
      if (await destination.isVisible()) return true;
      await primary.tap({ timeout: 2_000 });
      return destination.isVisible();
    }, { timeout: 15_000 }).toBe(true);
    await expect(destination).toBeVisible();
  }
  const next = screen.getByTestId('onboarding.guide.next');
  for (let step = 0; step < 3; step += 1) await next.tap();
  await expect(screen.getByText('Find Currency', { exact: true })).toBeVisible();
}

function originalAppearance() {
  const udid = process.env.CURRENCY_E2E_UDID?.trim();
  assert.ok(udid, 'CURRENCY_E2E_UDID must identify the owned simulator');
  const appearance = execFileSync('/usr/bin/xcrun', ['simctl', 'ui', udid, 'appearance'], {
    encoding: 'utf8', timeout: 15_000,
  }).trim();
  assert.ok(appearance === 'light' || appearance === 'dark', 'The original appearance must be restorable');
  return appearance;
}

test('first-launch widget tutorial shows the default World Yen app icon', { tags: ['extended', 'widget-icon'] }, async ({ start, agent, screen, app, device }) => {
  const appearance = originalAppearance();
  const context = { screen, device };
  try {
    await device.setAppearance('light');
    await start('ready-converter');
    await selectIcon(context, 'world');
    await start('fresh-onboarding');
    await expect(screen.getByTestId('onboarding.welcome.quote')).toBeVisible();
    await openTutorialSearch(context);
    await app.screenshot('widget-tutorial-default-world-yen');
    await agent.assert('In the illustrated widget gallery search result for Currency, the app icon is the blue World design with two round overlapping currency discs: a dollar symbol and a yen/yuan symbol. Both currency symbols are visible. The icon is not a four-tile grid.', { vision: 'only' });
  } finally {
    await device.setAppearance(appearance);
  }
});

test('replayed widget tutorial shows selected Grid Bitcoin artwork in light and dark appearance', { tags: ['extended', 'widget-icon'] }, async ({ start, agent, screen, app, device }) => {
  const appearance = originalAppearance();
  const context = { screen, device };
  try {
    await device.setAppearance('light');
    await start('ready-converter');
    await selectIcon(context, 'gridBitcoin');
    await app.restart();
    await settings(context);
    await expect(screen.getByTestId('settings.appIcon')).toHaveValue('Bitcoin · Grid');
    const replay = screen.getByTestId('settings.replayOnboarding');
    await screen.scrollUntilVisible(replay, { direction: 'down', momentum: 'slow', timeout: 15_000 });
    await replay.tap();
    await openTutorialSearch(context);
    await app.screenshot('widget-tutorial-selected-grid-bitcoin-light');
    await agent.assert('In the illustrated widget gallery search result for Currency, the app icon uses the blue Grid design: four rounded tiles with a dollar symbol in the upper-left tile and a Bitcoin symbol in the lower-right tile. The other two tiles are quiet blue. It is not the World icon with overlapping round discs and does not show a yen/yuan symbol.', { vision: 'only' });
    await device.setAppearance('dark');
    await agent.waitFor('The illustrated Currency gallery result now uses the dark Grid icon: four dark rounded tiles, with a dollar symbol in the upper-left tile and Bitcoin in the lower-right tile. The tutorial itself is in dark appearance. Both symbols are clearly visible; there are no overlapping round World discs or yen/yuan symbol.', { vision: 'only', timeout: 30_000 });
    await app.screenshot('widget-tutorial-selected-grid-bitcoin-dark');
  } finally {
    try {
      await start('ready-converter');
      await selectIcon(context, 'world');
    } finally {
      await device.setAppearance(appearance);
    }
  }
});
