import { test as base } from '@playwright/test';
import { createConfiguredDbpTest } from './fixtures';
import {
    createGetRecaptchaInfoAction,
    createSolveRecaptchaAction,
    createGetImageCaptchaInfoAction,
    createSolveImageCaptchaAction,
    createGetCloudFlareCaptchaInfoAction,
    createSolveCloudFlareCaptchaAction,
} from '../mocks/broker-protection/captcha.js';
import { BROKER_PROTECTION_CONFIGS } from './tests-config.js';

const test = createConfiguredDbpTest(base);

test.describe('Broker Protection Captcha', () => {
    test.describe('recaptcha2', () => {
        const recaptchaTargetPage = 're-captcha.html';
        const recaptchaResponseSelector = '#g-recaptcha-response';

        test.describe('getCaptchaInfo', () => {
            test('returns the expected response for the correct action data', async ({ createConfiguredDbp }) => {
                const dbp = await createConfiguredDbp(BROKER_PROTECTION_CONFIGS.default);
                await dbp.navigatesTo(recaptchaTargetPage);
                await dbp.receivesInlineAction(createGetRecaptchaInfoAction());
                const sucessResponse = await dbp.getSuccessResponse();

                dbp.isCaptchaMatch(sucessResponse, { captchaType: 'recaptcha2', targetPage: recaptchaTargetPage });
            });

            test('returns the expected response for the correct action data without the "captchaType" field', async ({
                createConfiguredDbp,
            }) => {
                const dbp = await createConfiguredDbp(BROKER_PROTECTION_CONFIGS.default);
                await dbp.navigatesTo(recaptchaTargetPage);
                await dbp.receivesInlineAction(createGetRecaptchaInfoAction({ captchaType: undefined }));
                const sucessResponse = await dbp.getSuccessResponse();

                dbp.isCaptchaMatch(sucessResponse, { captchaType: 'recaptcha2', targetPage: recaptchaTargetPage });
            });

            test('returns the expected type when the "captchaType" field does not match the detected captcha type', async ({
                createConfiguredDbp,
            }) => {
                const dbp = await createConfiguredDbp(BROKER_PROTECTION_CONFIGS.default);
                await dbp.navigatesTo(recaptchaTargetPage);
                await dbp.receivesInlineAction(createGetRecaptchaInfoAction({ captchaType: 'recaptchaEnterprise' }));
                const sucessResponse = await dbp.getSuccessResponse();

                dbp.isCaptchaMatch(sucessResponse, { captchaType: 'recaptcha2', targetPage: recaptchaTargetPage });
            });

            test('returns an error response for an action data with an invalid "captchaType" field', async ({ createConfiguredDbp }) => {
                const dbp = await createConfiguredDbp(BROKER_PROTECTION_CONFIGS.default);
                await dbp.navigatesTo(recaptchaTargetPage);
                await dbp.receivesInlineAction(createGetRecaptchaInfoAction({ captchaType: 'invalid' }));

                await dbp.isCaptchaError();
            });
        });

        test.describe('solveCaptchaInfo', () => {
            test('solves the captcha for the correct action data', async ({ createConfiguredDbp }) => {
                const dbp = await createConfiguredDbp(BROKER_PROTECTION_CONFIGS.default);
                await dbp.navigatesTo(recaptchaTargetPage);
                await dbp.receivesInlineAction(createSolveRecaptchaAction());
                dbp.getSuccessResponse();

                await dbp.isCaptchaTokenFilled(recaptchaResponseSelector);
            });

            test('solves the captcha for the correct action data without the "captchaType" field', async ({ createConfiguredDbp }) => {
                const dbp = await createConfiguredDbp(BROKER_PROTECTION_CONFIGS.default);
                await dbp.navigatesTo(recaptchaTargetPage);
                await dbp.receivesInlineAction(createSolveRecaptchaAction({ captchaType: undefined }));
                dbp.getSuccessResponse();

                await dbp.isCaptchaTokenFilled(recaptchaResponseSelector);
            });

            test('solves the captcha for an action data when the "captchaType" field does not match the detected captcha type', async ({
                createConfiguredDbp,
            }) => {
                const dbp = await createConfiguredDbp(BROKER_PROTECTION_CONFIGS.default);
                await dbp.navigatesTo(recaptchaTargetPage);
                await dbp.receivesInlineAction(createSolveRecaptchaAction({ captchaType: 'recaptchaEnterprise' }));
                dbp.getSuccessResponse();

                await dbp.isCaptchaTokenFilled(recaptchaResponseSelector);
            });

            test('returns an error response for an action data with an invalid "captchaType" field', async ({ createConfiguredDbp }) => {
                const dbp = await createConfiguredDbp(BROKER_PROTECTION_CONFIGS.default);
                await dbp.navigatesTo(recaptchaTargetPage);
                await dbp.receivesInlineAction(createSolveRecaptchaAction({ captchaType: 'invalid' }));

                await dbp.isCaptchaError();
            });
        });

        test('remove query params from captcha url', async ({ createConfiguredDbp }) => {
            const dbp = await createConfiguredDbp(BROKER_PROTECTION_CONFIGS.default);
            await dbp.navigatesTo('re-captcha.html?fname=john&lname=smith');
            await dbp.receivesInlineAction(createGetRecaptchaInfoAction());
            const sucessResponse = await dbp.getSuccessResponse();

            dbp.isQueryParamRemoved(sucessResponse);
        });
    });

    test.describe('image captcha', () => {
        const imageCaptchaTargetPage = 'image-captcha.html';
        const imageCaptchaResponseSelector = '#svgCaptchaInputId';

        test.describe('getCaptchaInfo', () => {
            test('returns the expected response for the correct action data', async ({ createConfiguredDbp }) => {
                const dbp = await createConfiguredDbp(BROKER_PROTECTION_CONFIGS.default);
                await dbp.navigatesTo(imageCaptchaTargetPage);
                await dbp.receivesInlineAction(createGetImageCaptchaInfoAction({ selector: '#svg-captcha-rendering svg' }));
                const sucessResponse = await dbp.getSuccessResponse();
                dbp.isCaptchaMatch(sucessResponse, { captchaType: 'image', targetPage: imageCaptchaTargetPage });
            });

            test('returns an error response when the selector is not an svg or image tag', async ({ createConfiguredDbp }) => {
                const dbp = await createConfiguredDbp(BROKER_PROTECTION_CONFIGS.default);
                await dbp.navigatesTo(imageCaptchaTargetPage);
                await dbp.receivesInlineAction(createGetImageCaptchaInfoAction({ selector: '#svg-captcha-rendering' }));

                await dbp.isCaptchaError();
            });
        });

        test.describe('solveCaptchaInfo', () => {
            test('solves the captcha for the correct action data', async ({ createConfiguredDbp }) => {
                const dbp = await createConfiguredDbp(BROKER_PROTECTION_CONFIGS.default);
                await dbp.navigatesTo(imageCaptchaTargetPage);
                await dbp.receivesInlineAction(createSolveImageCaptchaAction({ selector: imageCaptchaResponseSelector }));
                dbp.getSuccessResponse();

                await dbp.isCaptchaTokenFilled(imageCaptchaResponseSelector);
            });
        });
    });

    test.describe('cloudflare turnstile', () => {
        const cloudFlareCaptchaTargetPage = 'cloudflare-captcha.html';

        test.describe('getCaptchaInfo', () => {
            test('returns the expected response for the correct action data', async ({ createConfiguredDbp }) => {
                const dbp = await createConfiguredDbp(BROKER_PROTECTION_CONFIGS.default);
                await dbp.navigatesTo(cloudFlareCaptchaTargetPage);
                await dbp.receivesInlineAction(createGetCloudFlareCaptchaInfoAction({ selector: '#captcha-widget' }));
                const sucessResponse = await dbp.getSuccessResponse();

                dbp.isCaptchaMatch(sucessResponse, {
                    captchaType: 'cloudFlareTurnstile',
                    targetPage: cloudFlareCaptchaTargetPage,
                    siteKey: '0x4AAAAAAA34NY6rivjWMWoq',
                });
            });

            test('returns an error if the sitekey attribute is missing', async ({ createConfiguredDbp }) => {
                const dbp = await createConfiguredDbp(BROKER_PROTECTION_CONFIGS.default);
                await dbp.navigatesTo(cloudFlareCaptchaTargetPage);
                await dbp.receivesInlineAction(createGetCloudFlareCaptchaInfoAction({ selector: '#missing-sitekey' }));

                await dbp.isCaptchaError();
            });
        });

        test.describe('solveCaptchaInfo', () => {
            test('returns an error if the callback attribute is missing', async ({ createConfiguredDbp }) => {
                const dbp = await createConfiguredDbp(BROKER_PROTECTION_CONFIGS.default);
                await dbp.navigatesTo(cloudFlareCaptchaTargetPage);
                await dbp.receivesInlineAction(createSolveCloudFlareCaptchaAction({ selector: '#missing-callback' }));

                await dbp.isCaptchaError();
            });

            test('solves the captcha for the correct action data', async ({ createConfiguredDbp }) => {
                const dbp = await createConfiguredDbp(BROKER_PROTECTION_CONFIGS.default);
                await dbp.navigatesTo(cloudFlareCaptchaTargetPage);
                await dbp.receivesInlineAction(createSolveCloudFlareCaptchaAction({ selector: '#captcha-widget' }));
                dbp.getSuccessResponse();

                await dbp.isCaptchaTokenFilled("//input[@name='cf-turnstile-response']");
            });
        });
    });
});
