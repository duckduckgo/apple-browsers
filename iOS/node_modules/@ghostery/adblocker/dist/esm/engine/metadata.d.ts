/*!
 * Copyright (c) 2017-present Ghostery GmbH. All rights reserved.
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */
import { CompactMap } from './map.js';
import { StaticDataView } from '../data-view.js';
import NetworkFilter from '../filters/network.js';
import { ICategory } from './metadata/categories.js';
import { IOrganization } from './metadata/organizations.js';
import { IPattern } from './metadata/patterns.js';
export interface IPatternLookupResult {
    pattern: IPattern;
    organization: IOrganization | null;
    category: ICategory | null;
}
export declare class Metadata {
    static deserialize(buffer: StaticDataView): Metadata;
    organizations: CompactMap<IOrganization>;
    categories: CompactMap<ICategory>;
    patterns: CompactMap<IPattern>;
    constructor(rawTrackerDB: any);
    getCategories(): ICategory[];
    getOrganizations(): IOrganization[];
    getPatterns(): IPattern[];
    /**
     * Estimate the total serialized size of this Metadata instance.
     */
    getSerializedSize(): number;
    /**
     * Serialize this instance of Metadata into `view`
     */
    serialize(buffer: StaticDataView): void;
    /**
     * Given an instance of NetworkFilter, retrieve pattern, organization and
     * category information.
     */
    fromFilter(filter: NetworkFilter): IPatternLookupResult[];
    /**
     * Given a domain, retrieve pattern, organization and category information.
     */
    fromDomain(domain: string): IPatternLookupResult[];
    /**
     * Given an `id` from filter, retrieve using the NetworkFilter.getId() method,
     * lookup associated patterns (including organization and category) in an
     * efficient way.
     */
    fromId(id: number): IPatternLookupResult[];
}
//# sourceMappingURL=metadata.d.ts.map