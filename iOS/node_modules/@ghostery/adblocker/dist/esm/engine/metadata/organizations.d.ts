/*!
 * Copyright (c) 2017-present Ghostery GmbH. All rights reserved.
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */
import { CompactMap } from '../map.js';
import { StaticDataView } from '../../data-view.js';
export interface IOrganization {
    key: string;
    name: string;
    description: string | null;
    website_url: string | null;
    country: string | null;
    privacy_policy_url: string | null;
    privacy_contact: string | null;
    ghostery_id: string | null;
}
/**
 * This function takes an object representing an organization from TrackerDB
 * dump and validates its shape. The result is the same object, but strongly
 * typed.
 */
export declare function isValid(organization: any): organization is IOrganization;
export declare function getKey(organization: {
    key: string;
}): number;
export declare function getSerializedSize(organization: IOrganization): number;
export declare function serialize(organization: IOrganization, view: StaticDataView): void;
export declare function deserialize(view: StaticDataView): IOrganization;
export declare function createMap(organizations: IOrganization[]): CompactMap<IOrganization>;
//# sourceMappingURL=organizations.d.ts.map