import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { fileURLToPath } from 'node:url';
import { mkdtemp, readFile, rm, writeFile } from 'node:fs/promises';
import { join } from 'node:path';

const execute = promisify(execFile);
const utility = fileURLToPath(new URL('../../../../Tools/SimulatorWidgets/widget-place.py', import.meta.url));
const stateDirectory = fileURLToPath(new URL('./.local/simulator-widgets', import.meta.url));
const kinds: Record<string, string> = {
  'Currency Calculator': 'CurrencyConverter',
  'Currency board': 'CurrencyBoard',
  'Know Your Cash': 'CurrencyCash',
  'Pocket Rate': 'CurrencyPocketRate',
  'Mental Math': 'CurrencyMentalMath',
  History: 'CurrencyHistory',
};
let placementUsed = false;
let prepared = false;

export function widgetSetupMethod() {
  const method = process.env.CURRENCY_E2E_WIDGET_SETUP ?? 'private';
  if (method !== 'gallery' && method !== 'private') throw new Error('CURRENCY_E2E_WIDGET_SETUP must be gallery or private.');
  return method;
}

async function invoke(arguments_: string[]) {
  const udid = process.env.CURRENCY_E2E_UDID?.trim();
  if (!udid) throw new Error('Widget placement requires the explicitly owned CURRENCY_E2E_UDID.');
  const { stdout } = await execute('python3', [utility, udid, ...arguments_, '--state-dir', stateDirectory], { timeout: 180_000, maxBuffer: 1_048_576 });
  const result = JSON.parse(stdout) as { status: string; timings: Record<string, number> };
  console.log(`Widget utility: ${JSON.stringify({ status: result.status, timings: result.timings })}`);
  return result;
}

export async function prepareWidgetHelper() {
  if (prepared) return;
  placementUsed = true;
  const result = await invoke(['--prepare']);
  if (result.status !== 'ready') throw new Error('Widget helper did not become ready.');
  prepared = true;
}

export async function placeWidget(title: string, family: 'Small' | 'Medium' | 'Large') {
  const kind = kinds[title];
  if (!kind) throw new Error(`No widget kind maps to ${title}.`);
  placementUsed = true;
  const result = await invoke(['com.dimasike.currency.widgets', kind, family.toLowerCase(), '--exclusive', '--replace', '--position', 'top']);
  if (result.status !== 'verified') throw new Error(`Widget placement did not verify ${kind}/${family}.`);
}

export async function revealWidget(title: string, family: 'Small' | 'Medium' | 'Large') {
  await prepareWidgetHelper();
  const kind = kinds[title];
  if (!kind) throw new Error(`No widget kind maps to ${title}.`);
  const result = await invoke(['com.dimasike.currency.widgets', kind, family.toLowerCase(), '--position', 'top']);
  if (result.status !== 'verified') throw new Error('Existing widget reveal did not verify.');
}

export async function unloadWidgetHelper() {
  if (!placementUsed) return;
  await invoke(['--unload']);
  placementUsed = false;
  prepared = false;
}

type WidgetConfiguration = { intent: { parameters: Record<string, unknown> } };

async function withWidgetConfiguration<T>(title: string, family: 'Small' | 'Medium' | 'Large', use: (configuration: WidgetConfiguration, target: string[], path: string) => Promise<T>) {
  if (widgetSetupMethod() !== 'private') throw new Error('Direct widget configuration requires private setup.');
  const kind = kinds[title];
  if (!kind) throw new Error(`No widget kind maps to ${title}.`);
  await prepareWidgetHelper();
  const temporary = await mkdtemp(join(stateDirectory, 'configuration-'));
  try {
    const path = join(temporary, 'intent.json');
    const target = ['com.dimasike.currency.widgets', kind, family.toLowerCase()];
    const exported = await invoke([...target, '--export-config', path]);
    if (exported.status !== 'configuration_exported') throw new Error('Widget configuration export did not verify.');
    const configuration = JSON.parse(await readFile(path, 'utf8')) as WidgetConfiguration;
    return await use(configuration, target, path);
  } finally {
    await rm(temporary, { recursive: true, force: true });
  }
}

export async function widgetParameters(title: string, family: 'Small' | 'Medium' | 'Large') {
  return withWidgetConfiguration(title, family, async (configuration) => configuration.intent.parameters);
}

export async function configureWidget(title: string, family: 'Small' | 'Medium' | 'Large', update: (parameters: Record<string, unknown>) => void) {
  await withWidgetConfiguration(title, family, async (configuration, target, path) => {
    update(configuration.intent.parameters);
    await writeFile(path, JSON.stringify(configuration));
    const applied = await invoke([...target, '--apply-config', path]);
    if (applied.status !== 'configuration_applied') throw new Error('Widget configuration update did not verify.');
  });
}
