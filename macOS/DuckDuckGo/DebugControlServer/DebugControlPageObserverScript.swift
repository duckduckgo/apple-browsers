//
//  DebugControlPageObserverScript.swift
//
//  Copyright © 2025 DuckDuckGo. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

#if DEBUG

import Foundation

enum DebugControlPageObserverScript {

    static let messageName = "ddgDebugControl"

    static let source = """
    (function () {
        if (window.__ddgDebugControlInstalled) { return; }
        window.__ddgDebugControlInstalled = true;

        const handler = () => {
            try {
                return webkit.messageHandlers.\(messageName);
            } catch (e) {
                return null;
            }
        };

        const post = (payload) => {
            const target = handler();
            if (!target) { return; }
            try {
                payload.url = location.href;
                payload.frame = window === window.top ? 'main' : 'sub';
                target.postMessage(payload);
            } catch (e) {}
        };

        const describe = (value, depth) => {
            if (value === null) { return 'null'; }
            if (value === undefined) { return 'undefined'; }
            const type = typeof value;
            if (type === 'string') { return value; }
            if (type === 'number' || type === 'boolean' || type === 'bigint') { return String(value); }
            if (type === 'function') { return '[Function ' + (value.name || 'anonymous') + ']'; }
            if (type === 'symbol') { return value.toString(); }
            if (value instanceof Error) { return value.stack || (value.name + ': ' + value.message); }
            if (depth > 2) { return '[Object]'; }
            try {
                const seen = new WeakSet();
                return JSON.stringify(value, (key, nested) => {
                    if (nested && typeof nested === 'object') {
                        if (seen.has(nested)) { return '[Circular]'; }
                        seen.add(nested);
                    }
                    return nested;
                });
            } catch (e) {
                try {
                    return Object.prototype.toString.call(value);
                } catch (e2) {
                    return '[Unserializable]';
                }
            }
        };

        const levels = ['log', 'debug', 'info', 'warn', 'error', 'trace', 'table', 'dir'];
        for (const level of levels) {
            const original = console[level];
            if (typeof original !== 'function') { continue; }
            console[level] = function (...args) {
                post({
                    kind: 'console',
                    level: level,
                    text: args.map((arg) => describe(arg, 0)).join(' ')
                });
                return original.apply(console, args);
            };
        }

        window.addEventListener('error', (event) => {
            post({
                kind: 'console',
                level: 'uncaught',
                text: (event.error && (event.error.stack || event.error.message)) || event.message || 'script error',
                source: event.filename || '',
                line: event.lineno || 0,
                column: event.colno || 0
            });
        }, true);

        window.addEventListener('unhandledrejection', (event) => {
            const reason = event.reason;
            post({
                kind: 'console',
                level: 'unhandledrejection',
                text: describe(reason, 0)
            });
        }, true);

        const reportResourceEntries = (entries) => {
            for (const entry of entries) {
                post({
                    kind: 'resource',
                    name: entry.name,
                    initiatorType: entry.initiatorType,
                    startTime: entry.startTime,
                    duration: entry.duration,
                    transferSize: entry.transferSize,
                    responseStatus: typeof entry.responseStatus === 'number' ? entry.responseStatus : -1
                });
            }
        };

        try {
            const observer = new PerformanceObserver((list) => reportResourceEntries(list.getEntries()));
            observer.observe({ type: 'resource', buffered: true });
        } catch (e) {}
    })();
    """
}

#endif
