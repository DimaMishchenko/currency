import { createWidgetController, type WidgetController, type WidgetTarget } from 'widgetctl';
import { fileURLToPath } from 'node:url';

const kinds: Record<string, string> = {
  'Currency Calculator': 'CurrencyConverter',
  'Currency board': 'CurrencyBoard',
  'Know Your Cash': 'CurrencyCash',
  'Pocket Rate': 'CurrencyPocketRate',
  'Mental Math': 'CurrencyMentalMath',
  History: 'CurrencyHistory',
};
let controller: WidgetController | undefined;
let placementUsed = false;
let prepared = false;

function widgets() {
  if (controller) return controller;
  const udid = process.env.CURRENCY_E2E_UDID?.trim();
  if (!udid) throw new Error('Widget setup requires the explicitly owned CURRENCY_E2E_UDID.');
  controller = createWidgetController({
    udid,
    stateDirectory: fileURLToPath(new URL('./.local/simulator-widgets', import.meta.url)),
    onResult: ({ status, timings }) => console.log(`Widget utility: ${JSON.stringify({ status, timings })}`),
  });
  return controller;
}

function target(title: string, family: 'Small' | 'Medium' | 'Large'): WidgetTarget {
  const kind = kinds[title];
  if (!kind) throw new Error(`No widget kind maps to ${title}.`);
  return { extension: 'com.dimasike.currency.widgets', kind, size: family.toLowerCase() as WidgetTarget['size'] };
}

export function widgetSetupMethod() {
  const method = process.env.CURRENCY_E2E_WIDGET_SETUP ?? 'private';
  if (method !== 'gallery' && method !== 'private') throw new Error('CURRENCY_E2E_WIDGET_SETUP must be gallery or private.');
  return method;
}

export async function prepareWidgetHelper() {
  if (prepared) return;
  placementUsed = true;
  await widgets().prepare();
  prepared = true;
}

export async function placeWidget(title: string, family: 'Small' | 'Medium' | 'Large') {
  placementUsed = true;
  await widgets().ensure(target(title, family), { exclusive: true, replace: true, position: 'top' });
}

export async function revealWidget(title: string, family: 'Small' | 'Medium' | 'Large') {
  await prepareWidgetHelper();
  await widgets().ensure(target(title, family), { position: 'top' });
}

export async function unloadWidgetHelper() {
  if (!placementUsed) return;
  await widgets().release();
  placementUsed = false;
  prepared = false;
}

export async function widgetParameters(title: string, family: 'Small' | 'Medium' | 'Large'): Promise<Record<string, unknown>> {
  if (widgetSetupMethod() !== 'private') throw new Error('Direct widget configuration requires private setup.');
  await prepareWidgetHelper();
  return (await widgets().exportConfiguration(target(title, family))).intent.parameters;
}

export async function configureWidget(title: string, family: 'Small' | 'Medium' | 'Large', update: (parameters: Record<string, unknown>) => void) {
  if (widgetSetupMethod() !== 'private') throw new Error('Direct widget configuration requires private setup.');
  await prepareWidgetHelper();
  const selected = target(title, family);
  const configuration = await widgets().exportConfiguration(selected);
  update(configuration.intent.parameters);
  await widgets().applyConfiguration(selected, configuration);
}
