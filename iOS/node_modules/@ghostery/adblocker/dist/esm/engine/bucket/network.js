/*!
 * Copyright (c) 2017-present Ghostery GmbH. All rights reserved.
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */
import NetworkFilter from '../../filters/network.js';
import { noopOptimizeNetwork, optimizeNetwork } from '../optimizer.js';
import ReverseIndex from '../reverse-index.js';
import FiltersContainer from './filters.js';
/**
 * Accelerating data structure for network filters matching.
 */
export default class NetworkFilterBucket {
    static deserialize(buffer, config) {
        const bucket = new NetworkFilterBucket({ config });
        bucket.index = ReverseIndex.deserialize(buffer, NetworkFilter.deserialize, config.enableOptimizations ? optimizeNetwork : noopOptimizeNetwork, config);
        bucket.badFilters = FiltersContainer.deserialize(buffer, NetworkFilter.deserialize, config);
        return bucket;
    }
    constructor({ filters = [], config }) {
        this.index = new ReverseIndex({
            config,
            deserialize: NetworkFilter.deserialize,
            filters: [],
            optimize: config.enableOptimizations ? optimizeNetwork : noopOptimizeNetwork,
        });
        this.badFiltersIds = null;
        this.badFilters = new FiltersContainer({
            config,
            deserialize: NetworkFilter.deserialize,
            filters: [],
        });
        if (filters.length !== 0) {
            this.update(filters, undefined);
        }
    }
    getFilters() {
        const filters = [];
        return filters.concat(this.badFilters.getFilters(), this.index.getFilters());
    }
    update(newFilters, removedFilters) {
        const badFilters = [];
        const remaining = [];
        for (const filter of newFilters) {
            if (filter.isBadFilter()) {
                badFilters.push(filter);
            }
            else {
                remaining.push(filter);
            }
        }
        this.badFilters.update(badFilters, removedFilters);
        this.index.update(remaining, removedFilters);
        this.badFiltersIds = null;
    }
    getSerializedSize() {
        return this.badFilters.getSerializedSize() + this.index.getSerializedSize();
    }
    serialize(buffer) {
        this.index.serialize(buffer);
        this.badFilters.serialize(buffer);
    }
    matchAll(request, isFilterExcluded) {
        const filters = [];
        this.index.iterMatchingFilters(request.getTokens(), (filter) => {
            if (filter.match(request) &&
                this.isFilterDisabled(filter) === false &&
                !(isFilterExcluded === null || isFilterExcluded === void 0 ? void 0 : isFilterExcluded(filter))) {
                filters.push(filter);
            }
            return true;
        });
        return filters;
    }
    match(request, isFilterExcluded) {
        let match;
        this.index.iterMatchingFilters(request.getTokens(), (filter) => {
            if (filter.match(request) &&
                this.isFilterDisabled(filter) === false &&
                !(isFilterExcluded === null || isFilterExcluded === void 0 ? void 0 : isFilterExcluded(filter))) {
                match = filter;
                return false;
            }
            return true;
        });
        return match;
    }
    /**
     * Given a matching filter, check if it is disabled by a $badfilter.
     */
    isFilterDisabled(filter) {
        // Lazily load information about bad filters in memory. The only thing we
        // keep in memory is the list of IDs from $badfilter (ignoring the
        // $badfilter option from mask). This allows to check if a matching filter
        // should be ignored just by doing a lookup in a set of IDs.
        if (this.badFiltersIds === null) {
            const badFilters = this.badFilters.getFilters();
            // Shortcut if there is no badfilter in this bucket
            if (badFilters.length === 0) {
                return false;
            }
            // Create in-memory list of disabled filter IDs
            const badFiltersIds = new Set();
            for (const badFilter of badFilters) {
                badFiltersIds.add(badFilter.getIdWithoutBadFilter());
            }
            this.badFiltersIds = badFiltersIds;
        }
        return this.badFiltersIds.has(filter.getId());
    }
}
//# sourceMappingURL=network.js.map