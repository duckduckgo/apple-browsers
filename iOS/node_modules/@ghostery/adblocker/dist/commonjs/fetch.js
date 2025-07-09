"use strict";
/*!
 * Copyright (c) 2017-present Ghostery GmbH. All rights reserved.
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */
Object.defineProperty(exports, "__esModule", { value: true });
exports.fullLists = exports.adsAndTrackingLists = exports.adsLists = void 0;
exports.fetchWithRetry = fetchWithRetry;
exports.fetchLists = fetchLists;
exports.fetchResources = fetchResources;
/**
 * Built-in fetch helpers can be used to initialize the adblocker from
 * pre-built presets or raw lists (fetched from multiple sources). In case of
 * failure (e.g. timeout), the whole process of initialization fails. Timeouts
 * are not so uncommon, and retrying to fetch usually succeeds.
 */
function fetchWithRetry(fetch, url) {
    let retry = 3;
    // Wrap `fetch` into a lightweight retry function which makes sure that if
    // fetching fails, it can be retried up to three times. Failure can happen if
    // the remote server times-out, but retrying fetching of the same URL will
    // usually succeed.
    const fetchWrapper = () => {
        return fetch(url).catch((ex) => {
            if (retry > 0) {
                retry -= 1;
                return new Promise((resolve, reject) => {
                    setTimeout(() => {
                        fetchWrapper().then(resolve).catch(reject);
                    }, 500);
                });
            }
            throw ex;
        });
    };
    return fetchWrapper();
}
function fetchResource(fetch, url) {
    return fetchWithRetry(fetch, url).then((response) => response.text());
}
const PREFIX = 'https://raw.githubusercontent.com/ghostery/adblocker/master/packages/adblocker/assets';
exports.adsLists = [
    `${PREFIX}/easylist/easylist.txt`,
    `${PREFIX}/peter-lowe/serverlist.txt`,
    `${PREFIX}/ublock-origin/badware.txt`,
    `${PREFIX}/ublock-origin/filters-2020.txt`,
    `${PREFIX}/ublock-origin/filters-2021.txt`,
    `${PREFIX}/ublock-origin/filters-2022.txt`,
    `${PREFIX}/ublock-origin/filters-2023.txt`,
    `${PREFIX}/ublock-origin/filters-2024.txt`,
    `${PREFIX}/ublock-origin/filters.txt`,
    `${PREFIX}/ublock-origin/quick-fixes.txt`,
    `${PREFIX}/ublock-origin/resource-abuse.txt`,
    `${PREFIX}/ublock-origin/unbreak.txt`,
];
exports.adsAndTrackingLists = [
    ...exports.adsLists,
    `${PREFIX}/easylist/easyprivacy.txt`,
    `${PREFIX}/ublock-origin/privacy.txt`,
];
exports.fullLists = [
    ...exports.adsAndTrackingLists,
    `${PREFIX}/easylist/easylist-cookie.txt`,
    `${PREFIX}/ublock-origin/annoyances-others.txt`,
    `${PREFIX}/ublock-origin/annoyances-cookies.txt`,
];
/**
 * Fetch latest version of enabledByDefault blocking lists.
 */
function fetchLists(fetch, urls) {
    return Promise.all(urls.map((url) => fetchResource(fetch, url)));
}
/**
 * Fetch latest version of uBlock Origin's resources, used to inject scripts in
 * the page or redirect request to data URLs.
 */
function fetchResources(fetch) {
    return fetchResource(fetch, `${PREFIX}/ublock-origin/resources.json`);
}
//# sourceMappingURL=fetch.js.map