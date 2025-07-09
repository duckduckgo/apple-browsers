/*!
 * Copyright (c) 2017-present Ghostery GmbH. All rights reserved.
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */
export declare const EXTENDED_PSEUDO_CLASSES: Set<string>;
export declare const PSEUDO_CLASSES: Set<string>;
export declare const PSEUDO_ELEMENTS: Set<string>;
export declare enum SelectorType {
    Normal = 0,
    Extended = 1,
    Invalid = 2
}
export declare function classifySelector(selector: string): SelectorType;
//# sourceMappingURL=extended.d.ts.map