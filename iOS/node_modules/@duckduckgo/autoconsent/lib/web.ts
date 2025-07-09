import { MessageSender, AutoCMP, RuleBundle, Config, ConsentState } from './types';
import { ConsentOMaticCMP, ConsentOMaticConfig } from './cmps/consentomatic';
import { AutoConsentCMPRule, SUPPORTED_RULE_STEP_VERSION } from './rules';
import { BackgroundMessage, InitMessage } from './messages';
import { evalState, resolveEval } from './eval-handler';
import { getRandomID } from './random';
import { dynamicCMPs } from './cmps/all';
import { AutoConsentCMP } from './cmps/base';
import { DomActions } from './dom-actions';
import { normalizeConfig, scheduleWhenIdle } from './utils';
import { deserializeFilterList, getCosmeticStylesheet, getFilterlistSelectors } from './filterlist-utils';
import { FiltersEngine } from '@ghostery/adblocker';
import serializedEngine from './filterlist-engine';
import { checkHeuristicPatterns } from './heuristics';
import { decodeRules } from './encoding';

export { snippets as evalSnippets } from './eval-snippets';

function filterCMPs(rules: AutoCMP[], config: Config) {
    return rules.filter((cmp) => {
        return (
            (!config.disabledCmps || !config.disabledCmps.includes(cmp.name)) && // CMP is not disabled
            (config.enableCosmeticRules || !cmp.isCosmetic) // CMP is not cosmetic or cosmetic rules are enabled
        );
    });
}

export default class AutoConsent {
    id = getRandomID();
    rules: AutoCMP[] = [];
    config: Config;
    foundCmp: AutoCMP = null;
    state: ConsentState = {
        cosmeticFiltersOn: false,
        filterListReported: false,
        lifecycle: 'loading',
        prehideOn: false,
        findCmpAttempts: 0,
        detectedCmps: [],
        detectedPopups: [],
        heuristicPatterns: [],
        heuristicSnippets: [],
        selfTest: null,
    };
    domActions: DomActions;
    filtersEngine: FiltersEngine;
    protected sendContentMessage: MessageSender;
    protected cosmeticStyleSheet: CSSStyleSheet;
    protected focusedElement: HTMLElement = null;

    constructor(sendContentMessage: MessageSender, config: Partial<Config> = null, declarativeRules: RuleBundle = null) {
        evalState.sendContentMessage = sendContentMessage;
        this.sendContentMessage = sendContentMessage;
        this.rules = [];

        this.updateState({ lifecycle: 'loading' });

        this.addDynamicRules();
        if (config) {
            this.initialize(config, declarativeRules);
        } else {
            if (declarativeRules) {
                this.parseDeclarativeRules(declarativeRules);
            }
            const initMsg: InitMessage = {
                type: 'init',
                url: window.location.href,
            };
            sendContentMessage(initMsg);
            this.updateState({ lifecycle: 'waitingForInitResponse' });
        }
        this.domActions = new DomActions(this);
    }

    initialize(config: Partial<Config>, declarativeRules: RuleBundle) {
        const normalizedConfig = normalizeConfig(config);
        normalizedConfig.logs.lifecycle && console.log('autoconsent init', window.location.href);
        this.config = normalizedConfig;
        if (!normalizedConfig.enabled) {
            normalizedConfig.logs.lifecycle && console.log('autoconsent is disabled');
            return;
        }

        if (declarativeRules) {
            this.parseDeclarativeRules(declarativeRules);
        }

        if (config.enableFilterList) {
            try {
                if (BUNDLE_FILTERLIST && serializedEngine && serializedEngine.length > 0) {
                    this.filtersEngine = deserializeFilterList(serializedEngine);
                }
            } catch (e) {
                console.error('Error parsing filter list', e);
            }
            if (document.readyState === 'loading') {
                window.addEventListener('DOMContentLoaded', () => {
                    this.applyCosmeticFilters();
                });
            } else {
                this.applyCosmeticFilters();
            }
        }

        this.rules = filterCMPs(this.rules, normalizedConfig);

        if (config.enablePrehide) {
            if (document.documentElement) {
                this.prehideElements(); // prehide as early as possible to prevent flickering
            } else {
                // we're injected really early
                const delayedPrehide = () => {
                    window.removeEventListener('DOMContentLoaded', delayedPrehide);
                    this.prehideElements();
                };
                window.addEventListener('DOMContentLoaded', delayedPrehide);
            }
        }

        // start detection
        if (document.readyState === 'loading') {
            const onReady = () => {
                window.removeEventListener('DOMContentLoaded', onReady);
                this.start();
            };
            window.addEventListener('DOMContentLoaded', onReady);
        } else {
            this.start();
        }
        this.updateState({ lifecycle: 'initialized' });
    }

    saveFocus() {
        this.focusedElement = document.activeElement as HTMLElement;
        if (this.focusedElement) {
            this.config.logs.lifecycle && console.log('saving focus', this.focusedElement, location.href);
        }
    }

    restoreFocus() {
        if (this.focusedElement) {
            this.config.logs.lifecycle && console.log('restoring focus', this.focusedElement, location.href);
            try {
                this.focusedElement.focus({ preventScroll: true }); // preventScroll doesn't work on Android https://issues.chromium.org/issues/41453122
            } catch (e) {
                this.config.logs.errors && console.warn('error restoring focus', e);
            }
            this.focusedElement = null;
        }
    }

    addDynamicRules() {
        dynamicCMPs.forEach((Cmp) => {
            this.rules.push(new Cmp(this));
        });
    }

    parseDeclarativeRules(declarativeRules: RuleBundle) {
        if (declarativeRules.consentomatic) {
            Object.keys(declarativeRules.consentomatic).forEach((name) => {
                this.addConsentomaticCMP(name, declarativeRules.consentomatic[name]);
            });
        }

        if (declarativeRules.autoconsent) {
            declarativeRules.autoconsent.forEach((ruleset) => {
                this.addDeclarativeCMP(ruleset);
            });
        }

        if (declarativeRules.compact) {
            try {
                const rules = decodeRules(declarativeRules.compact);
                rules.forEach(this.addDeclarativeCMP.bind(this));
            } catch (e) {
                this.config.logs.errors && console.error(e);
            }
        }
    }

    addDeclarativeCMP(ruleset: AutoConsentCMPRule) {
        // Filter out any rules that need newer step/eval support
        if ((ruleset.minimumRuleStepVersion || 1) <= SUPPORTED_RULE_STEP_VERSION) {
            this.rules.push(new AutoConsentCMP(ruleset, this));
        }
    }

    addConsentomaticCMP(name: string, config: ConsentOMaticConfig) {
        this.rules.push(new ConsentOMaticCMP(`com_${name}`, config));
    }

    // start the detection process, possibly with a delay
    start() {
        scheduleWhenIdle(() => this._start());
    }

    async _start() {
        const logsConfig = this.config.logs;
        logsConfig.lifecycle && console.log(`Detecting CMPs on ${window.location.href}`);
        this.updateState({ lifecycle: 'started' });
        const foundCmps = await this.findCmp(this.config.detectRetries);
        this.updateState({ detectedCmps: foundCmps.map((c) => c.name) });
        if (foundCmps.length === 0) {
            logsConfig.lifecycle && console.log('no CMP found', location.href);
            if (this.config.enablePrehide) {
                this.undoPrehide();
            }

            return this.filterListFallback();
        }

        this.updateState({ lifecycle: 'cmpDetected' });

        // we resort to cosmetic rules only if no non-cosmetic rules are found
        const staticCmps: AutoCMP[] = [];
        const cosmeticCmps: AutoCMP[] = [];

        for (const cmp of foundCmps) {
            if (cmp.isCosmetic) {
                cosmeticCmps.push(cmp);
            } else {
                staticCmps.push(cmp);
            }
        }

        let result = false;

        let foundPopups = await this.detectPopups(staticCmps, async (cmp) => {
            result = await this.handlePopup(cmp);
        });
        if (foundPopups.length === 0) {
            foundPopups = await this.detectPopups(cosmeticCmps, async (cmp) => {
                result = await this.handlePopup(cmp);
            });
        }

        if (foundPopups.length === 0) {
            logsConfig.lifecycle && console.log('no popup found');
            if (this.config.enablePrehide) {
                this.undoPrehide();
            }
            return false;
        }

        if (foundPopups.length > 1) {
            const errorDetails = {
                msg: `Found multiple CMPs, check the detection rules.`,
                cmps: foundPopups.map((cmp) => cmp.name),
            };
            logsConfig.errors && console.warn(errorDetails.msg, errorDetails.cmps);
            this.sendContentMessage({
                type: 'autoconsentError',
                details: errorDetails,
            });
        }

        return result;
    }

    async findCmp(retries: number): Promise<AutoCMP[]> {
        const logsConfig = this.config.logs;
        this.updateState({ findCmpAttempts: this.state.findCmpAttempts + 1 });
        const foundCMPs: AutoCMP[] = [];

        const isTop = window.top === window;
        // refilter relevant rules for this context
        const siteSpecificRules: AutoCMP[] = [];
        const otherRules: AutoCMP[] = [];
        this.rules.forEach((cmp) => {
            // first filter out rules that don't run in this frame-type.
            if (cmp.checkFrameContext(isTop)) {
                // Pull out any rule that has a urlPattern that matches here to be prioritized.
                const isSiteSpecific = !!cmp.runContext.urlPattern;
                if (cmp.hasMatchingUrlPattern()) {
                    siteSpecificRules.push(cmp);
                } else if (!isSiteSpecific) {
                    otherRules.push(cmp);
                }
            }
        });

        const detectCmp = async (cmp: AutoCMP) => {
            try {
                const result = await cmp.detectCmp();
                if (result) {
                    logsConfig.lifecycle && console.log(`Found CMP: ${cmp.name} ${window.location.href}`);
                    this.sendContentMessage({
                        type: 'cmpDetected',
                        url: location.href,
                        cmp: cmp.name,
                    }); // notify the browser
                    foundCMPs.push(cmp);
                }
            } catch (e) {
                logsConfig.errors && console.warn(`error detecting ${cmp.name}`, e);
            }
        };
        const mutationObserver = this.domActions.waitForMutation('html');
        mutationObserver.catch(() => {}); // ensure promise rejection is caught

        logsConfig.lifecycle &&
            siteSpecificRules.length > 0 &&
            console.log(
                'Detecting site-specific rules',
                siteSpecificRules.map((r) => r.name),
            );
        // collect relevant site-specific rules and run them first
        await Promise.all(siteSpecificRules.map(detectCmp));

        // exit early if we already found a site-specific popup
        if (foundCMPs.length > 0) {
            return foundCMPs;
        }

        logsConfig.lifecycle && console.log("Site-specific rules didn't match, trying generic rules");
        // check generic popups
        await Promise.all(otherRules.map(detectCmp));

        this.detectHeuristics();

        if (foundCMPs.length === 0 && retries > 0) {
            // We wait 500ms, and also for some kind of dom mutation to happen before
            // rerunning the findCmp check
            try {
                await Promise.all([this.domActions.wait(500), mutationObserver]);
            } catch (e) {
                // timeout waiting for mutation - break out of detection
                return [];
            }

            return this.findCmp(retries - 1);
        }

        return foundCMPs;
    }

    detectHeuristics() {
        if (this.config.enableHeuristicDetection) {
            const { patterns, snippets } = checkHeuristicPatterns();
            if (
                patterns.length > 0 &&
                (patterns.length !== this.state.heuristicPatterns.length || this.state.heuristicPatterns.some((p, i) => p !== patterns[i]))
            ) {
                this.config.logs.lifecycle && console.log('Heuristic patterns found', patterns, snippets);
                this.updateState({ heuristicPatterns: patterns, heuristicSnippets: snippets }); // we don't care about previously found patterns
            }
        }
    }

    /**
     * Detect if a CMP has a popup open. Fullfils with the CMP if a popup is open, otherwise rejects.
     */
    async detectPopup(cmp: AutoCMP): Promise<AutoCMP> {
        const isOpen = await this.waitForPopup(cmp).catch((error) => {
            this.config.logs.errors && console.warn(`error waiting for a popup for ${cmp.name}`, error);
            return false;
        });

        if (isOpen) {
            this.updateState({ detectedPopups: this.state.detectedPopups.concat([cmp.name]) });
            this.sendContentMessage({
                type: 'popupFound',
                cmp: cmp.name,
                url: location.href,
            }); // notify the browser
            return cmp;
        }
        throw new Error('Popup is not shown');
    }

    /**
     * Detect if any of the CMPs has a popup open. Returns a list of CMPs with open popups.
     */
    async detectPopups(cmps: AutoCMP[], onFirstPopupAppears: (cmp: AutoCMP) => Promise<unknown>) {
        const tasks = cmps.map((cmp) => this.detectPopup(cmp));

        await Promise.any(tasks)
            .then((cmp) => {
                this.detectHeuristics();
                onFirstPopupAppears(cmp);
            })
            .catch(() => {});

        const results = await Promise.allSettled(tasks);
        const popups: AutoCMP[] = [];

        for (const result of results) {
            if (result.status === 'fulfilled') {
                popups.push(result.value);
            }
        }

        return popups;
    }

    async handlePopup(cmp: AutoCMP): Promise<boolean> {
        this.updateState({ lifecycle: 'openPopupDetected' });
        if (this.config.enablePrehide && !this.state.prehideOn) {
            // prehide might have timeouted by this time, apply it again
            this.prehideElements();
        }
        if (this.state.cosmeticFiltersOn) {
            // cancel cosmetic filters if we have a rule for this popup
            this.undoCosmetics();
        }

        this.foundCmp = cmp;

        if (this.config.autoAction === 'optOut') {
            return await this.doOptOut();
        } else if (this.config.autoAction === 'optIn') {
            return await this.doOptIn();
        } else {
            this.config.logs.lifecycle && console.log('waiting for opt-out signal...', location.href);
            return true;
        }
    }

    async doOptOut(): Promise<boolean> {
        const logsConfig = this.config.logs;
        this.updateState({ lifecycle: 'runningOptOut' });
        this.saveFocus();

        let optOutResult;
        if (!this.foundCmp) {
            logsConfig.errors && console.log('no CMP to opt out');
            optOutResult = false;
        } else {
            logsConfig.lifecycle && console.log(`CMP ${this.foundCmp.name}: opt out on ${window.location.href}`);
            optOutResult = await this.foundCmp.optOut();
            logsConfig.lifecycle && console.log(`${this.foundCmp.name}: opt out result ${optOutResult}`);
        }

        if (this.config.enablePrehide) {
            this.undoPrehide();
        }

        this.sendContentMessage({
            type: 'optOutResult',
            cmp: this.foundCmp ? this.foundCmp.name : 'none',
            result: optOutResult,
            scheduleSelfTest: this.foundCmp && this.foundCmp.hasSelfTest,
            url: location.href,
        });

        if (optOutResult && !this.foundCmp.isIntermediate) {
            this.sendContentMessage({
                type: 'autoconsentDone',
                cmp: this.foundCmp.name,
                isCosmetic: this.foundCmp.isCosmetic,
                url: location.href,
            });
            this.updateState({ lifecycle: 'done' });
        } else {
            this.updateState({ lifecycle: optOutResult ? 'optOutSucceeded' : 'optOutFailed' });
        }

        this.restoreFocus();
        return optOutResult;
    }

    async doOptIn(): Promise<boolean> {
        const logsConfig = this.config.logs;
        this.updateState({ lifecycle: 'runningOptIn' });
        this.saveFocus();

        let optInResult;
        if (!this.foundCmp) {
            logsConfig.errors && console.log('no CMP to opt in');
            optInResult = false;
        } else {
            logsConfig.lifecycle && console.log(`CMP ${this.foundCmp.name}: opt in on ${window.location.href}`);
            optInResult = await this.foundCmp.optIn();
            logsConfig.lifecycle && console.log(`${this.foundCmp.name}: opt in result ${optInResult}`);
        }

        if (this.config.enablePrehide) {
            this.undoPrehide();
        }

        this.sendContentMessage({
            type: 'optInResult',
            cmp: this.foundCmp ? this.foundCmp.name : 'none',
            result: optInResult,
            scheduleSelfTest: false, // self-tests are only for opt-out at the moment
            url: location.href,
        });

        if (optInResult && !this.foundCmp.isIntermediate) {
            this.sendContentMessage({
                type: 'autoconsentDone',
                cmp: this.foundCmp.name,
                isCosmetic: this.foundCmp.isCosmetic,
                url: location.href,
            });
            this.updateState({ lifecycle: 'done' });
        } else {
            this.updateState({ lifecycle: optInResult ? 'optInSucceeded' : 'optInFailed' });
        }

        this.restoreFocus();
        return optInResult;
    }

    async doSelfTest(): Promise<boolean> {
        const logsConfig = this.config.logs;
        let selfTestResult;
        if (!this.foundCmp) {
            logsConfig.errors && console.log('no CMP to self test');
            selfTestResult = false;
        } else {
            logsConfig.lifecycle && console.log(`CMP ${this.foundCmp.name}: self-test on ${window.location.href}`);
            selfTestResult = await this.foundCmp.test();
        }

        this.sendContentMessage({
            type: 'selfTestResult',
            cmp: this.foundCmp ? this.foundCmp.name : 'none',
            result: selfTestResult,
            url: location.href,
        });
        this.updateState({ selfTest: selfTestResult });
        return selfTestResult;
    }

    async waitForPopup(cmp: AutoCMP, retries = 5, interval = 500): Promise<boolean> {
        const logsConfig = this.config.logs;
        logsConfig.lifecycle && console.log('checking if popup is open...', cmp.name);
        const isOpen = await cmp.detectPopup().catch((e) => {
            logsConfig.errors && console.warn(`error detecting popup for ${cmp.name}`, e);
            return false;
        }); // ignore possible errors in one-time popup detection
        if (!isOpen && retries > 0) {
            await this.domActions.wait(interval);
            return this.waitForPopup(cmp, retries - 1, interval);
        }
        logsConfig.lifecycle && console.log(cmp.name, `popup is ${isOpen ? 'open' : 'not open'}`);
        return isOpen;
    }

    prehideElements(): boolean {
        const logsConfig = this.config.logs;
        // hide rules not specific to a single CMP rule
        const globalHidden = [
            '#didomi-popup,.didomi-popup-container,.didomi-popup-notice,.didomi-consent-popup-preferences,#didomi-notice,.didomi-popup-backdrop,.didomi-screen-medium',
        ];

        const selectors = this.rules
            .filter((rule) => rule.prehideSelectors && rule.checkRunContext())
            .reduce((selectorList, rule) => [...selectorList, ...rule.prehideSelectors], globalHidden);

        this.updateState({ prehideOn: true });
        setTimeout(() => {
            // unhide things if we are still looking for a pop-up
            if (this.config.enablePrehide && this.state.prehideOn && !['runningOptOut', 'runningOptIn'].includes(this.state.lifecycle)) {
                logsConfig.lifecycle && console.log('Process is taking too long, unhiding elements');
                this.undoPrehide();
            }
        }, this.config.prehideTimeout || 2000);
        return this.domActions.prehide(selectors.join(','));
    }

    undoPrehide(): void {
        this.updateState({ prehideOn: false });
        this.domActions.undoPrehide();
    }

    /**
     * Apply cosmetic filters
     * @returns true if the filters were applied, false otherwise
     */
    async applyCosmeticFilters(styles?: string) {
        if (!this.filtersEngine) {
            return false;
        }
        const logsConfig = this.config?.logs;
        if (BUNDLE_FILTERLIST && !styles) {
            styles = getCosmeticStylesheet(this.filtersEngine);
        }

        setTimeout(() => {
            if (this.state.cosmeticFiltersOn && !this.state.filterListReported) {
                // if the cosmetic filters are actually working, report the hidden popup to the background.
                // This may still be overridden later if an autoconsent rule matches.
                // this may be a false positive: sometimes filters hide unrelated elements that are not cookie pop-ups
                const cosmeticFiltersWorked = this.domActions.elementVisible(getFilterlistSelectors(styles), 'any');
                if (cosmeticFiltersWorked) {
                    logsConfig?.lifecycle && console.log('Prehide cosmetic filters matched', location.href);
                    this.reportFilterlist();
                } else {
                    logsConfig?.lifecycle && console.log("Prehide cosmetic filters didn't match", location.href);
                }
            }
        }, 2000);

        this.updateState({ cosmeticFiltersOn: true });
        try {
            this.cosmeticStyleSheet = await this.domActions.createOrUpdateStyleSheet(styles, this.cosmeticStyleSheet);
            logsConfig?.lifecycle && console.log('[cosmetics]', this.cosmeticStyleSheet, location.href);
            document.adoptedStyleSheets.push(this.cosmeticStyleSheet);
        } catch (e) {
            this.config.logs && console.error('Error applying cosmetic filters', e);
            return false;
        }
        return true;
    }

    undoCosmetics() {
        this.updateState({ cosmeticFiltersOn: false });
        this.config.logs.lifecycle && console.log('[undocosmetics]', this.cosmeticStyleSheet, location.href);
        this.domActions.removeStyleSheet(this.cosmeticStyleSheet);
    }

    reportFilterlist() {
        this.sendContentMessage({
            type: 'cmpDetected',
            url: location.href,
            cmp: 'filterList',
        });
        this.sendContentMessage({
            type: 'popupFound',
            cmp: 'filterList',
            url: location.href,
        });
        this.updateState({ filterListReported: true });
    }

    filterListFallback() {
        if (!BUNDLE_FILTERLIST || !this.filtersEngine) {
            this.updateState({ lifecycle: 'nothingDetected' });
            return false;
        }

        const cosmeticStyles = getCosmeticStylesheet(this.filtersEngine);

        // this may be a false positive: sometimes filters hide unrelated elements that are not cookie pop-ups
        const cosmeticFiltersWorked = this.domActions.elementVisible(getFilterlistSelectors(cosmeticStyles), 'any');

        const logsConfig = this.config?.logs;

        if (!cosmeticFiltersWorked) {
            logsConfig?.lifecycle && console.log("Cosmetic filters didn't work, removing them", location.href);
            this.undoCosmetics();
            this.updateState({ lifecycle: 'nothingDetected' });
            return false;
        } else {
            this.applyCosmeticFilters(cosmeticStyles); // do not wait for it to finish
            logsConfig?.lifecycle && console.log('Keeping cosmetic filters', location.href);
            this.updateState({ lifecycle: 'cosmeticFiltersDetected' });
            if (!this.state.filterListReported) {
                this.reportFilterlist();
            }

            this.sendContentMessage({
                type: 'optOutResult',
                cmp: 'filterList',
                result: true,
                scheduleSelfTest: false,
                url: location.href,
            });
            this.updateState({ lifecycle: 'done' });
            this.sendContentMessage({
                type: 'autoconsentDone',
                cmp: 'filterList',
                isCosmetic: true,
                url: location.href,
            });
            return true;
        }
    }

    updateState(change: Partial<ConsentState>) {
        Object.assign(this.state, change);
        this.sendContentMessage({
            type: 'report',
            instanceId: this.id,
            url: window.location.href,
            mainFrame: window.top === window.self,
            state: this.state,
        });
    }

    async receiveMessageCallback(message: BackgroundMessage) {
        const logsConfig = this.config?.logs;
        if (logsConfig?.messages) {
            console.log('received from background', message, window.location.href);
        }
        switch (message.type) {
            case 'initResp':
                this.initialize(message.config, message.rules);
                break;
            case 'optIn':
                await this.doOptIn();
                break;
            case 'optOut':
                await this.doOptOut();
                break;
            case 'selfTest':
                await this.doSelfTest();
                break;
            case 'evalResp':
                resolveEval(message.id, message.result);
                break;
        }
    }
}
