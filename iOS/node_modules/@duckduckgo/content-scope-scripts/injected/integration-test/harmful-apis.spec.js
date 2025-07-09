import { test, expect } from '@playwright/test';
import { ResultsCollector } from './page-objects/results-collector.js';

const HTML = '/harmful-apis/index.html';
const CONFIG = './integration-test/test-pages/harmful-apis/config/apis.json';

test.skip('Harmful APIs protections', async ({ page }, testInfo) => {
    const collector = ResultsCollector.create(page, testInfo.project.use);
    await collector.load(HTML, CONFIG);

    for (const button of await page.getByTestId('user-gesture-button').all()) {
        await button.click();
    }
    const results = await collector.results(async () => {
        await page.getByTestId('render-results').click();
    });

    // note that if protections are disabled, the browser will show a device selection pop-up, which will never be dismissed

    [
        'deviceOrientation',
        'GenericSensor',
        'UaClientHints',
        'NetworkInformation',
        'getInstalledRelatedApps',
        'FileSystemAccess',
        'WindowPlacement',
        'WebBluetooth',
        'WebUsb',
        'WebSerial',
        'WebHid',
        'WebMidi',
        'IdleDetection',
        'WebNfc',
        'StorageManager',
    ].forEach((name) => {
        for (const result of results[name]) {
            expect(result.result).toEqual(result.expected);
        }
    });
});
