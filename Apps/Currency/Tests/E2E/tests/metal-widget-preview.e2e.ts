import { expect } from 'e2e';
import { test } from '../fixtures.js';

test('onboarding replay preserves grams in calculator and board previews', { tags: ['extended', 'metal-preview'] }, async ({ start, screen, agent, app }) => {
  await start('ready-metals');
  await screen.getByTestId('converter.options').tap();
  await screen.getByTestId('converter.settings').tap();
  await screen.getByTestId('settings.metalUnit').getByText('Troy ounces').tap();
  await screen.getByTestId('settings.metalUnit.gram').tap();
  await agent.act('Scroll down Settings until the Replay onboarding row is visible. Stay in Settings and do not tap the row yet.');
  await screen.getByTestId('settings.replayOnboarding').tap();
  await agent.act('Advance through replay onboarding to the widget showcase. Keep EUR as the base and keep USD and Gold (XAU) as destinations. Skip optional location setup. Stop when the Currency Calculator preview and widget size controls are visible; do not edit the preview or finish onboarding.');
  await expect(screen.getByTestId('onboarding.preview.calculator')).toBeVisible();
  await agent.assert('The Currency Calculator preview visibly shows EUR 100, USD 200, and Gold/XAU exactly 31.1034768 with measurement g. It does not show troy oz.', { vision: 'only' });
  await app.screenshot('replay-calculator-metal-grams');
  await screen.getByTestId('onboarding.widget.board').tap();
  await expect(screen.getByTestId('onboarding.preview.board')).toBeVisible();
  await agent.assert('The Currency Board preview visibly shows EUR 100, USD 200, and Gold/XAU exactly 31.1034768 with measurement g. It does not show troy oz.', { vision: 'only' });
  await app.screenshot('replay-board-metal-grams');
});
