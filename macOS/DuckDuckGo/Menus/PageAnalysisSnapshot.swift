//
//  PageAnalysisSnapshot.swift
//
//  Copyright © 2026 DuckDuckGo. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

#if DEBUG && compiler(>=6.4) && canImport(FoundationModels)
import Foundation

/// A bounded, read-only inventory. IDs refer to retained nodes in an isolated content world for live target validation.
struct PageAnalysisSnapshot: Codable {
    let captureID: String
    let title: String
    let origin: String
    let documentTimeOrigin: Double
    let capturedAt: String
    let visibleElementCount: Int
    let scanLimitReached: Bool
    let iframeCount: Int
    let shadowHostCount: Int
    var elements: [Element]

    struct Element: Codable {
        let id: String
        let tag: String
        let role: String
        let type: String
        let label: String
        let landmark: String
        let surroundingText: String
        let autocomplete: String
        let form: String
        let required: Bool
        let disabled: Bool
        let invalid: Bool
        let nativeInvalid: Bool
        let ariaInvalid: Bool
        let inViewport: Bool
        let readOnly: Bool
        let hasValue: Bool
        let formBlocked: Bool
    }

    func json() throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let json = String(data: try encoder.encode(self), encoding: .utf8) else {
            throw CocoaError(.fileReadInapplicableStringEncoding)
        }
        return json
    }

    // Run in an isolated content world so page JavaScript cannot replace the built-ins we call.
    // No values, HTML, action URLs, cookies, or persistent identifiers are collected.
    // DOM selectors and node references stay outside the model prompt.
    static func targetValidationScript(captureID: String, elementID: String) throws -> String {
        let arguments = try JSONSerialization.data(withJSONObject: [captureID, elementID])
        guard let json = String(data: arguments, encoding: .utf8) else {
            throw CocoaError(.fileReadInapplicableStringEncoding)
        }
        return "globalThis.__ddgPageAnalysisTarget?.(...\(json))"
    }

    static let script = #"""
    (() => {
        const clean = (text, limit = 100) => String(text || '').replace(/\s+/g, ' ').trim().slice(0, limit);
        const visible = element => {
            if (element.closest('[hidden], [inert], [aria-hidden="true"]')) return false;
            const style = getComputedStyle(element);
            return style.display !== 'none' && style.visibility !== 'hidden' && element.getClientRects().length > 0;
        };
        // Do not include text entered into editable regions, including contenteditable descendants.
        const valueElements = 'input, textarea, select, [role="textbox"], [role="combobox"], '
            + '[contenteditable]:not([contenteditable="false"])';
        const labelText = element => {
            if (!element || element.closest(valueElements)) return '';
            const walker = document.createTreeWalker(element, NodeFilter.SHOW_TEXT);
            let text = '', visited = 0, node;
            while ((node = walker.nextNode()) && visited++ < 100 && text.length < 100) {
                if (!node.parentElement.closest(valueElements + ', script, style')
                    && visible(node.parentElement)) text += ' ' + node.textContent;
            }
            return clean(text);
        };
        const label = element => {
            const labelledBy = clean(element.getAttribute('aria-labelledby'), 300).split(' ').slice(0, 5)
                .map(id => labelText(document.getElementById(id))).join(' ');
            const labels = Array.from(element.labels || []).slice(0, 3).map(labelText).join(' ');
            return clean(element.getAttribute('aria-label') || labelledBy.trim() || labels.trim()
                || element.getAttribute('placeholder') || element.getAttribute('title')
                || (element.matches('input[type="submit"],input[type="button"]') ? element.value : '')
                || (element.matches('form') ? 'Form' : labelText(element)));
        };
        const landmark = element => {
            const region = element.closest('dialog,[role="dialog"],main,[role="main"],footer,[role="contentinfo"],nav,[role="navigation"],header,[role="banner"]');
            const role = region?.getAttribute('role') || region?.localName || '';
            return ({contentinfo: 'footer', nav: 'navigation', banner: 'header'})[role] || role;
        };
        const surroundingText = element => {
            // Small local context distinguishes an entry button from an unrelated footer expansion.
            // labelText excludes all editable values and hidden text.
            const ownLabel = label(element);
            for (let parent = element.parentElement, depth = 0; parent && depth < 3; parent = parent.parentElement, depth++) {
                if (parent.matches('body,html,main,footer,nav,header')) break;
                const text = labelText(parent);
                if (text && text !== ownLabel) return text;
            }
            return '';
        };
        const selector = 'form,input:not([type="hidden"]),textarea,select,button,a[href],summary,iframe,frame,'
            + '[role="button"],[role="link"],[role="checkbox"],[role="combobox"],[role="textbox"],'
            + '[role="radio"],[role="switch"],[role="tab"],[role="dialog"],[role="alert"],[role="status"],[role="listitem"],'
            + '[aria-invalid="true"],h1,h2,h3,[contenteditable="true"]';
        const candidates = [];
        const walker = document.createTreeWalker(document.documentElement, NodeFilter.SHOW_ELEMENT);
        let node, scanned = 0, iframeCount = 0, shadowHostCount = 0;
        while ((node = walker.nextNode()) && scanned < 12000) {
            scanned++;
            if (node.matches('iframe,frame')) iframeCount++;
            if (node.shadowRoot) shadowHostCount++;
            if (node.matches(selector) && visible(node)) candidates.push(node);
        }
        const forms = new Map(candidates.filter(element => element.matches('form')).map((form, index) => [form, 'f' + (index + 1)]));
        const priority = element => element.matches('form,input,textarea,select,button,[role="alert"],[role="dialog"],[aria-invalid="true"]') ? 0
            : element.matches('a') ? 2 : 1;
        candidates.sort((first, second) => priority(first) - priority(second));
        const captureID = Array.from(crypto.getRandomValues(new Uint32Array(4)), word => word.toString(16)).join('-');
        const targets = new Map();
        const selectorOptions = element => {
            const tag = CSS.escape(element.localName);
            const options = [];
            if (element.id) options.push('#' + CSS.escape(element.id));
            // Do not use field values or URLs as selector attributes.
            for (const attribute of ['name', 'data-testid', 'data-test', 'aria-label', 'type']) {
                const value = element.getAttribute(attribute);
                if (value) options.push(tag + '[' + attribute + '=' + CSS.escape(value) + ']');
            }
            const classes = Array.from(element.classList).slice(0, 8).map(value => '.' + CSS.escape(value));
            const classOptions = classes.map(value => tag + value);
            for (let first = 0; first < classes.length; first++) {
                for (let second = first + 1; second < classes.length; second++) {
                    classOptions.push(tag + classes[first] + classes[second]);
                }
            }
            if (classes.length > 2) classOptions.push(tag + classes.join(''));
            options.push(...classOptions.sort((first, second) => first.length - second.length), tag);
            return options;
        };
        const uniqueSelector = element => {
            const identifiesTarget = selector => {
                const matches = document.querySelectorAll(selector);
                return matches.length === 1 && matches[0] === element;
            };
            const options = selectorOptions(element);
            const direct = options.find(identifiesTarget);
            if (direct) return direct;

            // Try a short, named ancestor scope before relying on sibling positions.
            for (let parent = element.parentElement, depth = 0; parent && depth < 5; parent = parent.parentElement, depth++) {
                for (const scope of selectorOptions(parent)) {
                    const scoped = options.map(option => scope + ' ' + option).find(identifiesTarget);
                    if (scoped) return scoped;
                }
            }
            const parts = [];
            for (let node = element; node && node.nodeType === Node.ELEMENT_NODE; node = node.parentElement) {
                const index = Array.from(node.parentElement?.children || [node]).indexOf(node) + 1;
                parts.unshift(CSS.escape(node.localName) + ':nth-child(' + index + ')');
                const selector = parts.join(' > ');
                if (identifiesTarget(selector)) return selector;
            }
            return parts.join(' > ');
        };
        const formBlocked = form => !!form && Array.from(form.elements).some(control =>
            control.getAttribute('aria-invalid') === 'true' || (control.willValidate && !control.validity.valid));
        const describe = (element, id) => {
            const rect = element.getBoundingClientRect();
            return {
                id, tag: element.localName,
                role: clean(element.getAttribute('role'), 30), type: clean(element.type || element.getAttribute('type'), 30),
                label: label(element), landmark: landmark(element), surroundingText: surroundingText(element),
                autocomplete: clean(element.getAttribute('autocomplete'), 100), form: forms.get(element.form || element.closest('form')) || '',
                required: element.required === true || element.getAttribute('aria-required') === 'true',
                disabled: element.matches(':disabled') || element.getAttribute('aria-disabled') === 'true',
                invalid: element.getAttribute('aria-invalid') === 'true' || (element.willValidate === true && !element.validity.valid),
                nativeInvalid: element.willValidate === true && !element.validity.valid,
                ariaInvalid: element.getAttribute('aria-invalid') === 'true',
                readOnly: element.readOnly === true || element.getAttribute('aria-readonly') === 'true',
                hasValue: element.matches('input:not([type="password"]),textarea,select') && element.value.trim().length > 0,
                formBlocked: formBlocked(element.matches('form') ? element : element.form),
                inViewport: rect.bottom > 0 && rect.right > 0 && rect.top < innerHeight && rect.left < innerWidth
            };
        };
        const elements = candidates.slice(0, 70).map((element, index) => {
            const id = forms.get(element) || 'e' + (index + 1);
            const state = describe(element, id);
            const form = element.form;
            targets.set(id, {element, form, state});
            return state;
        });
        // Re-resolve the original node and compare current state, including native validity.
        // No selector text or JavaScript comes from the model.
        globalThis.__ddgPageAnalysisTarget = (expectedCapture, id) => {
            const target = targets.get(id);
            const fail = error => JSON.stringify({error});
            if (expectedCapture !== captureID || !target) return fail('Unknown or expired capture reference.');
            const {element, form, state} = target;
            if (!element.isConnected || !visible(element) || element.form !== form
                || JSON.stringify(describe(element, id)) !== JSON.stringify(state)) {
                return fail('The target or its form state changed. Analyze again.');
            }
            // Generate only for the selected node, after checking its captured identity and state.
            const selector = uniqueSelector(element);
            const formSelector = form ? uniqueSelector(form) : 'body';
            const matches = document.querySelectorAll(selector);
            if (matches.length !== 1 || matches[0] !== element) return fail('The selector no longer identifies the captured node.');
            const roots = document.querySelectorAll(formSelector);
            if (roots.length !== 1 || (form && roots[0] !== form)) return fail('The form changed. Analyze again.');
            const scopedMatches = roots[0].querySelectorAll(selector);
            if (scopedMatches.length !== 1 || scopedMatches[0] !== element) return fail('The target is outside the form scope.');
            return JSON.stringify({selector, formSelector});
        };
        return JSON.stringify({captureID, title: clean(document.title, 150), origin: location.origin,
            documentTimeOrigin: performance.timeOrigin, capturedAt: new Date().toISOString(),
            visibleElementCount: candidates.length, scanLimitReached: scanned >= 12000,
            iframeCount, shadowHostCount, elements});
    })()
    """#
}
#endif
