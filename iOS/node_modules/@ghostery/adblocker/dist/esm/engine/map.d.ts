/*!
 * Copyright (c) 2017-present Ghostery GmbH. All rights reserved.
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */
import { StaticDataView } from '../data-view.js';
/**
 * This is a simpler version of reverse-index data structure which implements
 * a simple Map-like class, backed by compact typed arrays. This means that
 * the structure can be serialized to a typed array very quickly and loaded
 * back instantly.
 */
export declare class CompactMap<T> {
    static deserialize<T>(buffer: StaticDataView, deserialize: (view: StaticDataView) => T): CompactMap<T>;
    private readonly cache;
    private bucketsIndex;
    private tokensLookupIndex;
    private valuesIndexStart;
    private numberOfValues;
    private view;
    private readonly deserializeValue;
    constructor({ serialize, deserialize, getKeys, getSerializedSize, values, }: {
        serialize: (value: T, view: StaticDataView) => void;
        deserialize: (view: StaticDataView) => T;
        getKeys: (value: T) => number[];
        getSerializedSize: (value: T) => number;
        values: T[];
    });
    private updateInternals;
    getValues(): T[];
    /**
     * Estimate the number of bytes needed to serialize this instance of `Map`.
     */
    getSerializedSize(): number;
    /**
     * Dump this index to `buffer`.
     */
    serialize(buffer: StaticDataView): void;
    get(key: number): T[];
}
//# sourceMappingURL=map.d.ts.map