import ContentFeature from '../content-feature.js';
import { execute } from './broker-protection/execute.js';
import { retry } from '../timer-utils.js';
import { ErrorResponse } from './broker-protection/types.js';

/**
 * @typedef {import("./broker-protection/types.js").ActionResponse} ActionResponse
 */
export default class BrokerProtection extends ContentFeature {
    init() {
        this.messaging.subscribe('onActionReceived', async (/** @type {any} */ params) => {
            try {
                const action = params.state.action;
                const data = params.state.data;

                if (!action) {
                    return this.messaging.notify('actionError', { error: 'No action found.' });
                }

                const { results, exceptions } = await this.exec(action, data);

                if (results) {
                    // there might only be a single result.
                    const parent = results[0];
                    const errors = results.filter((x) => 'error' in x);

                    // if there are no secondary actions, or just no errors in general, just report the parent action
                    if (results.length === 1 || errors.length === 0) {
                        return this.messaging.notify('actionCompleted', { result: parent });
                    }

                    // here we must have secondary actions that failed.
                    // so we want to create an error response with the parent ID, but with the errors messages from
                    // the children
                    const joinedErrors = errors.map((x) => x.error.message).join(', ');
                    const response = new ErrorResponse({
                        actionID: action.id,
                        message: 'Secondary actions failed: ' + joinedErrors,
                    });

                    return this.messaging.notify('actionCompleted', { result: response });
                } else {
                    return this.messaging.notify('actionError', { error: 'No response found, exceptions: ' + exceptions.join(', ') });
                }
            } catch (e) {
                console.log('unhandled exception: ', e);
                this.messaging.notify('actionError', { error: e.toString() });
            }
        });
    }

    /**
     * Recursively execute actions with the same dataset, collecting all results/exceptions for
     * later analysis
     * @param {any} action
     * @param {Record<string, any>} data
     * @return {Promise<{results: ActionResponse[], exceptions: string[]}>}
     */
    async exec(action, data) {
        const retryConfig = this.retryConfigFor(action);
        const { result, exceptions } = await retry(() => execute(action, data, document), retryConfig);

        if (result) {
            if ('success' in result && Array.isArray(result.success.next)) {
                const nextResults = [];
                const nextExceptions = [];

                for (const nextAction of result.success.next) {
                    const { results: subResults, exceptions: subExceptions } = await this.exec(nextAction, data);

                    nextResults.push(...subResults);
                    nextExceptions.push(...subExceptions);
                }
                return { results: [result, ...nextResults], exceptions: exceptions.concat(nextExceptions) };
            }
            return { results: [result], exceptions: [] };
        }
        return { results: [], exceptions };
    }

    /**
     * Define default retry configurations for certain actions
     *
     * @param {any} action
     * @returns
     */
    retryConfigFor(action) {
        /**
         * Note: We're not currently guarding against concurrent actions here
         * since the native side contains the scheduling logic to prevent it.
         */
        const retryConfig = action.retry?.environment === 'web' ? action.retry : undefined;
        /**
         * Special case for the exact action
         */
        if (!retryConfig && action.actionType === 'extract') {
            return {
                interval: { ms: 1000 },
                maxAttempts: 30,
            };
        }
        /**
         * Special case for when expectation or condition contains a check for an element, retry it
         */
        if (!retryConfig && (action.actionType === 'expectation' || action.actionType === 'condition')) {
            if (action.expectations.some((x) => x.type === 'element')) {
                return {
                    interval: { ms: 1000 },
                    maxAttempts: 30,
                };
            }
        }
        return retryConfig;
    }
}
