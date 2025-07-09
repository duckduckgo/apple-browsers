/*!
 * Copyright (c) 2017-present Ghostery GmbH. All rights reserved.
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */
import { CompactMap } from '../map.js';
import { StaticDataView } from '../../data-view.js';
export interface ICategory {
    key: string;
    name: string;
    color: string;
    description: string;
}
export declare function isValid(category: any): category is ICategory;
export declare function getKey(category: {
    key: string;
}): number;
export declare function getSerializedSize(category: ICategory): number;
export declare function serialize(category: ICategory, view: StaticDataView): void;
export declare function deserialize(view: StaticDataView): ICategory;
export declare function createMap(categories: ICategory[]): CompactMap<ICategory>;
//# sourceMappingURL=categories.d.ts.map