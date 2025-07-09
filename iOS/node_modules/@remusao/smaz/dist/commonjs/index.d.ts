export declare class Smaz {
    readonly codebook: readonly string[];
    private readonly compressor;
    private readonly decompressor;
    constructor(codebook: readonly string[], maxSize?: number);
    compress(str: string): Uint8Array;
    getCompressedSize(str: string): number;
    decompress(buffer: Uint8Array): string;
}
export declare function decompress(array: Uint8Array): string;
export declare function compress(str: string): Uint8Array;
export declare function getCompressedSize(str: string): number;
//# sourceMappingURL=index.d.ts.map