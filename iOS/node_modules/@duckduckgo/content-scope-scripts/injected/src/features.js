// Features must exist in either `baseFeatures` or `otherFeatures`
export const baseFeatures = /** @type {const} */ ([
    'fingerprintingAudio',
    'fingerprintingBattery',
    'fingerprintingCanvas',
    'googleRejected',
    'gpc',
    'fingerprintingHardware',
    'referrer',
    'fingerprintingScreenSize',
    'fingerprintingTemporaryStorage',
    'navigatorInterface',
    'elementHiding',
    'exceptionHandler',
    'apiManipulation',
]);

const otherFeatures = /** @type {const} */ ([
    'clickToLoad',
    'cookie',
    'messageBridge',
    'duckPlayer',
    'duckPlayerNative',
    'harmfulApis',
    'webCompat',
    'windowsPermissionUsage',
    'brokerProtection',
    'performanceMetrics',
    'breakageReporting',
    'autofillPasswordImport',
    'favicon',
    'scriptlets',
]);

/** @typedef {baseFeatures[number]|otherFeatures[number]} FeatureName */
/** @type {Record<string, FeatureName[]>} */
export const platformSupport = {
    apple: ['webCompat', 'duckPlayerNative', 'scriptlets', ...baseFeatures],
    'apple-isolated': [
        'duckPlayer',
        'duckPlayerNative',
        'brokerProtection',
        'performanceMetrics',
        'clickToLoad',
        'messageBridge',
        'favicon',
    ],
    android: [...baseFeatures, 'webCompat', 'breakageReporting', 'duckPlayer', 'messageBridge'],
    'android-broker-protection': ['brokerProtection'],
    'android-autofill-password-import': ['autofillPasswordImport'],
    windows: [
        'cookie',
        ...baseFeatures,
        'windowsPermissionUsage',
        'duckPlayer',
        'brokerProtection',
        'breakageReporting',
        'messageBridge',
        'webCompat',
    ],
    firefox: ['cookie', ...baseFeatures, 'clickToLoad'],
    chrome: ['cookie', ...baseFeatures, 'clickToLoad'],
    'chrome-mv3': ['cookie', ...baseFeatures, 'clickToLoad'],
    integration: [...baseFeatures, ...otherFeatures],
};
