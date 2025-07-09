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
exports.Metadata = void 0;
const map_js_1 = require("./map.js");
const network_js_1 = __importDefault(require("../filters/network.js"));
const categories_js_1 = require("./metadata/categories.js");
const organizations_js_1 = require("./metadata/organizations.js");
const patterns_js_1 = require("./metadata/patterns.js");
// Optionally, we can also compress their names and descriptions but I think that should not be necessary as it's probably pretty small.
// Usage in MV3 extension
// ======================
// 1. The extension will load the binary engine containing metadata and store it locally
// 2. Either on webRequest events or DNR filter IDs (requires to synchronize the IDs), we tag the request with their metadata
// (2.) At runtime, we will either feed it a request and we expect to get metadata (match, get filter, then from filter ID, get metadata)
//    Or we feed it the filter ID directly, from the DNR engine (but then it means we need to use the filter hash as an ID there as well and hope for no collision)
class Metadata {
    static deserialize(buffer) {
        const metadata = new Metadata(null);
        metadata.categories = map_js_1.CompactMap.deserialize(buffer, categories_js_1.deserialize);
        metadata.organizations = map_js_1.CompactMap.deserialize(buffer, organizations_js_1.deserialize);
        metadata.patterns = map_js_1.CompactMap.deserialize(buffer, patterns_js_1.deserialize);
        return metadata;
    }
    constructor(rawTrackerDB) {
        if (!rawTrackerDB) {
            this.organizations = (0, organizations_js_1.createMap)([]);
            this.categories = (0, categories_js_1.createMap)([]);
            this.patterns = (0, patterns_js_1.createMap)([]);
            return;
        }
        const { patterns: rawPatterns, organizations: rawOrganizations, categories: rawCategories, } = rawTrackerDB;
        // Type-check categories
        const categories = [];
        if (typeof rawCategories === 'object') {
            for (const [key, category] of Object.entries(rawCategories)) {
                if (typeof category !== 'object') {
                    continue;
                }
                const categoryWithKey = { key, ...category };
                if ((0, categories_js_1.isValid)(categoryWithKey)) {
                    categories.push(categoryWithKey);
                }
                else {
                    console.error('?? invalid category', categoryWithKey);
                }
            }
        }
        this.categories = (0, categories_js_1.createMap)(categories);
        // Type-check organizations
        const organizations = [];
        if (typeof rawOrganizations === 'object') {
            for (const [key, organization] of Object.entries(rawOrganizations)) {
                if (typeof organization !== 'object') {
                    continue;
                }
                const organizationWithKey = { key, ...organization };
                if ((0, organizations_js_1.isValid)(organizationWithKey)) {
                    organizations.push(organizationWithKey);
                }
                else {
                    console.error('?? invalid organization', organizationWithKey);
                }
            }
        }
        this.organizations = (0, organizations_js_1.createMap)(organizations);
        // Type-check patterns
        const patterns = [];
        if (typeof rawPatterns === 'object') {
            for (const [key, pattern] of Object.entries(rawPatterns)) {
                if (typeof pattern !== 'object') {
                    continue;
                }
                const patternWithKey = { key, ...pattern };
                if ((0, patterns_js_1.isValid)(patternWithKey)) {
                    patterns.push(patternWithKey);
                }
                else {
                    console.error('?? invalid pattern', patternWithKey);
                }
            }
        }
        this.patterns = (0, patterns_js_1.createMap)(patterns);
    }
    getCategories() {
        return this.categories.getValues();
    }
    getOrganizations() {
        return this.organizations.getValues();
    }
    getPatterns() {
        return this.patterns.getValues();
    }
    /**
     * Estimate the total serialized size of this Metadata instance.
     */
    getSerializedSize() {
        return (this.categories.getSerializedSize() +
            this.organizations.getSerializedSize() +
            this.patterns.getSerializedSize());
    }
    /**
     * Serialize this instance of Metadata into `view`
     */
    serialize(buffer) {
        this.categories.serialize(buffer);
        this.organizations.serialize(buffer);
        this.patterns.serialize(buffer);
    }
    /**
     * Given an instance of NetworkFilter, retrieve pattern, organization and
     * category information.
     */
    fromFilter(filter) {
        return this.fromId(filter.getId());
    }
    /**
     * Given a domain, retrieve pattern, organization and category information.
     */
    fromDomain(domain) {
        const domainParts = domain.split('.');
        for (; domainParts.length >= 2; domainParts.shift()) {
            const subdomain = domainParts.join('.');
            const parsedDomainFilter = network_js_1.default.parse(`||${subdomain}^`);
            if (parsedDomainFilter === null) {
                continue;
            }
            const patterns = this.fromId(parsedDomainFilter.getId());
            if (patterns.length > 0) {
                return patterns;
            }
        }
        return [];
    }
    /**
     * Given an `id` from filter, retrieve using the NetworkFilter.getId() method,
     * lookup associated patterns (including organization and category) in an
     * efficient way.
     */
    fromId(id) {
        var _a, _b;
        const results = [];
        for (const pattern of this.patterns.get(id)) {
            results.push({
                pattern,
                category: (_a = this.categories.get((0, categories_js_1.getKey)({ key: pattern.category }))) === null || _a === void 0 ? void 0 : _a[0],
                organization: pattern.organization !== null
                    ? (_b = this.organizations.get((0, organizations_js_1.getKey)({ key: pattern.organization }))) === null || _b === void 0 ? void 0 : _b[0]
                    : null,
            });
        }
        return results;
    }
}
exports.Metadata = Metadata;
//# sourceMappingURL=metadata.js.map