import { chromium } from '@playwright/test';

const testPath = 'integration-test/data/har/duckduckgo.com/search.har';

async function init() {
    const browser = await chromium.launch();
    const context = await browser.newContext({
        recordHar: { path: testPath },
    });

    const page = await context.newPage();

    await page.goto('https://duckduckgo.com/c-s-s-says-hello');
    await page.waitForLoadState('networkidle');

    // Close context to ensure HAR is saved to disk.
    await context.close();
    await browser.close();
}

init();
