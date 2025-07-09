/**
 * Special Page that displays release notes for the browser's current or updated version
 *
 * @module Release Notes Page
 */

/**
 * @typedef {import('../types/release-notes.ts').UpdateMessage} UpdateMessage
 */

/**
 * @typedef {Object} InitResponse
 * @property {ImportMeta['env']} [env] - optional override for the env
 * @property {string} [locale] - optional override for the locale
 */

import { init } from '../app/index.js';
import { createSpecialPageMessaging } from '../../../shared/create-special-page-messaging.js';
import { Environment } from '../../../shared/environment.js';
import { createTypedMessages } from '@duckduckgo/messaging';
import { mockTransport } from './mock-transport.js';
import '../../../shared/live-reload.js';

/**
 * This describes the messages that will be sent to the native layer,
 */
export class ReleaseNotesPage {
    /**
     * @param {import("@duckduckgo/messaging").Messaging} messaging
     * @internal
     */
    constructor(messaging) {
        /**
         * @internal
         */
        this.messaging = createTypedMessages(this, messaging);
    }

    /**
     * Sends an initial message to the native layer. This is the opportunity for the native layer
     * to provide the initial state of the application or any configuration, for example:
     *
     * ```json
     * {
     *   "env": "development",
     *   "locale": "en"
     * }
     * ```
     *
     * @returns {Promise<InitResponse>}
     */
    async initialSetup() {
        return await this.messaging.request('initialSetup');
    }

    /**
     * This will be sent if the application has loaded, but a client-side error
     * has occurred that cannot be recovered from
     * @param {{message: string}} params
     */
    reportPageException(params) {
        this.messaging.notify('reportPageException', params);
    }

    /**
     * This will be sent if the application fails to load.
     * @param {{message: string}} params
     */
    reportInitException(params) {
        this.messaging.notify('reportInitException', params);
    }

    /**
     * Forwards a click on retry fetching release notes button to browser. Added specifically for Windows use-case
     */
    retryFetchReleaseNotes() {
        this.messaging.notify('retryFetchReleaseNotes', {});
    }

    /**
     * Forwards a click on restart button to browser
     */
    browserRestart() {
        this.messaging.notify('browserRestart', {});
    }

    /**
     * Forwards a click on retry update button to browser
     */
    retryUpdate() {
        this.messaging.notify('retryUpdate', {});
    }

    /**
     * Subscribes to release info updates from browser
     * @param {(value: import('../types/release-notes.ts').UpdateMessage) => void} callback
     */
    onUpdate(callback) {
        return this.messaging.subscribe('onUpdate', callback);
    }
}

const baseEnvironment = new Environment().withInjectName(import.meta.injectName).withEnv(import.meta.env); // use the build's ENV

// share this in the app, it's an instance of `ReleaseNotesMessages` where all your native comms should be
const messaging = createSpecialPageMessaging({
    injectName: baseEnvironment.injectName,
    env: import.meta.env,
    pageName: import.meta.pageName || 'unknown',
    mockTransport: () => {
        // only in integration environments
        if (baseEnvironment.injectName !== 'integration') return null;
        let mock = null;
        // eslint-disable-next-line no-labels, no-unused-labels
        $INTEGRATION: mock = mockTransport();
        return mock;
    },
});

const releaseNotesPage = new ReleaseNotesPage(messaging);

init(releaseNotesPage, baseEnvironment).catch((e) => {
    console.error(e);
    const msg = typeof e?.message === 'string' ? e.message : 'unknown init error';
    releaseNotesPage.reportInitException({ message: msg });
});
