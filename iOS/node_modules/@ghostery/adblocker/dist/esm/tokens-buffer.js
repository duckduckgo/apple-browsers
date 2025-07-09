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
export class TokensBuffer {
    constructor(size) {
        this.pos = 0;
        this.buffer = new Uint32Array(size);
    }
    reset() {
        this.pos = 0;
    }
    slice() {
        return this.buffer.slice(0, this.pos);
    }
    push(token) {
        this.buffer[this.pos++] = token;
    }
    empty() {
        return this.pos === 0;
    }
    full() {
        return this.pos === this.buffer.length;
    }
    remaining() {
        return this.buffer.length - this.pos;
    }
}
export const TOKENS_BUFFER = new TokensBuffer(1024);
//# sourceMappingURL=tokens-buffer.js.map