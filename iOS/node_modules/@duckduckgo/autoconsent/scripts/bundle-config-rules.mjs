import fs from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

if (process.argv.length !== 3) {
    console.log('Usage: npm run bundle-config-rules path/to/privacy-configuration');
    process.exit(0);
}

const privacyConfigPath = process.argv[2];

const bundleLocations = [
    // join(privacyConfigPath, 'features', 'autoconsent.json'),
    join(privacyConfigPath, 'overrides', 'macos-override.json'),
];

const compactRules = JSON.parse(fs.readFileSync(join(dirname(fileURLToPath(import.meta.url)), '../rules/compact-rules.json'), 'utf-8'));

for (const location of bundleLocations) {
    const config = JSON.parse(fs.readFileSync(location, 'utf-8'));
    if (location.endsWith('autoconsent.json')) {
        // global config
        config.settings.compactRuleList = compactRules;
    } else {
        // platform override
        config.features.autoconsent.settings.compactRuleList = compactRules;
    }
    // generate standard pretty-printed output
    const outputData = JSON.stringify(config, undefined, 4);
    fs.writeFileSync(location, outputData);
}
