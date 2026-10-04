import { expect } from 'e2e';
import { test } from '../fixtures.js';
import { deviceProfile } from '../device-profile.js';

test('converted amount and currency choices survive restart', { tags: ['core'] }, async ({ start, app, agent, screen, device }) => {
  await start('ready-converter');
  const amount = screen.getByRole('button', 'Edit amount in EUR');
  const dollars = screen.getByRole('button', /^US Dollar,/i);
  await expect(screen.getByTestId('onboarding.primary')).toBeHidden();
  await expect(screen.getByTestId('converter.source')).toHaveAccessibleName(/Euro/i);
  await expect(amount).toHaveValue('1');
  await expect(dollars).toHaveAccessibleName('US Dollar, 2');

  await agent.act('Replace the Euro source amount with exactly 42 using the calculator keypad: enter 4 then 2. Finish with the keypad toolbar checkmark if it is shown. Stay on the converter.');
  await expect(amount).toHaveValue('42');
  await expect(dollars).toHaveAccessibleName('US Dollar, 84');

  if (deviceProfile === 'duo-open' || deviceProfile === 'duo-closed') {
    const poses = deviceProfile === 'duo-open' ? ['closed', 'open'] as const : ['open', 'closed'] as const;
    for (const pose of poses) {
      await device.fold(pose);
      await device.setOrientation(pose === 'open' ? 'landscape-left' : 'portrait');
      await expect(amount).toHaveValue('42');
      await expect(dollars).toHaveAccessibleName('US Dollar, 84');
      await app.screenshot(`converter-duo-${pose}-42-eur-84-usd`);
    }
  }

  await app.restart();
  await expect(screen.getByTestId('onboarding.primary')).toBeHidden();
  await expect(screen.getByTestId('converter.source')).toHaveAccessibleName(/Euro/i);
  await expect(amount).toHaveValue('42');
  await expect(dollars).toHaveAccessibleName('US Dollar, 84');
  await app.screenshot('converter-persisted-42-eur-84-usd');
});
