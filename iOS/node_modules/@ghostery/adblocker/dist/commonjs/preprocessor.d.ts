import { StaticDataView } from './data-view.js';
export type EnvKeys = 'ext_ghostery' | 'ext_abp' | 'ext_ublock' | 'ext_ubol' | 'ext_devbuild' | 'env_chromium' | 'env_edge' | 'env_firefox' | 'env_mobile' | 'env_safari' | 'env_mv3' | 'false' | 'cap_html_filtering' | 'cap_user_stylesheet' | 'adguard' | 'adguard_app_android' | 'adguard_app_ios' | 'adguard_app_mac' | 'adguard_app_windows' | 'adguard_ext_android_cb' | 'adguard_ext_chromium' | 'adguard_ext_edge' | 'adguard_ext_firefox' | 'adguard_ext_opera' | 'adguard_ext_safari' | (string & {});
export declare class Env extends Map<EnvKeys, boolean> {
}
export declare const enum PreprocessorTokens {
    INVALID = 0,
    BEGIF = 1,
    ELSE = 2,
    ENDIF = 3
}
type FilterId = number;
export declare function detectPreprocessor(line: string): PreprocessorTokens;
export declare const evaluate: (expression: string, env: Env) => boolean;
export default class Preprocessor {
    static getCondition(line: string): string;
    static parse(line: string, filterIDs?: Set<FilterId>): Preprocessor;
    static deserialize(view: StaticDataView): Preprocessor;
    readonly condition: string;
    readonly filterIDs: Set<FilterId>;
    constructor({ condition, filterIDs, }: {
        condition: string;
        filterIDs?: Set<FilterId> | undefined;
    });
    evaluate(env: Env): boolean;
    serialize(view: StaticDataView): void;
    getSerializedSize(): number;
}
export {};
//# sourceMappingURL=preprocessor.d.ts.map