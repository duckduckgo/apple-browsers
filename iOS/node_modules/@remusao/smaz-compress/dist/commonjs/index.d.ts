export declare class SmazCompress {
    private readonly buffer;
    private readonly trie;
    private readonly verbatim;
    constructor(codebook: readonly string[], maxSize?: number);
    getCompressedSize(str: string): number;
    compress(str: string): Uint8Array;
    private flushVerbatim;
}
//# sourceMappingURL=index.d.ts.map