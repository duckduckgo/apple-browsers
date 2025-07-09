"use strict";
/*!
 * Copyright (c) 2017-present Ghostery GmbH. All rights reserved.
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.StaticDataView = exports.EMPTY_UINT32_ARRAY = exports.EMPTY_UINT8_ARRAY = void 0;
exports.sizeOfByte = sizeOfByte;
exports.sizeOfBool = sizeOfBool;
exports.sizeOfLength = sizeOfLength;
exports.sizeOfBytes = sizeOfBytes;
exports.sizeOfBytesWithLength = sizeOfBytesWithLength;
exports.sizeOfASCII = sizeOfASCII;
exports.sizeOfUTF8 = sizeOfUTF8;
exports.sizeOfUint32Array = sizeOfUint32Array;
exports.sizeOfNetworkRedirect = sizeOfNetworkRedirect;
exports.sizeOfNetworkHostname = sizeOfNetworkHostname;
exports.sizeOfNetworkCSP = sizeOfNetworkCSP;
exports.sizeOfNetworkFilter = sizeOfNetworkFilter;
exports.sizeOfCosmeticSelector = sizeOfCosmeticSelector;
exports.sizeOfRawNetwork = sizeOfRawNetwork;
exports.sizeOfRawCosmetic = sizeOfRawCosmetic;
const compression_js_1 = __importDefault(require("./compression.js"));
const crc32_js_1 = __importDefault(require("./crc32.js"));
const punycode_js_1 = require("./punycode.js");
exports.EMPTY_UINT8_ARRAY = new Uint8Array(0);
exports.EMPTY_UINT32_ARRAY = new Uint32Array(0);
// Check if current architecture is little endian
const LITTLE_ENDIAN = new Int8Array(new Int16Array([1]).buffer)[0] === 1;
// Store compression in a lazy, global singleton
let getCompressionSingleton = () => {
    const COMPRESSION = new compression_js_1.default();
    getCompressionSingleton = () => COMPRESSION;
    return COMPRESSION;
};
function align4(pos) {
    // From: https://stackoverflow.com/a/2022194
    return (pos + 3) & ~0x03;
}
/**
 * Return size of of a serialized byte value.
 */
function sizeOfByte() {
    return 1;
}
/**
 * Return size of of a serialized boolean value.
 */
function sizeOfBool() {
    return 1;
}
/**
 * Return number of bytes needed to serialize `length`.
 */
function sizeOfLength(length) {
    return length <= 127 ? 1 : 5;
}
/**
 * Return number of bytes needed to serialize `array` Uint8Array typed array.
 *
 * WARNING: this only returns the correct size if `align` is `false`.
 */
function sizeOfBytes(array, align) {
    return sizeOfBytesWithLength(array.length, align);
}
/**
 * Return number of bytes needed to serialize `array` Uint8Array typed array.
 *
 * WARNING: this only returns the correct size if `align` is `false`.
 */
function sizeOfBytesWithLength(length, align) {
    // Alignment is a tricky thing because it depends on the current offset in
    // the buffer at the time of serialization; which we cannot anticipate
    // before actually starting serialization. This means that we need to
    // potentially over-estimate the size (at most by 3 bytes) to make sure the
    // final size is at least equal or a bit bigger than necessary.
    return (align ? 3 : 0) + length + sizeOfLength(length);
}
/**
 * Return number of bytes needed to serialize `str` ASCII string.
 */
function sizeOfASCII(str) {
    return str.length + sizeOfLength(str.length);
}
/**
 * Return number of bytes needed to serialize `str` UTF8 string.
 */
function sizeOfUTF8(str) {
    const encodedLength = (0, punycode_js_1.encode)(str).length;
    return encodedLength + sizeOfLength(encodedLength);
}
/**
 * Return number of bytes needed to serialize `array`.
 */
function sizeOfUint32Array(array) {
    return array.byteLength + sizeOfLength(array.length);
}
function sizeOfNetworkRedirect(str, compression) {
    return compression === true
        ? sizeOfBytesWithLength(getCompressionSingleton().networkRedirect.getCompressedSize(str), false)
        : sizeOfASCII(str);
}
function sizeOfNetworkHostname(str, compression) {
    return compression === true
        ? sizeOfBytesWithLength(getCompressionSingleton().networkHostname.getCompressedSize(str), false)
        : sizeOfASCII(str);
}
function sizeOfNetworkCSP(str, compression) {
    return compression === true
        ? sizeOfBytesWithLength(getCompressionSingleton().networkCSP.getCompressedSize(str), false)
        : sizeOfASCII(str);
}
function sizeOfNetworkFilter(str, compression) {
    return compression === true
        ? sizeOfBytesWithLength(getCompressionSingleton().networkFilter.getCompressedSize(str), false)
        : sizeOfASCII(str);
}
function sizeOfCosmeticSelector(str, compression) {
    return compression === true
        ? sizeOfBytesWithLength(getCompressionSingleton().cosmeticSelector.getCompressedSize(str), false)
        : sizeOfASCII(str);
}
function sizeOfRawNetwork(str, compression) {
    return compression === true
        ? sizeOfBytesWithLength(getCompressionSingleton().networkRaw.getCompressedSize((0, punycode_js_1.encode)(str)), false)
        : sizeOfUTF8(str);
}
function sizeOfRawCosmetic(str, compression) {
    return compression === true
        ? sizeOfBytesWithLength(getCompressionSingleton().cosmeticRaw.getCompressedSize((0, punycode_js_1.encode)(str)), false)
        : sizeOfUTF8(str);
}
/**
 * This abstraction allows to serialize efficiently low-level values of types:
 * string, uint8, uint16, uint32, etc. while hiding the complexity of managing
 * the current offset and growing. It should always be instantiated with a
 * big-enough length because this will not allow for resizing. To allow
 * deciding the required total size, function estimating the size needed to
 * store different primitive values are exposes as static methods.
 *
 * This class is also more efficient than the built-in `DataView`.
 *
 * The way this is used in practice is that you write pairs of function to
 * serialize and deserialize a given structure/class (with code being pretty
 * symetrical). In the serializer you `pushX` values, and in the deserializer
 * you use `getX` functions to get back the values.
 */
class StaticDataView {
    /**
     * Create an empty (i.e.: size = 0) StaticDataView.
     */
    static empty(options) {
        return StaticDataView.fromUint8Array(exports.EMPTY_UINT8_ARRAY, options);
    }
    /**
     * Instantiate a StaticDataView instance from `array` of type Uint8Array.
     */
    static fromUint8Array(array, options) {
        return new StaticDataView(array, options);
    }
    /**
     * Instantiate a StaticDataView with given `capacity` number of bytes.
     */
    static allocate(capacity, options) {
        return new StaticDataView(new Uint8Array(capacity), options);
    }
    constructor(buffer, { enableCompression }) {
        if (LITTLE_ENDIAN === false) {
            // This check makes sure that we will not load the adblocker on a
            // big-endian system. This would not work since byte ordering is important
            // at the moment (mainly for performance reasons).
            throw new Error('Adblocker currently does not support Big-endian systems');
        }
        if (enableCompression === true) {
            this.enableCompression();
        }
        this.buffer = buffer;
        this.pos = 0;
    }
    enableCompression() {
        this.compression = getCompressionSingleton();
    }
    checksum() {
        return (0, crc32_js_1.default)(this.buffer, 0, this.pos);
    }
    dataAvailable() {
        return this.pos < this.buffer.byteLength;
    }
    setPos(pos) {
        this.pos = pos;
    }
    getPos() {
        return this.pos;
    }
    seekZero() {
        this.pos = 0;
    }
    slice() {
        this.checkSize();
        return this.buffer.slice(0, this.pos);
    }
    subarray() {
        if (this.pos === this.buffer.byteLength) {
            return this.buffer;
        }
        this.checkSize();
        return this.buffer.subarray(0, this.pos);
    }
    /**
     * Make sure that `this.pos` is aligned on a multiple of 4.
     */
    align4() {
        this.pos = align4(this.pos);
    }
    set(buffer) {
        this.buffer = new Uint8Array(buffer);
        this.seekZero();
    }
    pushBool(bool) {
        this.pushByte(Number(bool));
    }
    getBool() {
        return Boolean(this.getByte());
    }
    setByte(pos, byte) {
        this.buffer[pos] = byte;
    }
    pushByte(octet) {
        this.pushUint8(octet);
    }
    getByte() {
        return this.getUint8();
    }
    pushBytes(bytes, align = false) {
        this.pushLength(bytes.length);
        if (align === true) {
            this.align4();
        }
        this.buffer.set(bytes, this.pos);
        this.pos += bytes.byteLength;
    }
    getBytes(align = false) {
        const numberOfBytes = this.getLength();
        if (align === true) {
            this.align4();
        }
        const bytes = this.buffer.subarray(this.pos, this.pos + numberOfBytes);
        this.pos += numberOfBytes;
        return bytes;
    }
    /**
     * Allows row access to the internal buffer through a Uint32Array acting like
     * a view. This is used for super fast writing/reading of large chunks of
     * Uint32 numbers in the byte array.
     */
    getUint32ArrayView(desiredSize) {
        // Round this.pos to next multiple of 4 for alignement
        this.align4();
        // Short-cut when empty array
        if (desiredSize === 0) {
            return exports.EMPTY_UINT32_ARRAY;
        }
        // Create non-empty view
        const view = new Uint32Array(this.buffer.buffer, this.pos + this.buffer.byteOffset, desiredSize);
        this.pos += desiredSize * 4;
        return view;
    }
    pushUint8(uint8) {
        this.buffer[this.pos++] = uint8;
    }
    getUint8() {
        return this.buffer[this.pos++];
    }
    pushUint16(uint16) {
        this.buffer[this.pos++] = uint16 >>> 8;
        this.buffer[this.pos++] = uint16;
    }
    getUint16() {
        return ((this.buffer[this.pos++] << 8) | this.buffer[this.pos++]) >>> 0;
    }
    pushUint32(uint32) {
        this.buffer[this.pos++] = uint32 >>> 24;
        this.buffer[this.pos++] = uint32 >>> 16;
        this.buffer[this.pos++] = uint32 >>> 8;
        this.buffer[this.pos++] = uint32;
    }
    getUint32() {
        return ((((this.buffer[this.pos++] << 24) >>> 0) +
            ((this.buffer[this.pos++] << 16) |
                (this.buffer[this.pos++] << 8) |
                this.buffer[this.pos++])) >>>
            0);
    }
    pushUint32Array(arr) {
        this.pushLength(arr.length);
        // TODO - use `set` to push the full buffer at once?
        for (const n of arr) {
            this.pushUint32(n);
        }
    }
    getUint32Array() {
        const length = this.getLength();
        const arr = new Uint32Array(length);
        // TODO - use `subarray`?
        for (let i = 0; i < length; i += 1) {
            arr[i] = this.getUint32();
        }
        return arr;
    }
    pushUTF8(raw) {
        const str = (0, punycode_js_1.encode)(raw);
        this.pushLength(str.length);
        for (let i = 0; i < str.length; i += 1) {
            this.buffer[this.pos++] = str.charCodeAt(i);
        }
    }
    getUTF8() {
        const byteLength = this.getLength();
        this.pos += byteLength;
        return (0, punycode_js_1.decode)(String.fromCharCode.apply(null, 
        // @ts-ignore
        this.buffer.subarray(this.pos - byteLength, this.pos)));
    }
    pushASCII(str) {
        this.pushLength(str.length);
        for (let i = 0; i < str.length; i += 1) {
            this.buffer[this.pos++] = str.charCodeAt(i);
        }
    }
    getASCII() {
        const byteLength = this.getLength();
        this.pos += byteLength;
        // @ts-ignore
        return String.fromCharCode.apply(null, this.buffer.subarray(this.pos - byteLength, this.pos));
    }
    pushNetworkRedirect(str) {
        if (this.compression !== undefined) {
            this.pushBytes(this.compression.networkRedirect.compress(str));
        }
        else {
            this.pushASCII(str);
        }
    }
    getNetworkRedirect() {
        if (this.compression !== undefined) {
            return this.compression.networkRedirect.decompress(this.getBytes());
        }
        return this.getASCII();
    }
    pushNetworkHostname(str) {
        if (this.compression !== undefined) {
            this.pushBytes(this.compression.networkHostname.compress(str));
        }
        else {
            this.pushASCII(str);
        }
    }
    getNetworkHostname() {
        if (this.compression !== undefined) {
            return this.compression.networkHostname.decompress(this.getBytes());
        }
        return this.getASCII();
    }
    pushNetworkCSP(str) {
        if (this.compression !== undefined) {
            this.pushBytes(this.compression.networkCSP.compress(str));
        }
        else {
            this.pushASCII(str);
        }
    }
    getNetworkCSP() {
        if (this.compression !== undefined) {
            return this.compression.networkCSP.decompress(this.getBytes());
        }
        return this.getASCII();
    }
    pushNetworkFilter(str) {
        if (this.compression !== undefined) {
            this.pushBytes(this.compression.networkFilter.compress(str));
        }
        else {
            this.pushASCII(str);
        }
    }
    getNetworkFilter() {
        if (this.compression !== undefined) {
            return this.compression.networkFilter.decompress(this.getBytes());
        }
        return this.getASCII();
    }
    pushCosmeticSelector(str) {
        if (this.compression !== undefined) {
            this.pushBytes(this.compression.cosmeticSelector.compress(str));
        }
        else {
            this.pushASCII(str);
        }
    }
    getCosmeticSelector() {
        if (this.compression !== undefined) {
            return this.compression.cosmeticSelector.decompress(this.getBytes());
        }
        return this.getASCII();
    }
    pushRawCosmetic(str) {
        if (this.compression !== undefined) {
            this.pushBytes(this.compression.cosmeticRaw.compress((0, punycode_js_1.encode)(str)));
        }
        else {
            this.pushUTF8(str);
        }
    }
    getRawCosmetic() {
        if (this.compression !== undefined) {
            return (0, punycode_js_1.decode)(this.compression.cosmeticRaw.decompress(this.getBytes()));
        }
        return this.getUTF8();
    }
    pushRawNetwork(str) {
        if (this.compression !== undefined) {
            this.pushBytes(this.compression.networkRaw.compress((0, punycode_js_1.encode)(str)));
        }
        else {
            this.pushUTF8(str);
        }
    }
    getRawNetwork() {
        if (this.compression !== undefined) {
            return (0, punycode_js_1.decode)(this.compression.networkRaw.decompress(this.getBytes()));
        }
        return this.getUTF8();
    }
    checkSize() {
        if (this.pos !== 0 && this.pos > this.buffer.byteLength) {
            throw new Error(`StaticDataView too small: ${this.buffer.byteLength}, but required ${this.pos} bytes`);
        }
    }
    // Serialiez `length` with variable encoding to save space
    pushLength(length) {
        if (length <= 127) {
            this.pushUint8(length);
        }
        else {
            this.pushUint8(128);
            this.pushUint32(length);
        }
    }
    getLength() {
        const lengthShort = this.getUint8();
        return lengthShort === 128 ? this.getUint32() : lengthShort;
    }
}
exports.StaticDataView = StaticDataView;
//# sourceMappingURL=data-view.js.map