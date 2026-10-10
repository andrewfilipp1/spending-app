// Usage: npm run release -- 1.1.0
// Sets the version in sw.js, js/version.js and package.json. A changed sw.js is what
// makes installed apps download the new files and show "update available".
import { readFileSync, writeFileSync } from 'node:fs';

const v = process.argv[2];
if (!/^\d+\.\d+\.\d+$/.test(v || '')) {
  console.error('Usage: npm run release -- <major.minor.patch>');
  process.exit(1);
}
const edit = (file, re, repl) => {
  const src = readFileSync(file, 'utf8');
  if (!re.test(src)) throw new Error(`version not found in ${file}`);
  writeFileSync(file, src.replace(re, repl));
};
edit('sw.js', /const VERSION = '[^']*';/, `const VERSION = '${v}';`);
edit('js/version.js', /APP_VERSION = '[^']*';/, `APP_VERSION = '${v}';`);
edit('package.json', /"version": "[^"]*"/, `"version": "${v}"`);
console.log(`Version set to ${v}`);
