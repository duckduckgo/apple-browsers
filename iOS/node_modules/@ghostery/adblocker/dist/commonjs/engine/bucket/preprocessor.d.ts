import { StaticDataView } from '../../data-view.js';
import IFilter from '../../filters/interface.js';
import Preprocessor, { Env } from '../../preprocessor.js';
type FilterId = number;
export default class PreprocessorBucket {
    static deserialize(view: StaticDataView): PreprocessorBucket;
    readonly preprocessors: Preprocessor[];
    private readonly excluded;
    constructor({ excluded, preprocessors, }: {
        excluded?: Set<FilterId>;
        preprocessors?: Preprocessor[];
    });
    isFilterExcluded(filter: IFilter): boolean;
    updateEnv(env: Env): void;
    update({ added, removed, }: {
        added?: Preprocessor[];
        removed?: Preprocessor[];
    }, env: Env): void;
    serialize(view: StaticDataView): void;
    getSerializedSize(): number;
}
export {};
//# sourceMappingURL=preprocessor.d.ts.map