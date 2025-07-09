import { create } from '@remusao/trie';
const EMPTY_UINT8_ARRAY = new Uint8Array(0);
export class SmazCompress {
    constructor(codebook, maxSize = 30000) {
        this.trie = create(codebook);
        this.buffer = new Uint8Array(maxSize);
        this.verbatim = new Uint8Array(255);
    }
    getCompressedSize(str) {
        if (str.length === 0) {
            return 0;
        }
        let bufferIndex = 0;
        let verbatimIndex = 0;
        let inputIndex = 0;
        while (inputIndex < str.length) {
            let indexAfterMatch = -1;
            let code = -1;
            let root = this.trie;
            for (let j = inputIndex; j < str.length; j += 1) {
                root = root.chars.get(str.charCodeAt(j));
                if (root === undefined) {
                    break;
                }
                if (root.code !== undefined) {
                    code = root.code;
                    indexAfterMatch = j + 1;
                }
            }
            if (code === -1) {
                verbatimIndex++;
                inputIndex++;
                if (verbatimIndex === 255) {
                    bufferIndex += 2 + verbatimIndex;
                    verbatimIndex = 0;
                }
            }
            else {
                if (verbatimIndex !== 0) {
                    bufferIndex += 2 + (verbatimIndex === 1 ? 0 : verbatimIndex);
                    verbatimIndex = 0;
                }
                bufferIndex++;
                inputIndex = indexAfterMatch;
            }
        }
        if (verbatimIndex !== 0) {
            bufferIndex += 2 + (verbatimIndex === 1 ? 0 : verbatimIndex);
        }
        return bufferIndex;
    }
    compress(str) {
        if (str.length === 0) {
            return EMPTY_UINT8_ARRAY;
        }
        let bufferIndex = 0;
        let verbatimIndex = 0;
        let inputIndex = 0;
        const len = str.length;
        while (inputIndex < str.length) {
            let indexAfterMatch = -1;
            let code = -1;
            let root = this.trie;
            for (let j = inputIndex; j < len; j += 1) {
                root = root.chars.get(str.charCodeAt(j));
                if (root === undefined) {
                    break;
                }
                if (root.code !== undefined) {
                    code = root.code;
                    indexAfterMatch = j + 1;
                }
            }
            if (code === -1) {
                this.verbatim[verbatimIndex++] = str.charCodeAt(inputIndex++);
                if (verbatimIndex === 255) {
                    bufferIndex = this.flushVerbatim(verbatimIndex, bufferIndex);
                    verbatimIndex = 0;
                }
            }
            else {
                if (verbatimIndex !== 0) {
                    bufferIndex = this.flushVerbatim(verbatimIndex, bufferIndex);
                    verbatimIndex = 0;
                }
                this.buffer[bufferIndex++] = code;
                inputIndex = indexAfterMatch;
            }
        }
        if (verbatimIndex !== 0) {
            bufferIndex = this.flushVerbatim(verbatimIndex, bufferIndex);
        }
        return this.buffer.slice(0, bufferIndex);
    }
    flushVerbatim(verbatimIndex, bufferIndex) {
        if (verbatimIndex === 1) {
            this.buffer[bufferIndex++] = 254;
            this.buffer[bufferIndex++] = this.verbatim[0];
        }
        else {
            this.buffer[bufferIndex++] = 255;
            this.buffer[bufferIndex++] = verbatimIndex;
            for (let k = 0; k < verbatimIndex; k += 1) {
                this.buffer[bufferIndex++] = this.verbatim[k];
            }
        }
        return bufferIndex;
    }
}
//# sourceMappingURL=index.js.map