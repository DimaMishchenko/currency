import { readFileSync } from 'node:fs';

const source = readFileSync(new URL('../../Modules/CurrencyApplication/Sources/CurrencyRateConfiguration.swift', import.meta.url), 'utf8');
const flag = source.match(/coinbaseEnabled\s*=\s*(true|false)\b/);
if (!flag) throw new Error('Expected the Boolean CurrencyRateConfiguration.coinbaseEnabled in source.');
export const coinbaseEnabled = flag[1] === 'true';
