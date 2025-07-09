/*!
 * Copyright (c) 2017-present Ghostery GmbH. All rights reserved.
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */
interface FetchResponse {
    text: () => Promise<string>;
    arrayBuffer: () => Promise<ArrayBuffer>;
    json: () => Promise<any>;
}
export type Fetch = (url: string) => Promise<FetchResponse>;
/**
 * Built-in fetch helpers can be used to initialize the adblocker from
 * pre-built presets or raw lists (fetched from multiple sources). In case of
 * failure (e.g. timeout), the whole process of initialization fails. Timeouts
 * are not so uncommon, and retrying to fetch usually succeeds.
 */
export declare function fetchWithRetry(fetch: Fetch, url: string): Promise<FetchResponse>;
export declare const adsLists: string[];
export declare const adsAndTrackingLists: string[];
export declare const fullLists: string[];
/**
 * Fetch latest version of enabledByDefault blocking lists.
 */
export declare function fetchLists(fetch: Fetch, urls: string[]): Promise<string[]>;
/**
 * Fetch latest version of uBlock Origin's resources, used to inject scripts in
 * the page or redirect request to data URLs.
 */
export declare function fetchResources(fetch: Fetch): Promise<string>;
export {};
//# sourceMappingURL=fetch.d.ts.map