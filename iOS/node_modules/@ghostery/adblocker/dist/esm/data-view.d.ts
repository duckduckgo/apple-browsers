/*!
 * Copyright (c) 2017-present Ghostery GmbH. All rights reserved.
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */
import Compression from './compression.js';
interface IDataViewOptions {
    enableCompression: boolean;
}
export declare const EMPTY_UINT8_ARRAY: Uint8Array;
export declare const EMPTY_UINT32_ARRAY: Uint32Array;
/**
 * Return size of of a serialized byte value.
 */
export declare function sizeOfByte(): number;
/**
 * Return size of of a serialized boolean value.
 */
export declare function sizeOfBool(): number;
/**
 * Return number of bytes needed to serialize `length`.
 */
export declare function sizeOfLength(length: number): number;
/**
 * Return number of bytes needed to serialize `array` Uint8Array typed array.
 *
 * WARNING: this only returns the correct size if `align` is `false`.
 */
export declare function sizeOfBytes(array: Uint8Array, align: boolean): number;
/**
 * Return number of bytes needed to serialize `array` Uint8Array typed array.
 *
 * WARNING: this only returns the correct size if `align` is `false`.
 */
export declare function sizeOfBytesWithLength(length: number, align: boolean): number;
/**
 * Return number of bytes needed to serialize `str` ASCII string.
 */
export declare function sizeOfASCII(str: string): number;
/**
 * Return number of bytes needed to serialize `str` UTF8 string.
 */
export declare function sizeOfUTF8(str: string): number;
/**
 * Return number of bytes needed to serialize `array`.
 */
export declare function sizeOfUint32Array(array: Uint32Array): number;
export declare function sizeOfNetworkRedirect(str: string, compression: boolean): number;
export declare function sizeOfNetworkHostname(str: string, compression: boolean): number;
export declare function sizeOfNetworkCSP(str: string, compression: boolean): number;
export declare function sizeOfNetworkFilter(str: string, compression: boolean): number;
export declare function sizeOfCosmeticSelector(str: string, compression: boolean): number;
export declare function sizeOfRawNetwork(str: string, compression: boolean): number;
export declare function sizeOfRawCosmetic(str: string, compression: boolean): number;
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
export declare class StaticDataView {
    /**
     * Create an empty (i.e.: size = 0) StaticDataView.
     */
    static empty(options: IDataViewOptions): StaticDataView;
    /**
     * Instantiate a StaticDataView instance from `array` of type Uint8Array.
     */
    static fromUint8Array(array: Uint8Array, options: IDataViewOptions): StaticDataView;
    /**
     * Instantiate a StaticDataView with given `capacity` number of bytes.
     */
    static allocate(capacity: number, options: IDataViewOptions): StaticDataView;
    pos: number;
    buffer: Uint8Array;
    compression: Compression | undefined;
    constructor(buffer: Uint8Array, { enableCompression }: IDataViewOptions);
    enableCompression(): void;
    checksum(): number;
    dataAvailable(): boolean;
    setPos(pos: number): void;
    getPos(): number;
    seekZero(): void;
    slice(): Uint8Array;
    subarray(): Uint8Array;
    /**
     * Make sure that `this.pos` is aligned on a multiple of 4.
     */
    align4(): void;
    set(buffer: Uint8Array): void;
    pushBool(bool: boolean): void;
    getBool(): boolean;
    setByte(pos: number, byte: number): void;
    pushByte(octet: number): void;
    getByte(): number;
    pushBytes(bytes: Uint8Array, align?: boolean): void;
    getBytes(align?: boolean): Uint8Array;
    /**
     * Allows row access to the internal buffer through a Uint32Array acting like
     * a view. This is used for super fast writing/reading of large chunks of
     * Uint32 numbers in the byte array.
     */
    getUint32ArrayView(desiredSize: number): Uint32Array;
    pushUint8(uint8: number): void;
    getUint8(): number;
    pushUint16(uint16: number): void;
    getUint16(): number;
    pushUint32(uint32: number): void;
    getUint32(): number;
    pushUint32Array(arr: Uint32Array): void;
    getUint32Array(): Uint32Array;
    pushUTF8(raw: string): void;
    getUTF8(): string;
    pushASCII(str: string): void;
    getASCII(): string;
    pushNetworkRedirect(str: string): void;
    getNetworkRedirect(): string;
    pushNetworkHostname(str: string): void;
    getNetworkHostname(): string;
    pushNetworkCSP(str: string): void;
    getNetworkCSP(): string;
    pushNetworkFilter(str: string): void;
    getNetworkFilter(): string;
    pushCosmeticSelector(str: string): void;
    getCosmeticSelector(): string;
    pushRawCosmetic(str: string): void;
    getRawCosmetic(): string;
    pushRawNetwork(str: string): void;
    getRawNetwork(): string;
    private checkSize;
    pushLength(length: number): void;
    getLength(): number;
}
export {};
//# sourceMappingURL=data-view.d.ts.map