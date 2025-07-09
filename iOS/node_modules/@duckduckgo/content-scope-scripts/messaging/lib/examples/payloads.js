/* eslint-disable @typescript-eslint/no-unused-vars */
import { NotificationMessage, RequestMessage, MessageResponse, SubscriptionEvent } from '../../index.js';

/**
 * This is the payload sent for a notification
 * @type {NotificationMessage}
 */
const notification = {
    context: 'contentScopeScripts',
    featureName: 'duckPlayerOverlays',
    method: 'setUserValues',
    params: {},
};

/**
 * This is the payload sent for a Request.
 * @type {RequestMessage}
 */
const request = {
    context: 'contentScopeScripts',
    featureName: 'duckPlayerOverlays',
    method: 'setUserValues',
    params: {},
    id: 'setUserValues.response',
};

/**
 * This is the payload for a response
 * @type {MessageResponse}
 */
const messageResponse = {
    context: 'contentScopeScripts',
    featureName: 'duckPlayerOverlays',
    result: {},
    id: 'setUserValues.response',
    error: undefined,
};

/**
 * This is the payload response for an error
 * @type {MessageResponse}
 */
const messageResponseError = {
    context: 'contentScopeScripts',
    featureName: 'duckPlayerOverlays',
    result: undefined,
    id: 'setUserValues.response',
    error: { message: '' },
};

/**
 * This is the payload response for a subscriptionEvent
 * @type {SubscriptionEvent}
 */
const myEvent = {
    context: 'contentScopeScripts',
    featureName: 'duckPlayerOverlays',
    subscriptionName: 'setUserValues',
    params: {},
};
