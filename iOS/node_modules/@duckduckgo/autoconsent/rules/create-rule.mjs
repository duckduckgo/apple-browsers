#!/usr/bin/env node
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';
import readline from 'readline';

const rulesDir = path.dirname(fileURLToPath(import.meta.url));
const testsDir = path.join(rulesDir, '../tests');
const rl = readline.createInterface({ input: process.stdin, output: process.stdout });
const prompt = (query) => new Promise((resolve) => rl.question(query, resolve));

(async () => {
    const name = await prompt('New rule name: ');
    const filename = `autoconsent/${name}.json`;
    const rule = {
        name,
        vendorUrl: 'https://unknown',
        cosmetic: false,
        runContext: {
            main: true,
            frame: false,
            urlPattern: '',
        },
        prehideSelectors: [],
        detectCmp: [{ exists: '#TODO' }],
        detectPopup: [{ visible: '#TODO' }],
        optIn: [{ waitForThenClick: '#Accept' }],
        optOut: [{ waitForThenClick: '#Reject' }],
        test: [{ cookieContains: 'TODO' }],
    };
    const ruleString = JSON.stringify(rule, undefined, 4);
    const testString = `import generateCMPTests from "../playwright/runner";

generateCMPTests('${name}', [
  // TODO: Add test URLs here
]);
`;
    console.log('Writing rule to', filename);
    await fs.promises.writeFile(path.join(rulesDir, filename), ruleString);
    console.log('Writing test to', `tests/${name}.spec.ts`);
    await fs.promises.writeFile(path.join(testsDir, `${name}.spec.ts`), testString);
    rl.close();
})();
