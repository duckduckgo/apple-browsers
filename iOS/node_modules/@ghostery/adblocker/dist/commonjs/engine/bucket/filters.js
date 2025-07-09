"use strict";
/*!
 * Copyright (c) 2017-present Ghostery GmbH. All rights reserved.
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */
Object.defineProperty(exports, "__esModule", { value: true });
const data_view_js_1 = require("../../data-view.js");
// Empty filters is 4 bytes because we need at least one 32 bits number to keep
// track of the number of filters in the container. If there is no filter then
// the number will be 0.
const EMPTY_FILTERS = new Uint8Array(4);
/**
 * Generic filters container (for both CosmeticFilter and NetworkFilter
 * instances). This abstracts away some of the logic to serialize/lazy-load
 * lists of filters (which is useful for things like generic cosmetic filters
 * or $badfilter).
 */
class FiltersContainer {
    static deserialize(buffer, deserialize, config) {
        const container = new FiltersContainer({ deserialize, config, filters: [] });
        container.filters = buffer.getBytes();
        return container;
    }
    constructor({ config, deserialize, filters, }) {
        this.deserialize = deserialize;
        this.filters = EMPTY_FILTERS;
        this.config = config;
        if (filters.length !== 0) {
            this.update(filters, undefined);
        }
    }
    /**
     * Update filters based on `newFilters` and `removedFilters`.
     */
    update(newFilters, removedFilters) {
        // Estimate size of the buffer we will need to store filters. This avoids
        // having to allocate a big chunk of memory up-front if it's not needed.
        // We start with the current size of `this.filters` then update it with
        // removed/added filters.
        let bufferSizeEstimation = this.filters.byteLength;
        let selected = [];
        const compression = this.config.enableCompression;
        // Add existing rules (removing the ones with ids in `removedFilters`)
        const currentFilters = this.getFilters();
        if (currentFilters.length !== 0) {
            // If no filter was removed (we only add new ones), we don't need to
            // filter out removed existing filters. So we just assign the array to
            // `selected` directly to save a bit of effort.
            if (removedFilters === undefined || removedFilters.size === 0) {
                selected = currentFilters;
            }
            else {
                // There might be some removed selected filters, so we iterate through
                // them and make sure we keep only the ones not having been deleted.
                for (const filter of currentFilters) {
                    if (removedFilters.has(filter.getId()) === false) {
                        selected.push(filter);
                    }
                    else {
                        bufferSizeEstimation -= filter.getSerializedSize(compression);
                    }
                }
            }
        }
        // If `selected` and `currentFilters` have the same length then no filter was removed.
        const storedFiltersRemoved = selected.length !== currentFilters.length;
        // Add new rules.
        const numberOfExistingFilters = selected.length;
        for (const filter of newFilters) {
            bufferSizeEstimation += filter.getSerializedSize(compression);
            selected.push(filter);
        }
        // Check if any new filter was added in `selected` (from `newFilters`).
        const storedFiltersAdded = selected.length > numberOfExistingFilters;
        // If selected changed, then update the compact representation of filters.
        if (selected.length === 0) {
            this.filters = EMPTY_FILTERS;
        }
        else if (storedFiltersAdded === true || storedFiltersRemoved === true) {
            // Store filters in their compact form
            const buffer = data_view_js_1.StaticDataView.allocate(bufferSizeEstimation, this.config);
            buffer.pushUint32(selected.length);
            // When we run in `debug` mode, we enable fully deterministic updates of
            // internal data-structure. To this effect, we sort all filters before
            // insertion.
            if (this.config.debug === true) {
                selected.sort((f1, f2) => f1.getId() - f2.getId());
            }
            for (const filter of selected) {
                filter.serialize(buffer);
            }
            // Update internals
            this.filters = buffer.buffer;
        }
    }
    getSerializedSize() {
        return (0, data_view_js_1.sizeOfBytes)(this.filters, false /* no alignement */);
    }
    serialize(buffer) {
        buffer.pushBytes(this.filters);
    }
    getFilters() {
        // No filter stored in the container
        if (this.filters.byteLength <= 4) {
            return [];
        }
        // Load all filters in memory and store them in `cache`
        const filters = [];
        const buffer = data_view_js_1.StaticDataView.fromUint8Array(this.filters, this.config);
        const numberOfFilters = buffer.getUint32();
        for (let i = 0; i < numberOfFilters; i += 1) {
            filters.push(this.deserialize(buffer));
        }
        return filters;
    }
}
exports.default = FiltersContainer;
//# sourceMappingURL=filters.js.map