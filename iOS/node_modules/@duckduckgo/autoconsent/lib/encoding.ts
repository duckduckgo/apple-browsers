import { AutoConsentCMPRule, AutoConsentRuleStep, RunContext, SUPPORTED_RULE_STEP_VERSION } from './rules';

export type CompactRuleStep = {
    e: number; // exists
    v: number; // visible
    c: number; // waitForThenClick
    k: number; // click
    w: number; // waitFor
    wv: number; // waitForVisible
    h: number; // hide
    cc: number; // cookieContains
};

export type CompactCMPRuleStep = AutoConsentRuleStep & Partial<CompactRuleStep>;
type CompactableRuleStepKey =
    | 'exists'
    | 'visible'
    | 'waitForThenClick'
    | 'click'
    | 'waitFor'
    | 'waitForVisible'
    | 'hide'
    | 'cookieContains';
type CompactNullableBoolean = 0 | 1 | 2;

export type CompactCMPRule = [
    number, // minimumRuleStepVersion
    string, // name
    CompactNullableBoolean, // cosmetic
    string, // runContext.urlPattern
    number, // runContext.main + runContext.frame
    number[], // prehideSelectors
    CompactCMPRuleStep[], // detectCMP
    CompactCMPRuleStep[], // detectPopup
    CompactCMPRuleStep[], // optOut
    CompactCMPRuleStep[], // test
    Pick<AutoConsentCMPRule, 'intermediate'>, // extra
];

export type CompactCMPRuleset = {
    v: number;
    s: string[];
    r: CompactCMPRule[];
};

/**
 * Mapping of long to short key for rule step keys that should be shortened, with their value
 * replaced by an array offset.
 */
const compactedRuleSteps: [CompactableRuleStepKey, keyof CompactRuleStep][] = [
    ['exists', 'e'],
    ['visible', 'v'],
    ['waitForThenClick', 'c'],
    ['click', 'k'],
    ['waitFor', 'w'],
    ['waitForVisible', 'wv'],
    ['hide', 'h'],
    ['cookieContains', 'cc'],
];

function encodeNullableBoolean(value: boolean | undefined): CompactNullableBoolean {
    if (value === true) {
        return 1;
    }
    if (value === false) {
        return 0;
    }
    return 2;
}

function decodeNullableBoolean(value: CompactNullableBoolean): boolean | undefined {
    if (value === 1) {
        return true;
    }
    if (value === 0) {
        return false;
    }
    return undefined;
}

export function encodeRules(rules: AutoConsentCMPRule[]): CompactCMPRuleset {
    const strings: string[] = [];

    function replaceStrings(selector: string): number {
        let index = strings.indexOf(selector);
        if (index === -1) {
            index = strings.push(selector) - 1;
        }
        return index;
    }

    function encodeRuleStep(step: AutoConsentRuleStep): CompactCMPRuleStep {
        const clonedStep: CompactCMPRuleStep = { ...step };
        for (const [longKey, shortKey] of compactedRuleSteps) {
            if (clonedStep[longKey] && typeof clonedStep[longKey] === 'string') {
                clonedStep[shortKey] = replaceStrings(clonedStep[longKey]);
                delete clonedStep[longKey];
            }
        }
        if (step.if) {
            clonedStep.if = encodeRuleStep(step.if);
            clonedStep.then = step.then && step.then.map(encodeRuleStep);
            if (step.else) {
                clonedStep.else = step.else.map(encodeRuleStep);
            }
        }
        if (step.any) {
            clonedStep.any = step.any.map(encodeRuleStep);
        }
        return clonedStep;
    }

    const compactRules: CompactCMPRule[] = rules.map((r) => {
        return [
            r.minimumRuleStepVersion || 1,
            r.name,
            encodeNullableBoolean(r.cosmetic),
            r.runContext?.urlPattern || '',
            parseInt(`${encodeNullableBoolean(r.runContext?.main)}${encodeNullableBoolean(r.runContext?.frame)}`),
            (r.prehideSelectors || []).map(replaceStrings),
            r.detectCmp.map(encodeRuleStep),
            r.detectPopup.map(encodeRuleStep),
            r.optOut.map(encodeRuleStep),
            (r.test || []).map(encodeRuleStep),
            r.intermediate !== undefined ? { intermediate: r.intermediate } : {},
        ];
    });

    return {
        v: 1,
        s: strings,
        r: compactRules,
    };
}

export function decodeRules(encoded: CompactCMPRuleset): AutoConsentCMPRule[] {
    if (encoded.v > 1) {
        throw new Error('Unsupported rule format.');
    }
    function decodeRuleStep(step: CompactCMPRuleStep): AutoConsentRuleStep {
        const clonedStep: CompactCMPRuleStep = { ...step };
        for (const [longKey, shortKey] of compactedRuleSteps) {
            if (clonedStep[shortKey] !== undefined) {
                clonedStep[longKey] = encoded.s[clonedStep[shortKey]];
                delete clonedStep[shortKey];
            }
        }
        if (step.if) {
            clonedStep.if = decodeRuleStep(step.if);
            clonedStep.then = step.then && step.then.map(decodeRuleStep);
            if (step.else) {
                clonedStep.else = step.else.map(decodeRuleStep);
            }
        }
        if (step.any) {
            clonedStep.any = step.any.map(decodeRuleStep);
        }
        return { ...clonedStep };
    }
    return encoded.r
        .filter((r) => r[0] <= SUPPORTED_RULE_STEP_VERSION)
        .map((rule) => {
            const [
                minimumRuleStepVersion,
                name,
                cosmetic,
                urlPattern,
                mainFrame,
                prehideSelectors,
                detectCmp,
                detectPopup,
                optOut,
                test,
                extra,
            ] = rule;
            const optIn: AutoConsentRuleStep[] = [];
            const runContext: RunContext = {};
            const runInMainFrame = decodeNullableBoolean((Math.floor(mainFrame / 10) % 10) as CompactNullableBoolean);
            const runInSubFrame = decodeNullableBoolean((mainFrame % 10) as CompactNullableBoolean);
            if (runInMainFrame !== undefined) {
                runContext.main = runInMainFrame;
            }
            if (runInSubFrame !== undefined) {
                runContext.frame = runInSubFrame;
            }
            if (urlPattern !== '') {
                runContext.urlPattern = urlPattern;
            }

            return {
                name,
                cosmetic: decodeNullableBoolean(cosmetic),
                runContext,
                prehideSelectors: prehideSelectors.map((i) => encoded.s[i].toString()),
                detectCmp: detectCmp.map(decodeRuleStep),
                detectPopup: detectPopup.map(decodeRuleStep),
                optOut: optOut.map(decodeRuleStep),
                optIn,
                test: test?.map(decodeRuleStep),
                minimumRuleStepVersion: minimumRuleStepVersion || undefined,
                ...extra,
            };
        });
}
