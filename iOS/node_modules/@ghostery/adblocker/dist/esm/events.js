/*!
 * Copyright (c) 2017-present Ghostery GmbH. All rights reserved.
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */
import { queueMicrotask } from './queue-microtask.js';
/**
 * Add `callback` listener for `event` in `listeners` Map.
 */
function registerCallback(event, callback, listeners) {
    let listenersForEvent = listeners.get(event);
    if (listenersForEvent === undefined) {
        listenersForEvent = [];
        listeners.set(event, listenersForEvent);
    }
    listenersForEvent.push(callback);
}
/**
 * Remove `callback` listener for `event` from `listeners` Map.
 */
function unregisterCallback(event, callback, listeners) {
    const listenersForEvent = listeners.get(event);
    if (listenersForEvent !== undefined) {
        const indexOfCallback = listenersForEvent.indexOf(callback);
        if (indexOfCallback !== -1) {
            listenersForEvent.splice(indexOfCallback, 1);
        }
    }
}
/**
 * Call all registered listeners for `event` with `args` as arguments. Return
 * `true` if at least one callback was registered and `false` otherwise.
 */
function triggerCallback(event, args, listeners) {
    // Fast-path for cases where no listener is registered
    if (listeners.size === 0) {
        return false;
    }
    const listenersForEvent = listeners.get(event);
    if (listenersForEvent !== undefined) {
        queueMicrotask(() => {
            for (const listener of listenersForEvent) {
                listener(...args);
            }
        });
        return true;
    }
    return false;
}
/**
 * Simple and efficient `EventEmitter` abstraction (following conventions from
 * Node.js) allowing partially typed event emitting. The set of event names is
 * specified as a type parameter while instantiating the event emitter.
 */
export class EventEmitter {
    constructor() {
        this.onceListeners = new Map();
        this.onListeners = new Map();
    }
    /**
     * Register an event listener for `event`.
     */
    on(event, callback) {
        registerCallback(event, callback, this.onListeners);
    }
    /**
     * Register an event listener for `event`; but only listen to first instance
     * of this event. The listener is automatically deleted afterwards.
     */
    once(event, callback) {
        registerCallback(event, callback, this.onceListeners);
    }
    /**
     * Remove `callback` from list of listeners for `event`.
     */
    unsubscribe(event, callback) {
        unregisterCallback(event, callback, this.onListeners);
        unregisterCallback(event, callback, this.onceListeners);
    }
    /**
     * Emit an event. Call all registered listeners to this event.
     */
    emit(event, ...args) {
        triggerCallback(event, args, this.onListeners);
        if (triggerCallback(event, args, this.onceListeners) === true) {
            this.onceListeners.delete(event);
        }
    }
}
//# sourceMappingURL=events.js.map