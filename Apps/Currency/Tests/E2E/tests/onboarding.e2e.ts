import { test } from '../fixtures.js';
import { expect } from 'e2e';

test('onboarding keeps currency choices when going back and after restart', { tags: ['core'] }, async ({ app, agent, start, screen }) => {
  await start('fresh-onboarding');
  await expect(screen.getByTestId('onboarding.welcome.quote')).toBeVisible();

  await agent.act('Advance from welcome to choosing a base currency. Open More currencies, scrolling the popular currencies rail horizontally if necessary. Search CHF in the picker and select Swiss Franc. Stay on the base currency screen with CHF selected.');
  await expect(screen.getByTestId('onboarding.base')).toBeVisible();
  await expect(screen.getByTestId('onboarding.base')).toHaveValue(/CHF/);

  await agent.act('Continue to destination currencies and select exactly Euro (EUR) and US Dollar (USD). Read each recommendation container accessibility value: both must say Selected, not Not selected. Tap the nested currency button only if its container is Not selected. Stay on the destination selection screen.');
  await expect(screen.getByTestId('onboarding.recommendations')).toBeVisible();
  await expect(screen.getByTestId('onboarding.recommendation.EUR')).toHaveValue('Selected');
  await expect(screen.getByTestId('onboarding.recommendation.USD')).toHaveValue('Selected');

  await agent.act('Go back to the base currency screen without changing any currency choices.');
  await expect(screen.getByTestId('onboarding.base')).toBeVisible();
  await expect(screen.getByTestId('onboarding.base')).toHaveValue(/CHF/);

  await agent.act('Tap the primary Continue button on the base currency screen to advance to destination currencies. Keep CHF as the base and keep the existing EUR and USD selections.');
  await expect(screen.getByTestId('onboarding.recommendations')).toBeVisible();
  await expect(screen.getByTestId('onboarding.recommendation.EUR')).toHaveValue('Selected');
  await expect(screen.getByTestId('onboarding.recommendation.USD')).toHaveValue('Selected');
  await app.screenshot('onboarding-preserved-currency-choices');

  await agent.act('Finish onboarding with the current CHF base and EUR and USD destinations. Skip optional location and widget setup, then use Get started to reach the converter.');
  await expect(screen.getByTestId('onboarding.primary')).toBeHidden();
  await expect(screen.getByTestId('converter.source')).toHaveAccessibleName(/Swiss Franc/i);
  await expect(screen.getByRole('button', /^Euro,/i)).toBeVisible();
  await expect(screen.getByRole('button', /^US Dollar,/i)).toBeVisible();
  await expect(screen.getByTestId('onboarding.welcome.quote')).toBeHidden();

  await app.restart();
  await expect(screen.getByTestId('onboarding.primary')).toBeHidden();
  await expect(screen.getByTestId('converter.source')).toHaveAccessibleName(/Swiss Franc/i);
  await expect(screen.getByRole('button', /^Euro,/i)).toBeVisible();
  await expect(screen.getByRole('button', /^US Dollar,/i)).toBeVisible();
  await expect(screen.getByTestId('onboarding.welcome.quote')).toBeHidden();
  await app.screenshot('onboarding-persisted-after-restart');
});
