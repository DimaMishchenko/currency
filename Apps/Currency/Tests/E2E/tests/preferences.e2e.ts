import { test } from '../fixtures.js';
import { expect } from 'e2e';

test('settings creator footer aligns with native rows', { tags: ['core'] }, async ({ start, agent, app, screen }) => {
  await start('ready-converter');
  await agent.act('Open Options and tap Settings. Finish on the Settings screen.');
  await agent.act('Scroll Settings to the very bottom. Finish with Feedback, the centered creator portrait and the complete Version footer visible.');
  await expect(screen.getByTestId('settings.feedback')).toBeVisible();
  await expect(screen.getByText('Found a bug or have an idea? Send me your feedback.')).toBeVisible();
  await expect(screen.getByText('Made by Dimasike')).toBeVisible();
  await expect(screen.getByTestId('settings.contact.email')).toBeVisible();
  await expect(screen.getByTestId('settings.contact.website')).toBeVisible();
  await expect(screen.getByTestId('settings.contact.x')).toBeVisible();
  await agent.assert('At the bottom of Settings below the Feedback section, a centered circular portrait and Made by Dimasike appear directly on the page background. Below them are three equal-height compact Liquid Glass pill buttons with Email, globe, and X logo icons and subtle glossy edges and fully readable single-line text Email, Website and X. The left edge of Email and right edge of X align with the outer edges of the native Feedback and other Settings rows. No text is clipped or fragmented into multiple lines.', { vision: 'only' });
  await app.screenshot('settings-creator-light');
  await expect(screen.getByTestId('settings.creator.coin')).toBeVisible();
  await expect(screen.getByTestId('settings.version')).toBeVisible();
});

test('appearance preference survives app restart', { tags: ['core'] }, async ({ start, agent, app, screen }) => {
  await start('ready-converter');
  await agent.act('Open Options and tap Settings. Finish on the Settings screen showing Theme and Accent color.');
  await expect(screen.getByTestId('settings.theme')).toBeVisible();
  const theme = screen.getByTestId('settings.theme');
  await expect(theme).toBeVisible();
  await expect(theme).toHaveAccessibleName('Theme, System');

  await theme.getByText('System').tap();
  await agent.act('Choose Dark in the open Theme menu. Stay on Settings with the theme menu closed.');
  await expect(theme).toHaveAccessibleName('Theme, Dark');
  await agent.act('Scroll Settings to the very bottom to show Feedback, the creator portrait, contact buttons and Version.');
  await expect(screen.getByText('Made by Dimasike')).toBeVisible();
  await expect(screen.getByTestId('settings.contact.email')).toBeVisible();
  await expect(screen.getByTestId('settings.contact.website')).toBeVisible();
  await expect(screen.getByTestId('settings.contact.x')).toBeVisible();
  await app.screenshot('settings-dark-theme');

  await app.restart();
  await expect(screen.getByRole('button', 'Edit amount in EUR')).toHaveValue('1');
  await expect(screen.getByRole('button', /^US Dollar,/i)).toHaveAccessibleName('US Dollar, 2');
  await agent.act('Open Options and tap Settings. Finish on the Settings screen showing Theme and Accent color.');
  await expect(theme).toBeVisible();
  await expect(theme).toHaveAccessibleName('Theme, Dark');
  await app.screenshot('settings-dark-theme-after-restart');
  const version = screen.getByTestId('settings.version');
  await agent.act('Scroll Settings to the very bottom so the complete Version label is visible above the home indicator. Do not leave Settings.');
  await expect(version).toBeVisible();
  await expect(version).toHaveAccessibleName(/^Version /);
  await agent.assert('The complete Version label is readable at the bottom of Settings without clipping or overlapping system controls.', { vision: 'only' });
  await app.screenshot('settings-version');
});
