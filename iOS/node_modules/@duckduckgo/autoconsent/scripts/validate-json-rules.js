const Ajv = require('ajv').default;
const fs = require('fs');
const path = require('path');
const schemaGenerator = require('ts-json-schema-generator');

function createGenerator() {
    try {
        return schemaGenerator.createGenerator({
            path: path.join(__dirname, '../lib/rules.ts'),
            type: 'AutoConsentCMPRule',
        });
    } catch (e) {
        console.error(e.diagnostic);
        throw e;
    }
}

function formatErrors(errors) {
    if (!Array.isArray(errors)) {
        return '';
    }

    return errors.map((item) => `${item.instancePath}: ${item.message}`).join(', ');
}

const ajv = new Ajv({ allowUnionTypes: true });
const schema = createGenerator().createSchema('AutoConsentCMPRule');
const validator = ajv.compile(schema);

const rulesDir = path.join(__dirname, '../rules/autoconsent');
const ruleFiles = fs.readdirSync(rulesDir).filter((f) => f.endsWith('.json'));

for (const ruleFile of ruleFiles) {
    const rulePath = path.join(rulesDir, ruleFile);
    const ruleJson = JSON.parse(fs.readFileSync(rulePath, 'utf8'));

    const valid = validator(ruleJson);
    if (!valid) {
        console.error(`Validation failed for ${ruleFile}:`);
        console.error(formatErrors(validator.errors));
        process.exit(1);
    }
}

console.log('All rules look good!');
