/**
 * Utility script to get the contents of a specific element for multiple locales
 */
import { chromium } from '@playwright/test';

// list of locales supported by DDG apps and extensions
const locales = [
    'bg',
    'cs',
    'da',
    'de',
    'el',
    'en',
    'es',
    'et',
    'fi',
    'fr',
    'hr',
    'hu',
    'it',
    'lt',
    'lv',
    'nb',
    'nl',
    'pl',
    'pt',
    'ro',
    'ru',
    'sk',
    'sl',
    'sv',
    'tr',
];
if (process.argv.length < 4) {
    console.log('Usage: npm run get-text-for-xpath -- <URL> <XPATH>');
    process.exit(0);
}
const url = process.argv[2];
const xpath = process.argv[3];
const values = new Set();
console.log(`Checking contents of ${xpath} on ${url}`);

(async () => {
    const browser = await chromium.launch({ headless: false });

    async function checkLocale(locale: string) {
        const context = await browser.newContext({ locale });
        const page = await context.newPage();
        await page.goto(url, {
            waitUntil: 'networkidle',
            timeout: 30000,
        });

        // add extra interactions here if necessary, e.g.
        // await page.locator('.my-button').click();

        const locator = page.locator(`xpath=${xpath}`);
        const content = await locator.textContent();
        console.log(locale, content);
        values.add(content);
        await page.close();
        await context.close();
    }

    const crawls = locales.map(async (locale) => {
        try {
            await checkLocale(locale);
        } catch (e) {
            console.warn(`Failed on locale ${locale}, retrying...`, e);
            await checkLocale(locale);
        }
    });
    await Promise.all(crawls);
    await browser.close();
    console.log('Final set of strings:');
    console.log([...values]);
    console.log('Example xpath rule:');
    const containsClause = [...values].map((v) => `contains(., '${v}')`).join(' or ');
    console.log(`xpath///span[${containsClause}]`);
})();
