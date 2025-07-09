import { sampleData } from '../src/sampleData.js';

export class SpecialError {
    /**
     * @param {object} params
     * @param {import('../types/special-error.js').InitialSetupResponse['errorData']} params.errorData
     */
    constructor({ errorData }) {
        this.data = errorData;
    }

    /**
     * @param {import('../types/special-error.js').InitialSetupResponse['errorData']} [errorData]
     */
    withErrorData(errorData) {
        if (errorData) {
            return new SpecialError({ errorData });
        }
        return this;
    }

    /**
     * @param {keyof sampleData|null} [errorId]
     */
    withSampleErrorId(errorId) {
        if (errorId && Object.keys(sampleData).includes(errorId)) {
            return new SpecialError({ errorData: sampleData[errorId].data });
        }
        return this;
    }
}
