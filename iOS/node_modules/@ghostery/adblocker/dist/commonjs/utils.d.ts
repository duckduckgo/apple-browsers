/*!
 * Copyright (c) 2017-present Ghostery GmbH. All rights reserved.
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */
import { TokensBuffer } from './tokens-buffer.js';
export declare const HASH_INTERNAL_MULT = 37;
export declare const HASH_SEED = 5011;
/***************************************************************************
 *  Bitwise helpers
 * ************************************************************************* */
export declare function bitCount(n: number): number;
export declare function getBit(n: number, mask: number): boolean;
export declare function setBit(n: number, mask: number): number;
export declare function clearBit(n: number, mask: number): number;
export declare function fastHashBetween(str: string, begin: number, end: number): number;
export declare function fastHash(str: string): number;
export declare function hashStrings(strings: string[]): Uint32Array;
export declare function fastStartsWith(haystack: string, needle: string): boolean;
export declare function fastStartsWithFrom(haystack: string, needle: string, start: number): boolean;
export declare function isDigit(ch: number): boolean;
export declare function isAlpha(ch: number): boolean;
export declare function tokenizeWithWildcardsInPlace(pattern: string, skipFirstToken: boolean, skipLastToken: boolean, buffer: TokensBuffer): void;
export declare function tokenizeInPlace(pattern: string, skipFirstToken: boolean, skipLastToken: boolean, buffer: TokensBuffer): void;
export declare function tokenizeNoSkipInPlace(pattern: string, buffer: TokensBuffer): void;
export declare function tokenizeNoSkip(pattern: string): Uint32Array;
export declare function tokenizeWithWildcards(pattern: string, skipFirstToken: boolean, skipLastToken: boolean): Uint32Array;
export declare function tokenize(pattern: string, skipFirstToken: boolean, skipLastToken: boolean): Uint32Array;
export declare function tokenizeRegexInPlace(selector: string, tokens: TokensBuffer): void;
export declare function binSearch(arr: Uint32Array, elt: number): number;
export declare function binLookup(arr: Uint32Array, elt: number): boolean;
export declare function hasUnicode(str: string): boolean;
/**
 * Finds the last index of an unescaped character in the given string.
 * This function tries to find the match from the backward.
 * When this function sees an escaping character, it will jump to the next index.
 */
export declare function findLastIndexOfUnescapedCharacter(text: string, character: string): number;
//# sourceMappingURL=utils.d.ts.map