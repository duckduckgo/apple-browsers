"use strict";
/**
 * The MIT License (MIT)
 *
 * Copyright (c) Feross Aboukhadijeh
 *
 * Originally from: https://github.com/feross/queue-microtask
 */
Object.defineProperty(exports, "__esModule", { value: true });
exports.queueMicrotask = void 0;
let promise;
exports.queueMicrotask = typeof window !== 'undefined' && typeof window.queueMicrotask === 'function'
    ? (cb) => window.queueMicrotask(cb)
    : // reuse resolved promise, and allocate it lazily
        (cb) => (promise || (promise = Promise.resolve())).then(cb).catch((err) => setTimeout(() => {
            throw err;
        }, 0));
//# sourceMappingURL=queue-microtask.js.map