import { test } from '../fixtures.js';
import { expect } from 'e2e';

test('appearance preference survives app restart', { tags: ['core'] }, async ({ start, agent, app, screen }) => {
  await start('ready-converter');
  await agent.act('Open Currency Settings from the converter Options menu. Stay on Settings.');
  const theme = screen.getByTestId('settings.theme');
  await expect(theme).toBeVisible();
  await expect(theme).toHaveAccessibleName('Theme, System');

  await theme.getByText('System').tap();
  await agent.act('Choose Dark in the open Theme menu. Stay on Settings with the theme menu closed.');
  await expect(theme).toHaveAccessibleName('Theme, Dark');
  await app.screenshot('settings-dark-theme');

  await app.restart();
  await expect(screen.getByRole('button', 'Edit amount in EUR')).toHaveValue('1');
  await expect(screen.getByRole('button', /^US Dollar,/i)).toHaveAccessibleName('US Dollar, 2');
  await agent.act('Open Currency Settings from the converter Options menu. Stay on Settings.');
  await expect(theme).toBeVisible();
  await expect(theme).toHaveAccessibleName('Theme, Dark');
  await app.screenshot('settings-dark-theme-after-restart');
});
