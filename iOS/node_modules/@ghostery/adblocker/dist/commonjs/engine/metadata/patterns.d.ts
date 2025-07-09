/*!
 * Copyright (c) 2017-present Ghostery GmbH. All rights reserved.
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */
import { CompactMap } from '../map.js';
import { StaticDataView } from '../../data-view.js';
export interface IPattern {
    readonly key: string;
    readonly name: string;
    readonly category: string;
    readonly organization: string | null;
    readonly alias: string | null;
    readonly website_url: string | null;
    readonly ghostery_id: string | null;
    readonly domains: string[];
    readonly filters: string[];
}
/**
 * This function takes an object representing a pattern from TrackerDB dump
 * and validates its shape. The result is the same object, but strongly typed.
 */
export declare function isValid(pattern: any): pattern is IPattern;
export declare function getKeys(pattern: IPattern): number[];
export declare function getSerializedSize(pattern: IPattern): number;
export declare function serialize(pattern: IPattern, view: StaticDataView): void;
export declare function deserialize(view: StaticDataView): IPattern;
export declare function createMap(patterns: IPattern[]): CompactMap<IPattern>;
//# sourceMappingURL=patterns.d.ts.map