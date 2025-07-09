import { ContentScriptMessage } from './messages';
import { ConsentOMaticConfig } from './cmps/consentomatic';
import { AutoConsentCMPRule, ElementSelector, HideMethod, RunContext, VisibilityCheck } from './rules';
import { CompactCMPRuleset } from './encoding';

export type MessageSender = (message: ContentScriptMessage) => Promise<void>;

export interface AutoCMP {
    name: string;
    hasSelfTest: boolean;
    isIntermediate: boolean;
    isCosmetic: boolean;
    prehideSelectors?: string[];
    runContext: RunContext;
    checkRunContext(): boolean;
    checkFrameContext(isTop: boolean): boolean;
    hasMatchingUrlPattern(): boolean;
    detectCmp(): Promise<boolean>;
    detectPopup(): Promise<boolean>;
    optOut(): Promise<boolean>;
    optIn(): Promise<boolean>;
    openCmp(): Promise<boolean>;
    test(): Promise<boolean>;
}

export interface DomActionsProvider {
    click(selector: ElementSelector, all: boolean): boolean;
    elementExists(selector: ElementSelector): boolean;
    elementVisible(selector: ElementSelector, check: VisibilityCheck): boolean;
    waitForElement(selector: ElementSelector, timeout?: number): Promise<boolean>;
    waitForVisible(selector: ElementSelector, timeout?: number, check?: VisibilityCheck): Promise<boolean>;
    waitForThenClick(selector: ElementSelector, timeout?: number, all?: boolean): Promise<boolean>;
    wait(ms: number): Promise<true>;
    hide(selector: string, method: HideMethod): boolean;
    prehide(selector: string): boolean;
    undoPrehide(): void;
    querySingleReplySelector(selector: string, parent?: any): HTMLElement[];
    querySelectorChain(selectors: string[]): HTMLElement[];
    elementSelector(selector: ElementSelector): HTMLElement[];
    waitForMutation(selector: ElementSelector): Promise<boolean>;
}

export type RuleBundle = {
    autoconsent: AutoConsentCMPRule[];
    compact?: CompactCMPRuleset;
    consentomatic?: { [name: string]: ConsentOMaticConfig };
};

export type AutoAction = 'optOut' | 'optIn' | null;

export type Config = {
    enabled: boolean;
    autoAction: AutoAction;
    disabledCmps: string[];
    enablePrehide: boolean;
    enableCosmeticRules: boolean;
    detectRetries: number;
    isMainWorld: boolean;
    prehideTimeout: number;
    enableFilterList: boolean;
    enableHeuristicDetection: boolean;
    logs: {
        lifecycle: boolean;
        rulesteps: boolean;
        detectionsteps: boolean;
        evals: boolean;
        errors: boolean;
        messages: boolean;
        waits: boolean;
    };
};

export type LifecycleState =
    | 'loading'
    | 'initialized'
    | 'waitingForInitResponse'
    | 'started'
    | 'nothingDetected'
    | 'cosmeticFiltersDetected'
    | 'cmpDetected'
    | 'openPopupDetected'
    | 'runningOptOut'
    | 'runningOptIn'
    | 'optOutSucceeded'
    | 'optOutFailed'
    | 'optInSucceeded'
    | 'optInFailed'
    | 'done';

export type ConsentState = {
    cosmeticFiltersOn: boolean; // true if cosmetic filter rules are currently applied.
    filterListReported: boolean; // true if the cosmetic filter list has been reported to the user.
    lifecycle: LifecycleState; // What point in the autoconsent lifecycle this script is at.
    prehideOn: boolean; // If the script is currently hiding preHide elements.
    findCmpAttempts: number; // Number of times we tried to find CMPs in this frame.
    detectedCmps: string[]; // Names of CMP rules where `detectCmp` returned true.
    detectedPopups: string[]; // Names of CMP rules where `detectPopup` returned true.
    heuristicPatterns: string[]; // Matched heuristic patterns
    heuristicSnippets: string[]; // Matched heuristic snippets
    selfTest: boolean; // null if no self test was run, otherwise it holds the result of the self test.
};
