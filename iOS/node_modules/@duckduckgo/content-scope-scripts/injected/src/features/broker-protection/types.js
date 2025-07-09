/**
 * @typedef {SuccessResponse | ErrorResponse} ActionResponse
 * @typedef {{ result: true } | { result: false; error: string }} BooleanResult
 * @typedef {{type: "element" | "text" | "url"; selector: string; parent?: string; expect?: string; failSilently?: boolean}} Expectation
 */

/**
 * @typedef {object} PirAction
 * @property {string} id
 * @property {"extract" | "fillForm" | "click" | "expectation" | "getCaptchaInfo" | "solveCaptcha" | "navigate" | "condition"} actionType
 * @property {string} [selector]
 * @property {string} [captchaType]
 * @property {string} [injectCaptchaHandler]
 * @property {string} [dataSource]
 */

/**
 * @template T
 * @typedef {PirError | PirSuccess<T>} PirResponse
 */

export class PirError {
    /**
     * @param {object} params
     * @param {boolean} params.success
     * @param {object} params.error
     * @param {string} params.error.message
     */
    constructor(params) {
        this.success = params.success;
        this.error = params.error;
    }

    /**
     * @param {string} message
     * @return {PirError}
     * @static
     * @memberof PirError
     */
    static create(message) {
        return new PirError({ success: false, error: { message } });
    }

    /**
     * @param {object} error
     * @return {error is PirError}
     * @static
     * @memberof PirError
     */
    static isError(error) {
        return error instanceof PirError && error.success === false;
    }
}

/**
 * Represents a successful response
 * @template T
 */
export class PirSuccess {
    /**
     * @param {object} params
     * @param {boolean} params.success
     * @param {T} params.response
     */
    constructor(params) {
        this.success = params.success;
        this.response = params.response;
    }

    /**
     * @template T
     * @param {T} response
     * @return {PirSuccess<T>}
     * @static
     * @memberof PirSuccess
     */
    static create(response) {
        return new PirSuccess({ success: true, response });
    }

    static createEmpty() {
        return new PirSuccess({ success: true, response: null });
    }

    /**
     * @param {object} params
     * @return {params is PirSuccess}
     * @static
     * @memberof PirSuccess
     */
    static isSuccess(params) {
        return params instanceof PirSuccess && params.success === true;
    }
}

/**
 * Represents an error
 */
export class ErrorResponse {
    /**
     * @param {object} params
     * @param {string} params.actionID
     * @param {string} params.message
     */
    constructor(params) {
        this.error = params;
    }

    /**
     * @param {ActionResponse} response
     * @return {response is ErrorResponse}
     * @static
     * @memberof ErrorResponse
     */
    static isErrorResponse(response) {
        return response instanceof ErrorResponse;
    }

    /**
     * @param {object} params
     * @param {PirAction['id']} params.actionID
     * @param {string} [params.context]
     * @return {(message: string) => ErrorResponse}
     * @static
     * @memberof ErrorResponse
     */
    static generateErrorResponseFunction({ actionID, context = '' }) {
        return (message) => new ErrorResponse({ actionID, message: [context, message].filter(Boolean).join(': ') });
    }
}

/**
 * @typedef {object} SuccessResponseInterface
 * @property {PirAction['id']} actionID
 * @property {PirAction['actionType']} actionType
 * @property {any} response
 * @property {import("./actions/extract").Action[]} [next]
 * @property {Record<string, any>} [meta] - optional meta data
 */

/**
 * Represents success, `response` can contain other complex types
 */
export class SuccessResponse {
    /**
     * @param {SuccessResponseInterface} params
     */
    constructor(params) {
        this.success = params;
    }

    /**
     * @param {SuccessResponseInterface} params
     * @return {SuccessResponse}
     * @static
     * @memberof SuccessResponse
     */
    static create(params) {
        return new SuccessResponse(params);
    }
}

/**
 * A type that includes the result + metadata of comparing a DOM element + children
 * to a set of data. Use this for analysis/debugging
 */
export class ProfileResult {
    /**
     * @param {object} params
     * @param {boolean} params.result - whether we consider this a 'match'
     * @param {string[]} params.matchedFields - a list of the fields in the data that were matched.
     * @param {number} params.score - value to determine
     * @param {HTMLElement} [params.element] - the parent element that was matched. Not present in JSON
     * @param {Record<string, any>} params.scrapedData
     */
    constructor(params) {
        this.scrapedData = params.scrapedData;
        this.result = params.result;
        this.score = params.score;
        this.element = params.element;
        this.matchedFields = params.matchedFields;
    }

    /**
     * Convert this structure into a format that can be sent between JS contexts/native
     * @return {{result: boolean, score: number, matchedFields: string[], scrapedData: Record<string, any>}}
     */
    asData() {
        return {
            scrapedData: this.scrapedData,
            result: this.result,
            score: this.score,
            matchedFields: this.matchedFields,
        };
    }
}

/**
 * @template JsonValue
 * @interface
 */
export class Extractor {
    /**
     * @param {string[]} _noneEmptyStringArray
     * @param {import("./actions/extract").ExtractorParams} _extractorParams
     * @return {JsonValue}
     */

    extract(_noneEmptyStringArray, _extractorParams) {
        throw new Error('must implement extract');
    }
}

/**
 * @interface
 */
export class AsyncProfileTransform {
    /**
     * @param {Record<string, any>} _profile - The current profile value
     * @param {Record<string, any>} _profileParams - the original action params from `action.profile`
     * @return {Promise<Record<string, any>>}
     */

    transform(_profile, _profileParams) {
        throw new Error('must implement extract');
    }
}
