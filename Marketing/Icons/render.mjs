import fs from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { createRequire } from 'node:module';

const root = path.dirname(fileURLToPath(import.meta.url));
const repository = path.resolve(root, '../..');
const output = path.resolve(process.argv[2] ?? path.join(repository, '.validation/icons'));
const require = createRequire(import.meta.url);
const { chromium } = require(process.env.CURRENCY_PLAYWRIGHT_MODULE ?? 'playwright');
const font = (await fs.readFile(path.join(root, 'Fonts/Nunito.ttf'))).toString('base64');
const icons = JSON.parse(await fs.readFile(path.join(root, 'manifest.json'), 'utf8'));
const browser = await chromium.launch({
  headless: true,
  ...(process.env.CURRENCY_CHROMIUM_PATH ? { executablePath: process.env.CURRENCY_CHROMIUM_PATH } : {}),
});
try {
  const page = await browser.newPage({ viewport: { width: 1024, height: 1024 }, deviceScaleFactor: 1 });
  for (const icon of icons) {
    const document = path.join(output, `${icon.name}.icon`);
    await fs.cp(path.join(repository, 'Apps/Currency/App/Resources', `${icon.name}.icon`), document, { recursive: true });
    for (const [asset, source] of Object.entries(icon.layers)) {
      const svg = (await fs.readFile(path.join(root, 'Layers', source), 'utf8'))
        .replaceAll('../Fonts/Nunito.ttf', `data:font/ttf;base64,${font}`);
      await page.setContent('<style>html,body{margin:0;width:1024px;height:1024px;overflow:hidden}</style>' + svg);
      await page.evaluate(() => document.fonts.ready);
      await page.screenshot({ path: path.join(document, 'Assets', `${asset}.png`), omitBackground: true });
    }
    console.log(icon.name);
  }
} finally {
  await browser.close();
}
