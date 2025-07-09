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
import CosmeticFilter from '../../filters/cosmetic.js';
import Request from '../../request.js';
import ReverseIndex from '../reverse-index.js';
export default class HTMLBucket {
    static deserialize(buffer: StaticDataView, config: Config): HTMLBucket;
    networkIndex: ReverseIndex<NetworkFilter>;
    exceptionsIndex: ReverseIndex<NetworkFilter>;
    cosmeticIndex: ReverseIndex<CosmeticFilter>;
    unhideIndex: ReverseIndex<CosmeticFilter>;
    private config;
    constructor({ filters, config, }: {
        filters?: (CosmeticFilter | NetworkFilter)[];
        config: Config;
    });
    update(newFilters: (NetworkFilter | CosmeticFilter)[], removedFilters: Set<number> | undefined): void;
    serialize(buffer: StaticDataView): void;
    getSerializedSize(): number;
    getHTMLFilters(request: Request, isFilterExcluded?: (filter: NetworkFilter | CosmeticFilter) => boolean): {
        networkFilters: NetworkFilter[];
        cosmeticFilters: CosmeticFilter[];
        exceptions: NetworkFilter[];
        unhides: CosmeticFilter[];
    };
    getFilters(): (NetworkFilter | CosmeticFilter)[];
}
//# sourceMappingURL=html.d.ts.map