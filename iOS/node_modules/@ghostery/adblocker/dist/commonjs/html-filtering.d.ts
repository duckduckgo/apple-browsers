/*!
 * Copyright (c) 2017-present Ghostery GmbH. All rights reserved.
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */
export type HTMLModifier = readonly [RegExp, string];
export type HTMLSelector = readonly ['script', readonly string[]] | readonly ['replace', HTMLModifier];
export declare function extractHTMLSelectorFromRule(rule: string): HTMLSelector | undefined;
export declare function extractTagsFromHtml(html: string, tag: string): [[number, string][], string, string];
type Patterns = readonly [readonly string[], readonly RegExp[]][];
export declare function extractSelectorsFromRules(filter: HTMLSelector[]): Patterns;
export declare function selectTagsToRemove(patterns: Patterns, tags: [number, string][]): [number, string][];
export declare function removeTagsFromHtml(html: string, toRemove: [number, string][]): string;
export default class StreamingHtmlFilter {
    private buffer;
    private readonly patterns;
    private readonly modifiers;
    constructor(selectors: HTMLSelector[]);
    flush(applyHTMLFiltering?: boolean): string;
    write(chunk: string): string;
}
export {};
//# sourceMappingURL=html-filtering.d.ts.map