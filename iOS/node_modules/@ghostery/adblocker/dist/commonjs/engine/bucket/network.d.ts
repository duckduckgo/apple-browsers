/*!
 * Copyright (c) 2017-present Ghostery GmbH. All rights reserved.
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */
import Config from '../../config.js';
import { StaticDataView } from '../../data-view.js';
import NetworkFilter from '../../filters/network.js';
import Request from '../../request.js';
import ReverseIndex from '../reverse-index.js';
import FiltersContainer from './filters.js';
/**
 * Accelerating data structure for network filters matching.
 */
export default class NetworkFilterBucket {
    static deserialize(buffer: StaticDataView, config: Config): NetworkFilterBucket;
    index: ReverseIndex<NetworkFilter>;
    badFilters: FiltersContainer<NetworkFilter>;
    private badFiltersIds;
    constructor({ filters, config }: {
        filters?: NetworkFilter[];
        config: Config;
    });
    getFilters(): NetworkFilter[];
    update(newFilters: NetworkFilter[], removedFilters: Set<number> | undefined): void;
    getSerializedSize(): number;
    serialize(buffer: StaticDataView): void;
    matchAll(request: Request, isFilterExcluded?: (filter: NetworkFilter) => boolean): NetworkFilter[];
    match(request: Request, isFilterExcluded?: (filter: NetworkFilter) => boolean): NetworkFilter | undefined;
    /**
     * Given a matching filter, check if it is disabled by a $badfilter.
     */
    private isFilterDisabled;
}
//# sourceMappingURL=network.d.ts.map