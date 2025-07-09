/*!
 * Copyright (c) 2017-present Ghostery GmbH. All rights reserved.
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */
/**
 * Simple and efficient `EventEmitter` abstraction (following conventions from
 * Node.js) allowing partially typed event emitting. The set of event names is
 * specified as a type parameter while instantiating the event emitter.
 */
export declare class EventEmitter<EventHandlers extends Record<string, (...args: any[]) => any>, EventNames extends keyof EventHandlers = keyof EventHandlers> {
    private onceListeners;
    private onListeners;
    /**
     * Register an event listener for `event`.
     */
    on<EventName extends EventNames>(event: EventName, callback: EventHandlers[EventName]): void;
    /**
     * Register an event listener for `event`; but only listen to first instance
     * of this event. The listener is automatically deleted afterwards.
     */
    once<EventName extends EventNames>(event: EventName, callback: EventHandlers[EventName]): void;
    /**
     * Remove `callback` from list of listeners for `event`.
     */
    unsubscribe<EventName extends EventNames>(event: EventName, callback: EventHandlers[EventName]): void;
    /**
     * Emit an event. Call all registered listeners to this event.
     */
    emit<EventName extends EventNames>(event: EventName, ...args: Parameters<EventHandlers[EventName]>): void;
}
//# sourceMappingURL=events.d.ts.map