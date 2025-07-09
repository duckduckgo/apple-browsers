#!/usr/bin/env node
import fs from 'fs';
import path from 'path';
import https from 'https';
import { encodeRules } from '../lib/encoding';
import { AutoConsentCMPRule } from '../lib/rules';

export const rulesDir = __dirname;

async function readFileJSON(filePath: string) {
    const data = await fs.promises.readFile(filePath, 'utf-8');
    return JSON.parse(data);
}

export async function buildAutoconsentRules(): Promise<AutoConsentCMPRule[]> {
    // merge rules from ./autoconsent into rules.autoconsent array
    const autoconsentDir = path.join(rulesDir, 'autoconsent');
    const files = fs.readdirSync(autoconsentDir);
    return await Promise.all(files.map((file) => readFileJSON(path.join(autoconsentDir, file))));
}

export async function buildConsentOMaticRules() {
    // fetch ConsentOMatic rule set and merge with our custom rules
    const consentOMaticCommit = '7d7fd2bd6bf2b662350b0eaeca74db6eba155efe';
    const consentOMaticUrl = `https://raw.githubusercontent.com/cavi-au/Consent-O-Matic/${consentOMaticCommit}/Rules.json`;
    const consentOMaticInclude = ['didomi.io', 'oil', 'optanon', 'quantcast2', 'springer', 'wordpressgdpr'];
    const comRules: Record<string, object> = {};
    const allComRules: Record<string, object> = await new Promise((resolve) => {
        https.get(consentOMaticUrl, (res) => {
            res.setEncoding('utf-8');
            let content = '';
            res.on('data', (data) => (content += data));
            res.on('end', () => resolve(JSON.parse(content)));
        });
    });
    consentOMaticInclude.forEach((name) => {
        comRules[name] = allComRules[name];
    });
    return comRules;
}

(async () => {
    const stringify = (rules: object) => JSON.stringify(rules);
    const autoconsent = await buildAutoconsentRules();
    const consentomatic = await buildConsentOMaticRules();
    fs.writeFile(path.join(rulesDir, 'rules.json'), stringify({ autoconsent }), () => console.log('Written rules.json'));
    fs.writeFile(path.join(rulesDir, 'consentomatic.json'), stringify({ consentomatic }), () => console.log('Written consentomatic.json'));
    fs.writeFile(path.join(rulesDir, 'compact-rules.json'), stringify(encodeRules(autoconsent)), () =>
        console.log('Written compact-rules.json'),
    );
})();
