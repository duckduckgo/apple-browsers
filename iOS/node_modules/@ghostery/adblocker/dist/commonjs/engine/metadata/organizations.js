"use strict";
/*!
 * Copyright (c) 2017-present Ghostery GmbH. All rights reserved.
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */
Object.defineProperty(exports, "__esModule", { value: true });
exports.isValid = isValid;
exports.getKey = getKey;
exports.getSerializedSize = getSerializedSize;
exports.serialize = serialize;
exports.deserialize = deserialize;
exports.createMap = createMap;
const map_js_1 = require("../map.js");
const data_view_js_1 = require("../../data-view.js");
const utils_js_1 = require("../../utils.js");
/**
 * This function takes an object representing an organization from TrackerDB
 * dump and validates its shape. The result is the same object, but strongly
 * typed.
 */
function isValid(organization) {
    if (organization === null) {
        return false;
    }
    if (typeof organization !== 'object') {
        return false;
    }
    const { key, name, description, country, website_url: websiteUrl, privacy_policy_url: privacyPolicyUrl, privacy_contact: privacyContact, ghostery_id: ghosteryId, } = organization;
    if (typeof key !== 'string') {
        return false;
    }
    if (typeof name !== 'string') {
        return false;
    }
    if (description !== null && typeof description !== 'string') {
        return false;
    }
    if (country !== null && typeof country !== 'string') {
        return false;
    }
    if (websiteUrl !== null && typeof websiteUrl !== 'string') {
        return false;
    }
    if (privacyPolicyUrl !== null && typeof privacyPolicyUrl !== 'string') {
        return false;
    }
    if (privacyContact !== null && typeof privacyContact !== 'string') {
        return false;
    }
    if (ghosteryId !== null && typeof ghosteryId !== 'string') {
        return false;
    }
    return true;
}
function getKey(organization) {
    return (0, utils_js_1.fastHash)(organization.key);
}
function getSerializedSize(organization) {
    return ((0, data_view_js_1.sizeOfUTF8)(organization.key) +
        (0, data_view_js_1.sizeOfUTF8)(organization.name) +
        (0, data_view_js_1.sizeOfUTF8)(organization.description || '') +
        (0, data_view_js_1.sizeOfUTF8)(organization.website_url || '') +
        (0, data_view_js_1.sizeOfUTF8)(organization.country || '') +
        (0, data_view_js_1.sizeOfUTF8)(organization.privacy_policy_url || '') +
        (0, data_view_js_1.sizeOfUTF8)(organization.privacy_contact || '') +
        (0, data_view_js_1.sizeOfUTF8)(organization.ghostery_id || ''));
}
function serialize(organization, view) {
    view.pushUTF8(organization.key);
    view.pushUTF8(organization.name);
    view.pushUTF8(organization.description || '');
    view.pushUTF8(organization.website_url || '');
    view.pushUTF8(organization.country || '');
    view.pushUTF8(organization.privacy_policy_url || '');
    view.pushUTF8(organization.privacy_contact || '');
    view.pushUTF8(organization.ghostery_id || '');
}
function deserialize(view) {
    return {
        key: view.getUTF8(),
        name: view.getUTF8(),
        description: view.getUTF8() || null,
        website_url: view.getUTF8() || null,
        country: view.getUTF8() || null,
        privacy_policy_url: view.getUTF8() || null,
        privacy_contact: view.getUTF8() || null,
        ghostery_id: view.getUTF8() || null,
    };
}
function createMap(organizations) {
    return new map_js_1.CompactMap({
        getSerializedSize,
        getKeys: (organization) => [getKey(organization)],
        serialize,
        deserialize,
        values: organizations,
    });
}
//# sourceMappingURL=organizations.js.map