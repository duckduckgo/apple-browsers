import { DDGVideoOverlayMobile } from '../../../../src/features/duckplayer/components/ddg-video-overlay-mobile.js';
import { overlayCopyVariants } from '../../../../src/features/duckplayer/text.js';

customElements.define(DDGVideoOverlayMobile.CUSTOM_TAG_NAME, DDGVideoOverlayMobile);

const elem = /** @type {DDGVideoOverlayMobile} */ (document.createElement(DDGVideoOverlayMobile.CUSTOM_TAG_NAME));
elem.testMode = true;
elem.text = overlayCopyVariants.default;

elem.addEventListener('opt-in', (/** @type {CustomEvent} */ e) => {
    console.log('did opt in?', e.detail);
});

elem.addEventListener('opt-out', (/** @type {CustomEvent} */ e) => {
    console.log('did opt out?', e.detail);
});

elem.addEventListener('open-info', (e) => {
    console.log('did open info');
});

document.querySelector('.html5-video-player')?.append(elem);
