/**
 * @typedef {Object} StepCompleteParams
 * Sent when a user has transitioned from a step to the next one
 * @property {import('./types').Step['id']} id - a unique identifier for each step
 *
 * @typedef {Object} InitResponse
 * @property {Record<string, any>} stepDefinitions
 * @property {string} [order] - ability to override the screen order
 * @property {string[]} [exclude] - ability to exclude screens
 * @property {ImportMeta['env']} [env] - optional override for the running override
 * @property {string} locale
 * @property {{ name: 'macos'|'windows'|'android'|'ios'}} [platform]
 */

/**
 * This describes the messages that will be sent to the native layer,
 */
export class OnboardingMessages {
    /**
     * @param {import("@duckduckgo/messaging").Messaging} messaging
     * @param {ImportMeta["injectName"]} injectName
     * @internal
     */
    constructor(messaging, injectName) {
        /**
         * @internal
         */
        this.messaging = messaging;
        this.injectName = injectName;
    }

    /**
     * Sends an initial message to the native layer. This is the opportunity for the native layer
     * to provide the initial state of the application or any configuration, for example:
     *
     * ```json
     * {
     *   "stepDefinitions": {
     *     "systemSettings": {
     *       "rows": ["dock", "import", "default-browser"]
     *     }
     *   },
     *   "order": "v2",
     *   "exclude": ["dockSingle"],
     *   "locale": "en"
     * }
     * ```
     *
     * In that example, the native layer is providing the list of rows that should be shown in the
     * systemSettings step, overriding the default list provided in `data.js`.
     *
     * @returns {Promise<InitResponse>}
     */
    async init() {
        return await this.messaging.request('init');
    }

    /**
     * Sends a notification to the native layer that the user has completed a step
     *
     * @param {StepCompleteParams} params
     */
    stepCompleted(params) {
        this.messaging.notify('stepCompleted', params);
    }

    /**
     * Sent when the user wants to enable or disable the bookmarks bar
     *
     * @param {import('./types').BooleanSystemValue} params
     */
    setBookmarksBar(params) {
        this.messaging.notify('setBookmarksBar', params);
    }

    /**
     * Sent when the user wants to enable or disable the session restore setting
     *
     * @param {import('./types').BooleanSystemValue} params
     */
    setSessionRestore(params) {
        this.messaging.notify('setSessionRestore', params);
    }

    /**
     * Sent when the user wants to enable or disable the home button
     * Note: Although the home button can placed in multiple places in the browser taskbar, this
     * application will only ever send enabled/disabled to the native layer
     *
     * @param {import('./types').BooleanSystemValue} params
     */
    setShowHomeButton(params) {
        this.messaging.notify('setShowHomeButton', params);
    }

    /**
     * Sent when the user wants to keep the application in the dock/taskbar.
     *
     * Native side should respond when the operation is 'complete'.
     *
     * @returns {Promise<any>}
     */
    requestDockOptIn() {
        return this.messaging.request('requestDockOptIn');
    }

    /**
     * Sent when the user wants to import data. The UI will remain
     * in a loading state until the native layer sends a response.
     *
     * Native side should respond when the operation is 'complete'.
     *
     * @returns {Promise<any>}
     */
    requestImport() {
        return this.messaging.request('requestImport');
    }

    /**
     * Sent when the user wants to set DuckDuckGo as their default browser. The UI will remain
     * in a loading state until the native layer sends a response.
     *
     * Native side should respond when the operation is 'complete'.
     *
     * @returns {Promise<any>}
     */
    requestSetAsDefault() {
        return this.messaging.request('requestSetAsDefault');
    }

    /**
     * Sent when onboarding is complete and the user has chosen to go to settings
     */
    dismissToSettings() {
        this.messaging.notify('dismissToSettings');
    }

    /**
     * Sent when the "Start Browsing" button has been clicked.
     */
    dismissToAddressBar() {
        this.messaging.notify('dismissToAddressBar');
    }

    /**
     * This will be sent if the application has loaded, but a client-side error
     * has occurred that cannot be recovered from
     * @param {import('./types').ErrorBoundaryEvent["error"]} params
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
     * Sent when the user wants to enable or disable ad blocking.
     *
     * @param {import('./types').BooleanSystemValue} params
     */
    setAdBlocking(params) {
        this.messaging.notify('setAdBlocking', params);
    }
}
