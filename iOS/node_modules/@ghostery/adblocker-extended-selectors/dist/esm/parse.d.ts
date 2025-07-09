/*!
 * Based on parsel. Extended by Rémi Berson for Ghostery (2021).
 * https://github.com/LeaVerou/parsel
 *
 * MIT License
 *
 * Copyright (c) 2020 Lea Verou
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in all
 * copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 * SOFTWARE.
 */
import type { AST, Atoms, ParserOptions, Strings } from './types.js';
export declare const RECURSIVE_PSEUDO_CLASSES: Set<string>;
export declare function isEscaped(str: string, index: number): boolean;
export declare function gobbleQuotes(text: string, quote: '"' | "'", start: number): string | undefined;
export declare function gobbleParens(text: string, start: number): string | undefined;
export declare function replace(selector: string, replacement: '¶' | '§', opening: '(' | '"' | "'", gobble: (text: string, start: number) => string | undefined): [Strings, string];
export declare function tokenize(selector: string): Atoms;
/**
 * Parse a CSS selector
 * @param selector {String} The selector to parse
 * @param options.recursive {Boolean} Whether to parse the arguments of pseudo-classes like :is(), :has() etc. Defaults to true.
 * @param options.list {Boolean} Whether this can be a selector list (A, B, C etc). Defaults to true.
 */
export declare function parse(selector: string, { recursive, list }?: ParserOptions): AST | undefined;
//# sourceMappingURL=parse.d.ts.map