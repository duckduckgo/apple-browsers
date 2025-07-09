/*!
 * Copyright (c) 2017-present Ghostery GmbH. All rights reserved.
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */
import { CompactMap } from '../map.js';
import { sizeOfUTF8 } from '../../data-view.js';
import { fastHash } from '../../utils.js';
export function isValid(category) {
    if (category === null) {
        return false;
    }
    if (typeof category !== 'object') {
        return false;
    }
    const { key, name, color, description } = category;
    if (typeof key !== 'string') {
        return false;
    }
    if (typeof name !== 'string') {
        return false;
    }
    if (typeof color !== 'string') {
        return false;
    }
    if (typeof description !== 'string') {
        return false;
    }
    return true;
}
export function getKey(category) {
    return fastHash(category.key);
}
export function getSerializedSize(category) {
    return (sizeOfUTF8(category.key) +
        sizeOfUTF8(category.name) +
        sizeOfUTF8(category.color) +
        sizeOfUTF8(category.description));
}
export function serialize(category, view) {
    view.pushUTF8(category.key);
    view.pushUTF8(category.name);
    view.pushUTF8(category.color);
    view.pushUTF8(category.description);
}
export function deserialize(view) {
    return {
        key: view.getUTF8(),
        name: view.getUTF8(),
        color: view.getUTF8(),
        description: view.getUTF8(),
    };
}
export function createMap(categories) {
    return new CompactMap({
        getSerializedSize,
        getKeys: (category) => [getKey(category)],
        serialize,
        deserialize,
        values: categories,
    });
}
//# sourceMappingURL=categories.js.map