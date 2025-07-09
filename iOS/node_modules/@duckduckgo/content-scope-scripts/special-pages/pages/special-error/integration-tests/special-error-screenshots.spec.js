import { expect, test } from '@playwright/test';
import { SpecialErrorPage } from './special-error';

const maxDiffPixels = 20;

test.describe('screenshots @screenshots', () => {
    test('SSL expired cert error', async ({ page }, workerInfo) => {
        const special = SpecialErrorPage.create(page, workerInfo);
        await special.openPage({ errorId: 'ssl.expired' });
        await expect(page).toHaveScreenshot('ssl-expired-cert.png', { maxDiffPixels });
    });

    test('SSL expired cert error with reduced motion', async ({ page }, workerInfo) => {
        const special = SpecialErrorPage.create(page, workerInfo);
        await special.reducedMotion();
        await special.openPage({ errorId: 'ssl.expired' });
        await special.showsAdvancedInfo();
        await expect(page).toHaveScreenshot('ssl-expired-cert-reduced-motion.png', { maxDiffPixels });
    });

    test('Malware warning with advanced info', async ({ page }, workerInfo) => {
        const special = SpecialErrorPage.create(page, workerInfo);
        await special.openPage({ errorId: 'malware' });
        await special.showsAdvancedInfo();
        await expect(page).toHaveScreenshot('malware-warning-advanced.png', { maxDiffPixels });
    });

    test('Phishing warning with advanced info', async ({ page }, workerInfo) => {
        const special = SpecialErrorPage.create(page, workerInfo);
        await special.openPage({ errorId: 'phishing' });
        await special.showsAdvancedInfo();
        await expect(page).toHaveScreenshot('phishing-warning-advanced.png', { maxDiffPixels });
    });

    test('Malware warning in Russian', async ({ page }, workerInfo) => {
        const special = SpecialErrorPage.create(page, workerInfo);
        await special.openPage({ errorId: 'malware', locale: 'ru' });
        await expect(page).toHaveScreenshot('malware-warning-ru.png', { maxDiffPixels });
    });

    test('Scam warning with advanced info', async ({ page }, workerInfo) => {
        const special = SpecialErrorPage.create(page, workerInfo);
        await special.openPage({ errorId: 'scam' });
        await special.showsAdvancedInfo();
        await expect(page).toHaveScreenshot('scam-warning-advanced.png', { maxDiffPixels });
    });
});
