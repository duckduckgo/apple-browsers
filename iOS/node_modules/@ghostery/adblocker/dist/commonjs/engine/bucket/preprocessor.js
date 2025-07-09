"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const preprocessor_js_1 = __importDefault(require("../../preprocessor.js"));
class PreprocessorBucket {
    static deserialize(view) {
        const excluded = new Set();
        for (let i = 0, l = view.getUint32(); i < l; i++) {
            excluded.add(view.getUint32());
        }
        const preprocessors = [];
        for (let i = 0, l = view.getUint32(); i < l; i++) {
            preprocessors.push(preprocessor_js_1.default.deserialize(view));
        }
        return new this({
            excluded,
            preprocessors,
        });
    }
    constructor({ excluded = new Set(), preprocessors = [], }) {
        this.excluded = excluded;
        this.preprocessors = preprocessors;
    }
    isFilterExcluded(filter) {
        return this.excluded.has(filter.getId());
    }
    updateEnv(env) {
        // Update excluded filter ids based on bindings
        this.excluded.clear();
        for (const preprocessor of this.preprocessors) {
            if (!preprocessor.evaluate(env)) {
                for (const filterID of preprocessor.filterIDs) {
                    this.excluded.add(filterID);
                }
            }
        }
    }
    update({ added, removed, }, env) {
        if (removed) {
            for (const preprocessor of removed) {
                const local = this.preprocessors.find((local) => local.condition === preprocessor.condition);
                // Skip if we don't have any preprocessor on local
                // In the context of filters updates from CDN this should never happen.
                if (!local) {
                    continue;
                }
                for (const filterID of preprocessor.filterIDs) {
                    local.filterIDs.delete(filterID);
                }
            }
        }
        if (added) {
            for (const preprocessor of added) {
                const local = this.preprocessors.find((local) => local.condition === preprocessor.condition);
                if (!local) {
                    this.preprocessors.push(preprocessor);
                    continue;
                }
                for (const filterID of preprocessor.filterIDs) {
                    local.filterIDs.add(filterID);
                }
            }
        }
        if ((removed && removed.length !== 0) || (added && added.length !== 0)) {
            this.updateEnv(env);
        }
    }
    serialize(view) {
        view.pushUint32(this.excluded.size);
        for (const filterID of this.excluded) {
            view.pushUint32(filterID);
        }
        view.pushUint32(this.preprocessors.length);
        for (const preprocessor of this.preprocessors) {
            preprocessor.serialize(view);
        }
    }
    getSerializedSize() {
        let estimatedSize = (1 + this.excluded.size) * 4;
        estimatedSize += 4;
        for (const preprocessor of this.preprocessors) {
            estimatedSize += preprocessor.getSerializedSize();
        }
        return estimatedSize;
    }
}
exports.default = PreprocessorBucket;
//# sourceMappingURL=preprocessor.js.map