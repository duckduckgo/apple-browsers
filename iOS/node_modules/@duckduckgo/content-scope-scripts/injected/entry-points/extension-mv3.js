/**
 * @module main world integration for Chrome MV3 and Firefox (enhanced) MV2
 */
import { load, init, update } from '../src/content-scope-features.js';
import { computeLimitedSiteObject } from '../src/utils.js';

const secret = (crypto.getRandomValues(new Uint32Array(1))[0] / 2 ** 32).toString().replace('0.', '');

load({
    platform: {
        name: 'extension',
    },
    site: computeLimitedSiteObject(),
    // @ts-expect-error https://app.asana.com/0/1201614831475344/1203979574128023/f
    bundledConfig: $BUNDLED_CONFIG$,
});

// @ts-expect-error https://app.asana.com/0/1201614831475344/1203979574128023/f
window.addEventListener(secret, ({ detail: encodedMessage }) => {
    if (!encodedMessage) return;
    const message = JSON.parse(encodedMessage);

    switch (message.type) {
        case 'update':
            update(message);
            break;
        case 'register':
            if (message.argumentsObject) {
                message.argumentsObject.messageSecret = secret;
                init(message.argumentsObject);
            }
            break;
    }
});

window.dispatchEvent(
    new CustomEvent('ddg-secret', {
        detail: secret,
    }),
);
