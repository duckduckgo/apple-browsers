import { getElements } from '../utils/utils.js';
import { ErrorResponse, SuccessResponse } from '../types.js';
import { extractProfiles } from './extract.js';
import { processTemplateStringWithUserData } from './build-url-transforms.js';

/**
 * @param {Record<string, any>} action
 * @param {Record<string, any>} userData
 * @param {Document | HTMLElement} root
 * @return {import('../types.js').ActionResponse}
 */
export function click(action, userData, root = document) {
    /** @type {Array<any> | null} */
    let elements = [];

    if (action.choices?.length) {
        const choices = evaluateChoices(action, userData);

        // If we returned null, the intention is to skip execution, so return success
        if (choices === null) {
            return new SuccessResponse({ actionID: action.id, actionType: action.actionType, response: null });
        } else if ('error' in choices) {
            return new ErrorResponse({ actionID: action.id, message: `Unable to evaluate choices: ${choices.error}` });
        } else if (!('elements' in choices)) {
            return new ErrorResponse({ actionID: action.id, message: 'No elements provided to click action' });
        }

        elements = choices.elements;
    } else {
        if (!('elements' in action)) {
            return new ErrorResponse({ actionID: action.id, message: 'No elements provided to click action' });
        }

        elements = action.elements;
    }

    if (!elements || !elements.length) {
        return new ErrorResponse({ actionID: action.id, message: 'No elements provided to click action' });
    }

    // there can be multiple elements provided by the action
    for (const element of elements) {
        let rootElement;

        try {
            rootElement = selectRootElement(element, userData, root);
        } catch (error) {
            return new ErrorResponse({ actionID: action.id, message: `Could not find root element: ${error.message}` });
        }

        const elements = getElements(rootElement, element.selector);

        if (!elements?.length) {
            if (element.failSilently) {
                return new SuccessResponse({ actionID: action.id, actionType: action.actionType, response: null });
            }

            return new ErrorResponse({
                actionID: action.id,
                message: `could not find element to click with selector '${element.selector}'!`,
            });
        }

        const loopLength = element.multiple && element.multiple === true ? elements.length : 1;

        for (let i = 0; i < loopLength; i++) {
            const elem = elements[i];

            if ('disabled' in elem) {
                if (elem.disabled && !element.failSilently) {
                    return new ErrorResponse({ actionID: action.id, message: `could not click disabled element ${element.selector}'!` });
                }
            }
            if ('click' in elem && typeof elem.click === 'function') {
                elem.click();
            }
        }
    }

    return new SuccessResponse({ actionID: action.id, actionType: action.actionType, response: null });
}

/**
 * @param {{parent?: {profileMatch?: Record<string, any>}}} clickElement
 * @param {Record<string, any>} userData
 * @param {Document | HTMLElement} root
 * @return {Node}
 */
function selectRootElement(clickElement, userData, root = document) {
    // if there's no 'parent' field, just use the document
    if (!clickElement.parent) return root;

    // if the 'parent' field contains 'profileMatch', try to match it
    if (clickElement.parent.profileMatch) {
        const extraction = extractProfiles(clickElement.parent.profileMatch, userData, root);
        if ('results' in extraction) {
            const sorted = extraction.results.filter((x) => x.result === true).sort((a, b) => b.score - a.score);
            const first = sorted[0];
            if (first && first.element) {
                return first.element;
            }
        }
    }

    throw new Error('`parent` was present on the element, but the configuration is not supported');
}

/**
 * Evaluate a comparator and return the appropriate function
 * @param {string} operator
 * @returns {(a: any, b: any) => boolean}
 */
export function getComparisonFunction(operator) {
    switch (operator) {
        case '=':
        case '==':
        case '===':
            return (a, b) => a === b;
        case '!=':
        case '!==':
            return (a, b) => a !== b;
        case '<':
            return (a, b) => a < b;
        case '<=':
            return (a, b) => a <= b;
        case '>':
            return (a, b) => a > b;
        case '>=':
            return (a, b) => a >= b;
        default:
            throw new Error(`Invalid operator: ${operator}`);
    }
}

/**
 * Evaluates the defined choices (and/or the default) and returns an array of the elements to be clicked
 *
 * @param {Record<string, any>} action
 * @param {Record<string, any>} userData
 * @returns {{ elements: [Record<string, any>] } | { error: String } | null}
 */
function evaluateChoices(action, userData) {
    if ('elements' in action) {
        return { error: 'Elements should be nested inside of choices' };
    }

    for (const choice of action.choices) {
        if (!('condition' in choice) || !('elements' in choice)) {
            return { error: 'All choices must have a condition and elements' };
        }

        const comparison = runComparison(choice, action, userData);

        if ('error' in comparison) {
            return { error: comparison.error };
        } else if ('result' in comparison && comparison.result === true) {
            return { elements: choice.elements };
        }
    }

    // If there's no default defined, return an error.
    if (!('default' in action)) {
        return { error: 'All conditions failed and no default action was provided' };
    }

    // If there is a default and it's null (meaning skip any further action) return success.
    if (action.default === null) {
        // Nothing else to do, return null
        return null;
    }

    // If the default is defined and not null (without elements), return an error.
    if (!('elements' in action.default)) {
        return { error: 'Default action must have elements' };
    }

    return { elements: action.default.elements };
}

/**
 * Attempts to turn a choice definition into an executable comparison and returns the result
 *
 * @param {Record<string, any>} choice
 * @param {Record<string, any>} action
 * @param {Record<string, any>} userData
 * @returns {{ result: Boolean } | { error: String }}
 */
function runComparison(choice, action, userData) {
    let compare;
    let left;
    let right;

    try {
        compare = getComparisonFunction(choice.condition.operation);
    } catch (error) {
        return { error: `Unable to get comparison function: ${error.message}` };
    }

    try {
        left = processTemplateStringWithUserData(choice.condition.left, action, userData);
        right = processTemplateStringWithUserData(choice.condition.right, action, userData);
    } catch (error) {
        return { error: `Unable to resolve left/right comparison arguments: ${error.message}` };
    }

    let result;

    try {
        result = compare(left, right);
    } catch (error) {
        return { error: `Comparison failed with the following error: ${error.message}` };
    }

    return { result };
}
