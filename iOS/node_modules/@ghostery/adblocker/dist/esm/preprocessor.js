import { sizeOfUTF8 } from './data-view.js';
export class Env extends Map {
}
export var PreprocessorTokens;
(function (PreprocessorTokens) {
    PreprocessorTokens[PreprocessorTokens["INVALID"] = 0] = "INVALID";
    PreprocessorTokens[PreprocessorTokens["BEGIF"] = 1] = "BEGIF";
    PreprocessorTokens[PreprocessorTokens["ELSE"] = 2] = "ELSE";
    PreprocessorTokens[PreprocessorTokens["ENDIF"] = 3] = "ENDIF";
})(PreprocessorTokens || (PreprocessorTokens = {}));
export function detectPreprocessor(line) {
    // Minimum size of a valid condition should be 6 for something like: "!#if x" or "!#else"
    if (line.length < 6 ||
        line.charCodeAt(0) !== 33 /* '!' */ ||
        line.charCodeAt(1) !== 35 /* '#' */) {
        return PreprocessorTokens.INVALID;
    }
    if (line.startsWith('!#if ')) {
        return PreprocessorTokens.BEGIF;
    }
    if (line.startsWith('!#else')) {
        return PreprocessorTokens.ELSE;
    }
    if (line.startsWith('!#endif')) {
        return PreprocessorTokens.ENDIF;
    }
    return PreprocessorTokens.INVALID;
}
const tokenizerPattern = /(!|&&|\|\||\(|\)|[a-zA-Z0-9_]+)/g;
const identifierPattern = /^[a-zA-Z0-9_]+$/;
const tokenize = (expression) => expression.match(tokenizerPattern);
const isIdentifier = (expression) => identifierPattern.test(expression);
const precedence = {
    '!': 2,
    '&&': 1,
    '||': 0,
};
const isOperator = (token) => Object.prototype.hasOwnProperty.call(precedence, token);
const testIdentifier = (identifier, env) => {
    if (identifier === 'true' && !env.has('true')) {
        return true;
    }
    if (identifier === 'false' && !env.has('false')) {
        return false;
    }
    return !!env.get(identifier);
};
/// The parsing is done using the [Shunting yard algorithm](https://en.wikipedia.org/wiki/Shunting_yard_algorithm).
/// This function takes as input a string expression and an environment Map.
/// The expression is made of constants (identifiers), logical operators
/// (&&, ||), negations (!constant) and parentheses.
///
/// The environment is a simple Map that associates identifiers to boolean values.
///
/// The function should return the result of evaluating the expression using
/// the values from `environment`. The return value of this function is
/// either `true` or `false`.
export const evaluate = (expression, env) => {
    if (expression.length === 0) {
        return false;
    }
    if (isIdentifier(expression)) {
        if (expression[0] === '!') {
            return !testIdentifier(expression.slice(1), env);
        }
        return testIdentifier(expression, env);
    }
    const tokens = tokenize(expression);
    if (!tokens || tokens.length === 0) {
        return false;
    }
    // Exit if an unallowed character found.
    // Since we're tokenizing via String.prototype.match function,
    // the total length of matched tokens will be different in case
    // unallowed characters were injected.
    // However, we expect all spaces were already removed in prior step.
    if (expression.length !== tokens.reduce((partialSum, token) => partialSum + token.length, 0)) {
        return false;
    }
    const output = [];
    const stack = [];
    for (const token of tokens) {
        if (token === '(') {
            stack.push(token);
        }
        else if (token === ')') {
            while (stack.length !== 0 && stack[stack.length - 1] !== '(') {
                output.push(stack.pop());
            }
            // If the opening parenthesis doesn't exist
            if (stack.length === 0) {
                return false;
            }
            stack.pop();
        }
        else if (isOperator(token)) {
            while (stack.length &&
                isOperator(stack[stack.length - 1]) &&
                precedence[token] <= precedence[stack[stack.length - 1]]) {
                output.push(stack.pop());
            }
            stack.push(token);
        }
        else {
            output.push(testIdentifier(token, env));
        }
    }
    // If there is incomplete parenthesis
    if (stack[0] === '(' || stack[0] === ')') {
        return false;
    }
    while (stack.length !== 0) {
        output.push(stack.pop());
    }
    for (const token of output) {
        if (token === true || token === false) {
            stack.push(token);
        }
        else if (token === '!') {
            stack.push(!stack.pop());
        }
        else if (isOperator(token)) {
            const right = stack.pop();
            const left = stack.pop();
            if (token === '&&') {
                stack.push(left && right);
            }
            else {
                stack.push(left || right);
            }
        }
    }
    return stack[0] === true;
};
export default class Preprocessor {
    static getCondition(line) {
        return line.slice(5 /* '!#if '.length */).replace(/\s/g, '');
    }
    static parse(line, filterIDs) {
        return new this({
            condition: Preprocessor.getCondition(line),
            filterIDs,
        });
    }
    static deserialize(view) {
        const condition = view.getUTF8();
        const filterIDs = new Set();
        for (let i = 0, l = view.getUint32(); i < l; i++) {
            filterIDs.add(view.getUint32());
        }
        return new this({
            condition,
            filterIDs,
        });
    }
    constructor({ condition, filterIDs = new Set(), }) {
        this.condition = condition;
        this.filterIDs = filterIDs;
    }
    evaluate(env) {
        return evaluate(this.condition, env);
    }
    serialize(view) {
        view.pushUTF8(this.condition);
        view.pushUint32(this.filterIDs.size);
        for (const filterID of this.filterIDs) {
            view.pushUint32(filterID);
        }
    }
    getSerializedSize() {
        let estimatedSize = sizeOfUTF8(this.condition);
        estimatedSize += (1 + this.filterIDs.size) * 4;
        return estimatedSize;
    }
}
//# sourceMappingURL=preprocessor.js.map