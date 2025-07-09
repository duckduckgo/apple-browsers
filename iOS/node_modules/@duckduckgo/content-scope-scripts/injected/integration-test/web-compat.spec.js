import { gotoAndWait, testContextForExtension } from './helpers/harness.js';
import { test as base, expect } from '@playwright/test';

const test = testContextForExtension(base);

test.describe('Ensure safari interface is injected', () => {
    test('should expose window.safari when enabled', async ({ page }) => {
        await gotoAndWait(page, '/blank.html', { site: { enabledFeatures: [] } });
        const noSafari = await page.evaluate(() => {
            return 'safari' in window;
        });
        expect(noSafari).toEqual(false);

        await gotoAndWait(page, '/blank.html', {
            site: {
                enabledFeatures: ['webCompat'],
            },
            featureSettings: {
                webCompat: {
                    safariObject: 'enabled',
                },
            },
        });
        const hasSafari = await page.evaluate(() => {
            return 'safari' in window;
        });
        expect(hasSafari).toEqual(true);

        const pushNotificationToString = await page.evaluate(() => {
            // @ts-expect-error https://app.asana.com/0/1201614831475344/1203979574128023/f
            return window.safari.pushNotification.toString();
        });
        expect(pushNotificationToString).toEqual('[object SafariRemoteNotification]');

        const pushNotificationPermission = await page.evaluate(() => {
            // @ts-expect-error https://app.asana.com/0/1201614831475344/1203979574128023/f
            return window.safari.pushNotification.permission('test');
        });
        expect(pushNotificationPermission.deviceToken).toEqual(null);
        expect(pushNotificationPermission.permission).toEqual('denied');

        const pushNotificationRequestPermissionThrow = await page.evaluate(() => {
            try {
                // @ts-expect-error https://app.asana.com/0/1201614831475344/1203979574128023/f
                window.safari.pushNotification.requestPermission('test', 'test.com');
            } catch (e) {
                return e.message;
            }
        });
        expect(pushNotificationRequestPermissionThrow).toEqual(
            "Invalid 'callback' value passed to safari.pushNotification.requestPermission(). Expected a function.",
        );

        const pushNotificationRequestPermission = await page.evaluate(() => {
            const response = new Promise((resolve) => {
                // @ts-expect-error https://app.asana.com/0/1201614831475344/1203979574128023/f
                window.safari.pushNotification.requestPermission('test', 'test.com', {}, (data) => {
                    resolve(data);
                });
            });
            return response;
        });
        expect(pushNotificationRequestPermission.deviceToken).toEqual(null);
        expect(pushNotificationRequestPermission.permission).toEqual('denied');
    });
});

test.describe('Ensure Notification interface is injected', () => {
    test('should expose window.Notification when enabled', async ({ page }) => {
        // Fake the Notification API not existing in this browser
        const removeNotificationScript = `
            delete window.Notification
        `;
        function checkForNotification() {
            return 'Notification' in window;
        }
        function checkObjectDescriptorSerializedValue() {
            const descriptor = Object.getOwnPropertyDescriptor(window, 'Notification');
            const out = {};
            for (const key in descriptor) {
                out[key] = !!descriptor[key];
            }
            return out;
        }
        await gotoAndWait(page, '/blank.html', { site: { enabledFeatures: [] } });
        const initialNotification = await page.evaluate(checkForNotification);
        // Base implementation of the test env should have it.
        expect(initialNotification).toEqual(true);
        const initialDescriptorSerialization = await page.evaluate(checkObjectDescriptorSerializedValue);

        await gotoAndWait(page, '/blank.html', { site: { enabledFeatures: [] } }, removeNotificationScript);
        const noNotification = await page.evaluate(() => {
            return 'Notification' in window;
        });
        expect(noNotification).toEqual(false);

        await gotoAndWait(
            page,
            '/blank.html',
            {
                site: {
                    enabledFeatures: ['webCompat'],
                },
                featureSettings: {
                    webCompat: {
                        notification: 'enabled',
                    },
                },
            },
            removeNotificationScript,
        );
        const hasNotification = await page.evaluate(checkForNotification);
        expect(hasNotification).toEqual(true);

        const modifiedDescriptorSerialization = await page.evaluate(checkObjectDescriptorSerializedValue);
        expect(modifiedDescriptorSerialization).toEqual(initialDescriptorSerialization);

        const permissionDenied = await page.evaluate(() => {
            return window.Notification.requestPermission();
        });
        expect(permissionDenied).toEqual('denied');

        const permissionPropDenied = await page.evaluate(() => {
            return window.Notification.permission;
        });
        expect(permissionPropDenied).toEqual('denied');

        const maxActionsPropDenied = await page.evaluate(() => {
            // @ts-expect-error - This is a property that should exist but experimental.
            return window.Notification.maxActions;
        });
        expect(maxActionsPropDenied).toEqual(2);
    });
});

test.describe('Permissions API', () => {
    // Fake the Permission API not existing in this browser
    const removePermissionsScript = `
    Object.defineProperty(window.navigator, 'permissions', { writable: true, value: undefined })
    `;

    function checkForPermissions() {
        return !!window.navigator.permissions;
    }
    function checkObjectDescriptorIsNotPresent() {
        const descriptor = Object.getOwnPropertyDescriptor(window.navigator, 'permissions');
        return descriptor === undefined;
    }

    test.describe('disabled feature', () => {
        test('should not expose permissions API', async ({ page }) => {
            await gotoAndWait(page, '/blank.html', { site: { enabledFeatures: [] } });
            const initialPermissions = await page.evaluate(checkForPermissions);
            // Base implementation of the test env should have it.
            expect(initialPermissions).toEqual(true);
            const initialDescriptorSerialization = await page.evaluate(checkObjectDescriptorIsNotPresent);
            expect(initialDescriptorSerialization).toEqual(true);
            await gotoAndWait(page, '/blank.html', { site: { enabledFeatures: [] } }, removePermissionsScript);
            const noPermissions = await page.evaluate(checkForPermissions);
            expect(noPermissions).toEqual(false);
        });
    });

    test.describe('enabled feature', () => {
        /**
         * @param {import("@playwright/test").Page} page
         */
        async function before(page) {
            await gotoAndWait(
                page,
                '/blank.html',
                {
                    site: {
                        enabledFeatures: ['webCompat'],
                    },
                    featureSettings: {
                        webCompat: {
                            permissions: {
                                state: 'enabled',
                                supportedPermissions: {
                                    geolocation: {},
                                    push: {
                                        name: 'notifications',
                                    },
                                    camera: {
                                        name: 'video_capture',
                                        native: true,
                                    },
                                },
                            },
                        },
                    },
                },
                removePermissionsScript,
            );
        }
        /**
         * @param {import("@playwright/test").Page} page
         * @param {any} name
         * @return {Promise<{result: any, message: *}>}
         */
        async function checkPermission(page, name) {
            const payload = `window.navigator.permissions.query(${JSON.stringify({ name })})`;
            const result = await page.evaluate(payload).catch((e) => {
                return { threw: e };
            });
            const message = await page.evaluate(() => {
                return globalThis.shareReq;
            });
            return { result, message };
        }
        test('should expose window.navigator.permissions when enabled', async ({ page }) => {
            await before(page);
            const hasPermissions = await page.evaluate(checkForPermissions);
            expect(hasPermissions).toEqual(true);
            const modifiedDescriptorSerialization = await page.evaluate(checkObjectDescriptorIsNotPresent);
            // This fails in a test condition purely because we have to add a descriptor to modify the prop
            expect(modifiedDescriptorSerialization).toEqual(false);
        });
        test('should throw error when permission not supported', async ({ page }) => {
            await before(page);
            const { result } = await checkPermission(page, 'notexistent');
            expect(result.threw).not.toBeUndefined();
            expect(result.threw.message).toContain('notexistent');
        });
        test('should return prompt by default', async ({ page }) => {
            await before(page);
            const { result } = await checkPermission(page, 'geolocation');
            expect(result).toMatchObject({ name: 'geolocation', state: 'prompt' });
        });
        test('should return updated name when configured', async ({ page }) => {
            await before(page);
            const { result } = await checkPermission(page, 'push');
            expect(result).toMatchObject({ name: 'notifications', state: 'prompt' });
        });
        test('should propagate result from native when configured', async ({ page }) => {
            await before(page);
            // Fake result from native
            await page.evaluate(() => {
                globalThis.cssMessaging.impl.request = (req) => {
                    globalThis.shareReq = req;
                    return Promise.resolve({ state: 'granted' });
                };
            });
            const { result, message } = await checkPermission(page, 'camera');
            expect(result).toMatchObject({ name: 'video_capture', state: 'granted' });
            expect(message).toMatchObject({ featureName: 'webCompat', method: 'permissionsQuery', params: { name: 'camera' } });
        });
        test('should default to prompt when native sends unexpected response', async ({ page }) => {
            await before(page);
            page.on('console', (msg) => {
                console.log(`PAGE LOG: ${msg.text()}`);
            });

            await page.evaluate(() => {
                globalThis.cssMessaging.impl.request = (message) => {
                    globalThis.shareReq = message;
                    return Promise.resolve({ noState: 'xxx' });
                };
            });
            const { result, message } = await checkPermission(page, 'camera');
            expect(result).toMatchObject({ name: 'video_capture', state: 'prompt' });
            expect(message).toMatchObject({ featureName: 'webCompat', method: 'permissionsQuery', params: { name: 'camera' } });
        });
        test('should default to prompt when native error occurs', async ({ page }) => {
            await before(page);
            await page.evaluate(() => {
                globalThis.cssMessaging.impl.request = (message) => {
                    globalThis.shareReq = message;
                    return Promise.reject(new Error('something wrong'));
                };
            });
            const { result, message } = await checkPermission(page, 'camera');
            expect(result).toMatchObject({ name: 'video_capture', state: 'prompt' });
            expect(message).toMatchObject({ featureName: 'webCompat', method: 'permissionsQuery', params: { name: 'camera' } });
        });
    });
});

test.describe('ScreenOrientation API', () => {
    test.describe('disabled feature', () => {
        /**
         * @param {import("@playwright/test").Page} page
         * @param {any} orientation
         * @return {Promise<any>}
         */
        async function checkLockThrows(page, orientation) {
            const payload = `screen.orientation.lock(${JSON.stringify(orientation)})`;
            const result = await page.evaluate(payload).catch((e) => {
                return { threw: e };
            });
            return result;
        }

        test(' should not fix screenOrientation API', async ({ page }) => {
            // no screenLock setting
            await gotoAndWait(page, '/blank.html', { site: { enabledFeatures: ['webCompat'] } });
            const result = await checkLockThrows(page, 'landscape');
            expect(result.threw).not.toBeUndefined();
            expect(result.threw.message).toContain('screen.orientation.lock() is not available on this device.');
        });
    });

    test.describe('enabled feature', () => {
        async function beforeAll(page) {
            await gotoAndWait(page, '/blank.html', {
                site: {
                    enabledFeatures: ['webCompat'],
                },
                featureSettings: {
                    webCompat: {
                        screenLock: 'enabled',
                    },
                },
            });
        }

        /**
         * @param {import("@playwright/test").Page} page
         * @param {any} orientation
         */
        async function checkLock(page, orientation) {
            const payload = `screen.orientation.lock(${JSON.stringify(orientation)})`;
            const result = await page.evaluate(payload).catch((e) => {
                return { threw: e };
            });
            const message = await page.evaluate(() => {
                return globalThis.lockReq;
            });
            return { result, message };
        }

        /**
         * @param {import("@playwright/test").Page} page
         */
        async function checkUnlock(page) {
            const payload = 'screen.orientation.unlock()';
            const result = await page.evaluate(payload).catch((e) => {
                return { threw: e };
            });
            const message = await page.evaluate(() => {
                return globalThis.lockReq;
            });
            return { result, message };
        }

        test('should err out when orientation not provided', async ({ page }) => {
            await beforeAll(page);
            const { result } = await checkLock(page, undefined);
            expect(result.threw).not.toBeUndefined();
            expect(result.threw.message).toContain(
                "Failed to execute 'lock' on 'ScreenOrientation': 1 argument required, but only 0 present",
            );
        });

        test('should err out when orientation of unexpected type', async ({ page }) => {
            await beforeAll(page);
            const { result } = await checkLock(page, {});
            expect(result.threw).not.toBeUndefined();
            expect(result.threw.message).toContain('not a valid enum value of type OrientationLockType');
        });

        test('should err out when orientation of unexpected value', async ({ page }) => {
            await beforeAll(page);
            const { result } = await checkLock(page, 'xxx');
            expect(result.threw).not.toBeUndefined();
            expect(result.threw.message).toContain('not a valid enum value of type OrientationLockType');
        });

        test('should propagate native TypeError', async ({ page }) => {
            await beforeAll(page);
            await page.evaluate(() => {
                globalThis.cssMessaging.impl.request = () => {
                    return Promise.resolve({ failure: { name: 'TypeError', message: 'some error message' } });
                };
            });

            const { result } = await checkLock(page, 'landscape');
            expect(result.threw).not.toBeUndefined();
            expect(result.threw.message).toContain('some error message');
        });

        test('should propagate native InvalidStateError', async ({ page }) => {
            await beforeAll(page);
            await page.evaluate(() => {
                globalThis.cssMessaging.impl.request = () => {
                    return Promise.resolve({ failure: { name: 'InvalidStateError', message: 'some error message' } });
                };
            });

            const { result } = await checkLock(page, 'landscape');
            expect(result.threw).not.toBeUndefined();
            expect(result.threw.message).toContain('some error message');
        });

        test('should propagate native default error', async ({ page }) => {
            await beforeAll(page);
            await page.evaluate(() => {
                globalThis.cssMessaging.impl.request = () => {
                    return Promise.resolve({ failure: { name: 'xxx', message: 'some error message' } });
                };
            });

            const { result } = await checkLock(page, 'landscape');
            expect(result.threw).not.toBeUndefined();
            expect(result.threw.message).toContain('some error message');
        });

        test('should fix screenOrientation API', async ({ page }) => {
            await beforeAll(page);
            await page.evaluate(() => {
                globalThis.cssMessaging.impl.request = (req) => {
                    globalThis.lockReq = req;
                    return Promise.resolve({});
                };
            });

            const { result, message } = await checkLock(page, 'landscape');
            expect(result).toBeUndefined();
            expect(message).toMatchObject({ featureName: 'webCompat', method: 'screenLock', params: { orientation: 'landscape' } });
        });

        test('should send message on unlock', async ({ page }) => {
            await beforeAll(page);
            await page.evaluate(() => {
                globalThis.cssMessaging.impl.request = (req) => {
                    globalThis.lockReq = req;
                    return Promise.resolve({});
                };
            });

            const { result, message } = await checkUnlock(page);
            expect(result).toBeUndefined();
            expect(message).toMatchObject({ featureName: 'webCompat', method: 'screenUnlock' });
        });
    });
});

test.describe('Viewport fixes', () => {
    function getViewportValue() {
        return document.querySelector('meta[name="viewport"]')?.getAttribute('content');
    }

    test('should not change viewport if disabled', async ({ page }) => {
        await gotoAndWait(
            page,
            '/blank.html',
            { site: { enabledFeatures: [] } },
            'document.head.innerHTML += \'<meta name="viewport" content="width=device-width">\'',
        );
        const initialViewportValue = await page.evaluate(getViewportValue);
        // Base implementation of the test env should have it.
        expect(initialViewportValue).toEqual('width=device-width');

        // We don't make a change if disabled
        await gotoAndWait(page, '/blank.html', { site: { enabledFeatures: [] } });
        const viewportValue = await page.evaluate(getViewportValue);
        expect(viewportValue).toBeUndefined();
    });

    test('should respect forced zoom', async ({ page }) => {
        await gotoAndWait(
            page,
            '/blank.html',
            {
                site: { enabledFeatures: ['webCompat'] },
                featureSettings: { webCompat: { viewportWidth: 'enabled' } },
                desktopModeEnabled: false,
                forcedZoomEnabled: true,
            },
            'document.head.innerHTML += \'<meta name="viewport" content="width=device-width">\'',
        );

        const viewportValue = await page.evaluate(getViewportValue);
        expect(viewportValue).toEqual('initial-scale=1, user-scalable=yes, maximum-scale=10, width=device-width');
    });

    test.describe('Desktop mode off', () => {
        test('should respect the forcedMobileValue config', async ({ page }) => {
            await gotoAndWait(page, '/blank.html', {
                site: { enabledFeatures: ['webCompat'] },
                featureSettings: { webCompat: { viewportWidth: { state: 'enabled', forcedMobileValue: 'bla, bla, bla' } } },
                desktopModeEnabled: false,
            });
            const viewportValue = await page.evaluate(getViewportValue);
            expect(viewportValue).toEqual('bla, bla, bla');
        });

        test('should force wide viewport if the meta tag is not present', async ({ page }) => {
            await gotoAndWait(page, '/blank.html', {
                site: { enabledFeatures: ['webCompat'] },
                featureSettings: { webCompat: { viewportWidth: 'enabled' } },
                desktopModeEnabled: false,
            });
            const width = await page.evaluate('screen.width');
            const expectedWidth = width < 1280 ? 980 : 1280;
            const viewportValue = await page.evaluate(getViewportValue);
            expect(viewportValue).toEqual(`width=${expectedWidth}, initial-scale=${(width / expectedWidth).toFixed(3)}, user-scalable=yes`);
        });

        test('should respect forced zoom', async ({ page }) => {
            await gotoAndWait(page, '/blank.html', {
                site: { enabledFeatures: ['webCompat'] },
                featureSettings: { webCompat: { viewportWidth: 'enabled' } },
                desktopModeEnabled: false,
                forcedZoomEnabled: true,
            });
            const width = await page.evaluate('screen.width');
            const expectedWidth = width < 1280 ? 980 : 1280;
            const viewportValue = await page.evaluate(getViewportValue);
            expect(viewportValue).toEqual(
                `initial-scale=${(width / expectedWidth).toFixed(3)}, user-scalable=yes, maximum-scale=10, width=${expectedWidth}`,
            );
        });

        test('should fix the WebView edge case', async ({ page }) => {
            await gotoAndWait(
                page,
                '/blank.html',
                {
                    site: { enabledFeatures: ['webCompat'] },
                    featureSettings: { webCompat: { viewportWidth: 'enabled' } },
                    desktopModeEnabled: false,
                },
                'document.head.innerHTML += \'<meta name="viewport" content="initial-scale=1.00001, something-something">\'',
            );
            const viewportValue = await page.evaluate(getViewportValue);
            expect(viewportValue).toEqual('width=device-width, initial-scale=1.00001, something-something');
        });

        test('should ignore the character case in the viewport tag', async ({ page }) => {
            await gotoAndWait(
                page,
                '/blank.html',
                {
                    site: { enabledFeatures: ['webCompat'] },
                    featureSettings: { webCompat: { viewportWidth: 'enabled' } },
                    desktopModeEnabled: false,
                },
                'document.head.innerHTML += \'<meta name="viewport" content="initIAL-scale=1.00001, something-something">\'',
            );
            const viewportValue = await page.evaluate(getViewportValue);
            expect(viewportValue).toEqual('width=device-width, initIAL-scale=1.00001, something-something');
        });
    });

    test.describe('Desktop mode on', () => {
        test('should respect the forcedDesktopValue config', async ({ page }) => {
            await gotoAndWait(page, '/blank.html', {
                site: { enabledFeatures: ['webCompat'] },
                featureSettings: { webCompat: { viewportWidth: { state: 'enabled', forcedDesktopValue: 'bla, bla, bla' } } },
                desktopModeEnabled: true,
            });
            const viewportValue = await page.evaluate(getViewportValue);
            expect(viewportValue).toEqual('bla, bla, bla');
        });

        test('should force wide viewport, ignoring the viewport tag', async ({ page }) => {
            await gotoAndWait(
                page,
                '/blank.html',
                {
                    site: { enabledFeatures: ['webCompat'] },
                    featureSettings: { webCompat: { viewportWidth: 'enabled' } },
                    desktopModeEnabled: true,
                },
                'document.head.innerHTML += \'<meta name="viewport" content="width=device-width, initial-scale=2, user-scalable=no, something-something">\'',
            );
            const width = await page.evaluate('screen.width');
            const expectedWidth = width < 1280 ? 980 : 1280;
            const viewportValue = await page.evaluate(getViewportValue);
            expect(viewportValue).toEqual(
                `width=${expectedWidth}, initial-scale=${(width / expectedWidth).toFixed(3)}, user-scalable=yes, something-something`,
            );
        });

        test('should override minimum-scale, if it is set', async ({ page }) => {
            await gotoAndWait(
                page,
                '/blank.html',
                {
                    site: { enabledFeatures: ['webCompat'] },
                    featureSettings: { webCompat: { viewportWidth: 'enabled' } },
                    desktopModeEnabled: true,
                },
                'document.head.innerHTML += \'<meta name="viewport" content="width=device-width, initial-scale=2, user-scalable=no, minimum-scale=1, something-something">\'',
            );
            const width = await page.evaluate('screen.width');
            const expectedWidth = width < 1280 ? 980 : 1280;
            const viewportValue = await page.evaluate(getViewportValue);
            expect(viewportValue).toEqual(
                `width=${expectedWidth}, initial-scale=${(width / expectedWidth).toFixed(3)}, user-scalable=yes, minimum-scale=0, something-something`,
            );
        });

        test('should force wide viewport, ignoring the viewport tag 2', async ({ page }) => {
            await gotoAndWait(
                page,
                '/blank.html',
                {
                    site: { enabledFeatures: ['webCompat'] },
                    featureSettings: { webCompat: { viewportWidth: 'enabled' } },
                    desktopModeEnabled: true,
                },
                'document.head.innerHTML += \'<meta name="viewport" content="something-something">\'',
            );
            const width = await page.evaluate('screen.width');
            const expectedWidth = width < 1280 ? 980 : 1280;
            const viewportValue = await page.evaluate(getViewportValue);
            expect(viewportValue).toEqual(
                `width=${expectedWidth}, initial-scale=${(width / expectedWidth).toFixed(3)}, user-scalable=yes, something-something`,
            );
        });

        test('should respect forced zoom', async ({ page }) => {
            await gotoAndWait(
                page,
                '/blank.html',
                {
                    site: { enabledFeatures: ['webCompat'] },
                    featureSettings: { webCompat: { viewportWidth: 'enabled' } },
                    desktopModeEnabled: true,
                    forcedZoomEnabled: true,
                },
                'document.head.innerHTML += \'<meta name="viewport" content="width=device-width, initial-scale=2, user-scalable=no, something-something">\'',
            );
            const width = await page.evaluate('screen.width');
            const expectedWidth = width < 1280 ? 980 : 1280;
            const viewportValue = await page.evaluate(getViewportValue);
            expect(viewportValue).toEqual(
                `initial-scale=${(width / expectedWidth).toFixed(3)}, user-scalable=yes, maximum-scale=10, width=${expectedWidth}, something-something`,
            );
        });

        test('should ignore the character case in the viewport tag', async ({ page }) => {
            await gotoAndWait(
                page,
                '/blank.html',
                {
                    site: { enabledFeatures: ['webCompat'] },
                    featureSettings: { webCompat: { viewportWidth: 'enabled' } },
                    desktopModeEnabled: true,
                },
                'document.head.innerHTML += \'<meta name="viewport" content="wIDth=device-width, iniTIal-scale=2, usER-scalable=no, something-something">\'',
            );
            const width = await page.evaluate('screen.width');
            const expectedWidth = width < 1280 ? 980 : 1280;
            const viewportValue = await page.evaluate(getViewportValue);
            expect(viewportValue).toEqual(
                `width=${expectedWidth}, initial-scale=${(width / expectedWidth).toFixed(3)}, user-scalable=yes, something-something`,
            );
        });
    });
});
