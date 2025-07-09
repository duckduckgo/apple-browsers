/*!
 * Copyright (c) 2017-present Ghostery GmbH. All rights reserved.
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */
declare class HidingBuilder {
}
declare class NetworkBuilder {
    private options;
    private prefix;
    private infix;
    private suffix;
    private redirect;
    private blockRequestsWithType;
    images(): NetworkBuilder;
    scripts(): NetworkBuilder;
    frames(): NetworkBuilder;
    fonts(): NetworkBuilder;
    medias(): NetworkBuilder;
    styles(): NetworkBuilder;
    redirectTo(redirect: string): NetworkBuilder;
    urlContains(infix: string): NetworkBuilder;
    urlStartsWith(prefix: string): NetworkBuilder;
    urlEndsWith(suffix: string): NetworkBuilder;
    withHostname(hostname: string): NetworkBuilder;
    toString(): string;
}
export declare function block(): NetworkBuilder;
export declare function hide(): HidingBuilder;
export {};
//# sourceMappingURL=dsl.d.ts.map