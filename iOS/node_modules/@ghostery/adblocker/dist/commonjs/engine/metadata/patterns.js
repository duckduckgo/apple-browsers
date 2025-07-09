"use strict";
/*!
 * Copyright (c) 2017-present Ghostery GmbH. All rights reserved.
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.isValid = isValid;
exports.getKeys = getKeys;
exports.getSerializedSize = getSerializedSize;
exports.serialize = serialize;
exports.deserialize = deserialize;
exports.createMap = createMap;
const map_js_1 = require("../map.js");
const data_view_js_1 = require("../../data-view.js");
const network_js_1 = __importDefault(require("../../filters/network.js"));
/**
 * This function takes an object representing a pattern from TrackerDB dump
 * and validates its shape. The result is the same object, but strongly typed.
 */
function isValid(pattern) {
    if (pattern === null) {
        return false;
    }
    if (typeof pattern !== 'object') {
        return false;
    }
    const { key, name, category, organization, alias, website_url: websiteUrl, domains, filters, } = pattern;
    if (typeof key !== 'string') {
        return false;
    }
    if (typeof name !== 'string') {
        return false;
    }
    if (typeof category !== 'string') {
        return false;
    }
    if (organization !== null && typeof organization !== 'string') {
        return false;
    }
    if (typeof alias !== 'string' && alias !== null) {
        return false;
    }
    if (websiteUrl !== null && typeof websiteUrl !== 'string') {
        return false;
    }
    if (!Array.isArray(domains) || !domains.every((domain) => typeof domain === 'string')) {
        return false;
    }
    if (!Array.isArray(filters) || !filters.every((filter) => typeof filter === 'string')) {
        return false;
    }
    return true;
}
function getKeys(pattern) {
    const keys = [];
    for (const filter of pattern.filters) {
        const parsedFilter = network_js_1.default.parse(filter);
        if (parsedFilter !== null) {
            keys.push(parsedFilter.getId());
        }
    }
    for (const domain of pattern.domains) {
        const parsedFilter = network_js_1.default.parse(`||${domain}^`);
        if (parsedFilter !== null) {
            keys.push(parsedFilter.getId());
        }
    }
    return [...new Set(keys)];
}
function getSerializedSize(pattern) {
    let sizeOfDomains = (0, data_view_js_1.sizeOfLength)(pattern.domains.length);
    for (const domain of pattern.domains) {
        sizeOfDomains += (0, data_view_js_1.sizeOfUTF8)(domain);
    }
    let sizeOfFilters = (0, data_view_js_1.sizeOfLength)(pattern.filters.length);
    for (const filter of pattern.filters) {
        sizeOfFilters += (0, data_view_js_1.sizeOfUTF8)(filter);
    }
    return ((0, data_view_js_1.sizeOfUTF8)(pattern.key) +
        (0, data_view_js_1.sizeOfUTF8)(pattern.name) +
        (0, data_view_js_1.sizeOfUTF8)(pattern.category) +
        (0, data_view_js_1.sizeOfUTF8)(pattern.organization || '') +
        (0, data_view_js_1.sizeOfUTF8)(pattern.alias || '') +
        (0, data_view_js_1.sizeOfUTF8)(pattern.website_url || '') +
        (0, data_view_js_1.sizeOfUTF8)(pattern.ghostery_id || '') +
        sizeOfDomains +
        sizeOfFilters);
}
function serialize(pattern, view) {
    view.pushUTF8(pattern.key);
    view.pushUTF8(pattern.name);
    view.pushUTF8(pattern.category);
    view.pushUTF8(pattern.organization || '');
    view.pushUTF8(pattern.alias || '');
    view.pushUTF8(pattern.website_url || '');
    view.pushUTF8(pattern.ghostery_id || '');
    view.pushLength(pattern.domains.length);
    for (const domain of pattern.domains) {
        view.pushUTF8(domain);
    }
    view.pushLength(pattern.filters.length);
    for (const filter of pattern.filters) {
        view.pushUTF8(filter);
    }
}
function deserialize(view) {
    const key = view.getUTF8();
    const name = view.getUTF8();
    const category = view.getUTF8();
    const organization = view.getUTF8() || null;
    const alias = view.getUTF8() || null;
    const website_url = view.getUTF8() || null;
    const ghostery_id = view.getUTF8() || null;
    const numberOfDomains = view.getLength();
    const domains = [];
    for (let i = 0; i < numberOfDomains; i += 1) {
        domains.push(view.getUTF8());
    }
    const numberOfFilters = view.getLength();
    const filters = [];
    for (let i = 0; i < numberOfFilters; i += 1) {
        filters.push(view.getUTF8());
    }
    return {
        key,
        name,
        category,
        organization,
        alias,
        website_url,
        ghostery_id,
        domains,
        filters,
    };
}
function createMap(patterns) {
    return new map_js_1.CompactMap({
        getSerializedSize,
        getKeys,
        serialize,
        deserialize,
        values: patterns,
    });
}
//# sourceMappingURL=patterns.js.map