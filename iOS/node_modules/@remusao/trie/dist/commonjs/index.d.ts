export interface Trie {
    chars: Map<number, Trie>;
    code: number | undefined;
}
export declare function create(strings: readonly string[]): Trie;
export declare function lookup(trie: Trie, str: string): boolean;
//# sourceMappingURL=index.d.ts.map