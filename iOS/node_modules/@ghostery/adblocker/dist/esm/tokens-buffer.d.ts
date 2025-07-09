/*!
 * Copyright (c) 2017-present Ghostery GmbH. All rights reserved.
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */
/**
 * Thin abstraction around a Uint32Array which allows to push tokens
 * whithout caring for the offset. It is used as a way to avoid multiple
 * allocations while calling tokenization (mostly beneficitial for
 * `NetworkFilter.getTokens()`).
 */
export declare class TokensBuffer {
    private readonly buffer;
    pos: number;
    constructor(size: number);
    reset(): void;
    slice(): Uint32Array;
    push(token: number): void;
    empty(): boolean;
    full(): boolean;
    remaining(): number;
}
export declare const TOKENS_BUFFER: TokensBuffer;
//# sourceMappingURL=tokens-buffer.d.ts.map