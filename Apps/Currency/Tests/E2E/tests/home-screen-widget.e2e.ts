import { test, tapCalculatorControl } from '../widget-fixtures.js';
import { expect } from 'e2e';

test('Home Screen calculator updates the shared converter amount', { tags: ['extended', 'widgets'] }, async ({ calculator, app, agent, screen }) => {
  const dollars = calculator.getByRole('button', /^US Dollar, USD/i);
  await tapCalculatorControl(calculator, 'EUR');
  await tapCalculatorControl(calculator, 'Clear');
  await expect(dollars).toHaveValue('0');
  await tapCalculatorControl(calculator, '4');
  await expect(dollars).toHaveValue('8');
  await tapCalculatorControl(calculator, '2');
  await expect(calculator.getByRole('button', /^US Dollar, USD/i)).toHaveValue('84');
  await agent.assert('The Currency widget shows EUR with amount 42 and USD with amount 84.', { vision: 'only' });
  await app.screenshot('home-screen-widget-42-eur-84-usd');

  await app.restart();
  await expect(screen.getByTestId('converter.source')).toHaveAccessibleName(/Euro/i);
  await expect(screen.getByRole('button', 'Edit amount in EUR')).toHaveValue('42');
  await expect(screen.getByRole('button', /^US Dollar,/i)).toHaveAccessibleName('US Dollar, 84');
  await app.screenshot('converter-shared-widget-amount');
});
