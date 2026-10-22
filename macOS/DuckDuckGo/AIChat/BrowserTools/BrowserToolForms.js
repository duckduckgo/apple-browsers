//
//  BrowserToolForms.js
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

// Page side of Duck.ai's form tools. It runs in Duck.ai's own content world, so page scripts can't
// see or change the ref registry. It only reads and writes the DOM: what may be filled, what counts
// as a submit and what a label is are decided natively, where they can be tested.
(() => {
    if (globalThis.__duckAIForms) {
        return;
    }

    const maxControls = 400;
    const maxButtons = 100;
    const maxText = 300;
    const maxValue = 2000;
    const maxPageText = 4000;

    const controlSelector = 'input:not([type="submit" i]):not([type="button" i]):not([type="reset" i]):not([type="image" i]), select, textarea';
    const buttonSelector = 'button, input[type="submit" i], input[type="button" i], input[type="reset" i], input[type="image" i], [role="button"]';
    const anyControlSelector = 'input, select, textarea';
    // Left out of label text: the controls themselves, and error and hint text that sits beside them.
    const notLabelSelector = 'input, select, textarea, button, script, style, [class*="error" i], [role="alert"], [class*="hint" i]';

    // Refs stay the same for an element until the document goes away.
    const elementsByRef = new Map();
    const refsByElement = new WeakMap();
    const counters = { f: 0, e: 0, b: 0 };

    function refFor(element, prefix) {
        let ref = refsByElement.get(element);
        if (!ref) {
            counters[prefix] += 1;
            ref = prefix + counters[prefix];
            refsByElement.set(element, ref);
            elementsByRef.set(ref, new WeakRef(element));
        }
        return ref;
    }

    function elementFor(ref) {
        const element = elementsByRef.get(ref)?.deref();
        return element && element.isConnected ? element : null;
    }

    function clean(value, max = maxText) {
        return (value || '').replace(/\s+/g, ' ').trim().slice(0, max);
    }

    function isRendered(element) {
        if (!element) {
            return false;
        }
        if (typeof element.checkVisibility === 'function') {
            return element.checkVisibility({ checkVisibilityCSS: true });
        }
        const style = getComputedStyle(element);
        return style.display !== 'none' && style.visibility !== 'hidden' && element.getClientRects().length > 0;
    }

    function isVisible(control) {
        if (control.type === 'hidden') {
            return false;
        }
        if (isRendered(control)) {
            return true;
        }
        // Custom-styled checkboxes and radios hide the input and show their label instead.
        if (control.type === 'checkbox' || control.type === 'radio') {
            return Array.from(control.labels || []).some(isRendered);
        }
        return false;
    }

    function visibleText(element) {
        return isRendered(element) ? clean(element.textContent) : '';
    }

    function textWithout(element, selector) {
        const copy = element.cloneNode(true);
        copy.querySelectorAll(selector).forEach((node) => node.remove());
        return clean(copy.textContent);
    }

    function textOfIds(ids, onlyVisible) {
        return clean((ids || '').split(/\s+/)
            .map((id) => id && document.getElementById(id))
            .filter((element) => element && (!onlyVisible || isRendered(element)))
            .map((element) => element.textContent)
            .join(' '));
    }

    // The largest ancestor, at most 3 levels up, that holds no control other than `isSame` ones.
    function soleContainer(control, isSame) {
        let best = null;
        let container = control.parentElement;
        for (let depth = 0; container && container !== document.body && depth < 3; depth += 1) {
            const others = Array.from(container.querySelectorAll(anyControlSelector))
                .filter((other) => !isSame(other) && other.type !== 'hidden');
            if (others.length > 0) {
                break;
            }
            best = container;
            container = container.parentElement;
        }
        return best;
    }

    function legendOf(control, isSame) {
        const fieldset = control.closest('fieldset');
        const legend = fieldset && fieldset.querySelector(':scope > legend');
        if (!legend) {
            return '';
        }
        // A step's legend ("Your home") says nothing about one field among many.
        const others = Array.from(fieldset.querySelectorAll(anyControlSelector))
            .filter((other) => !isSame(other) && other.type !== 'hidden');
        return others.length === 0 ? clean(legend.textContent) : '';
    }

    function sameRadioGroup(radio) {
        return (other) => other.type === 'radio' && other.name === radio.name && other.form === radio.form;
    }

    function labelsOf(control, isSame) {
        const labels = Array.from(control.labels || []);
        const wrapping = labels.find((label) => label.contains(control));
        const pointing = labels.find((label) => !label.contains(control));
        const container = soleContainer(control, isSame);
        return {
            labelFor: pointing ? textWithout(pointing, notLabelSelector) : '',
            wrapping: wrapping ? textWithout(wrapping, notLabelSelector) : '',
            ariaLabel: clean(control.getAttribute('aria-label')),
            ariaLabelledBy: textOfIds(control.getAttribute('aria-labelledby'), false),
            placeholder: clean(control.getAttribute('placeholder')),
            nearby: container ? textWithout(container, notLabelSelector + ', label') : '',
            legend: legendOf(control, isSame),
            title: clean(control.getAttribute('title')),
        };
    }

    function groupLabelsOf(radio) {
        const isSame = sameRadioGroup(radio);
        const group = radio.closest('[role="radiogroup"]');
        const container = soleContainer(radio, isSame);
        return {
            ariaGroup: group ? clean(group.getAttribute('aria-label')) || textOfIds(group.getAttribute('aria-labelledby'), false) : '',
            nearby: container ? textWithout(container, notLabelSelector + ', label') : '',
            legend: legendOf(radio, isSame),
        };
    }

    function errorOf(control, isSame) {
        const fromErrorMessage = textOfIds(control.getAttribute('aria-errormessage'), true);
        if (fromErrorMessage) {
            return fromErrorMessage;
        }
        // `<id>-error` is a common convention; radio groups often use their name instead.
        for (const key of [control.id, control.type === 'radio' ? control.name : '']) {
            const slot = key && document.getElementById(key + '-error');
            const text = slot && visibleText(slot);
            if (text) {
                return text;
            }
        }
        const invalid = control.getAttribute('aria-invalid') === 'true';
        if (invalid) {
            const described = textOfIds(control.getAttribute('aria-describedby'), true);
            if (described) {
                return described;
            }
        }
        const container = soleContainer(control, isSame);
        if (container) {
            for (const candidate of container.querySelectorAll('[class*="error" i], [role="alert"]')) {
                const text = visibleText(candidate);
                if (text) {
                    return text;
                }
            }
        }
        return invalid ? clean(control.validationMessage) : '';
    }

    function describeControl(control) {
        const tag = control.tagName.toLowerCase();
        const type = tag === 'input' ? (control.getAttribute('type') || 'text').toLowerCase() : tag;
        const autocomplete = clean(control.getAttribute('autocomplete')).toLowerCase();
        const isSame = type === 'radio' ? sameRadioGroup(control) : (other) => other === control;
        const field = {
            ref: refFor(control, 'e'),
            formRef: refFor(control.form || document.body, 'f'),
            tag,
            type,
            name: control.getAttribute('name') || '',
            autocomplete,
            required: control.required || control.getAttribute('aria-required') === 'true',
            disabled: control.matches(':disabled'),
            visible: isVisible(control),
            labels: labelsOf(control, isSame),
            error: errorOf(control, isSame),
        };
        // Secret values never leave the page.
        const secret = type === 'password' || type === 'file' || /(^|\s)cc-/.test(autocomplete);
        if (!secret) {
            field.value = (control.value || '').slice(0, maxValue);
        }
        if (type === 'checkbox' || type === 'radio') {
            field.checked = control.checked;
        }
        if (tag === 'select') {
            field.options = Array.from(control.options).slice(0, 100)
                .map((option) => ({ value: option.value, label: clean(option.label || option.textContent) }));
        }
        if (type === 'radio') {
            field.groupLabels = groupLabelsOf(control);
        }
        return field;
    }

    function describeButton(button) {
        const form = button.form || button.closest('form');
        return {
            ref: refFor(button, 'b'),
            formRef: refFor(form || document.body, 'f'),
            tag: button.tagName.toLowerCase(),
            typeAttribute: button.hasAttribute('type') ? button.getAttribute('type').toLowerCase() : null,
            inForm: Boolean(form),
            text: clean(button.innerText || button.value || button.getAttribute('aria-label') || button.getAttribute('title')),
            visible: isRendered(button),
            disabled: button.matches(':disabled') || button.getAttribute('aria-disabled') === 'true',
        };
    }

    function messages() {
        const seen = new Set();
        const result = [];
        for (const element of document.querySelectorAll('[role="alert"], [role="status"], [aria-live]:not([aria-live="off"])')) {
            const text = visibleText(element);
            if (text && !seen.has(text)) {
                seen.add(text);
                const isAlert = element.getAttribute('role') === 'alert' || element.getAttribute('aria-live') === 'assertive';
                result.push({ text, isAlert });
            }
            if (result.length >= 10) {
                break;
            }
        }
        return result;
    }

    function page() {
        // Forms first, then fields, then buttons, so refs read f1, e1, b1 in document order.
        const forms = Array.from(document.forms).map((form) => ({
            ref: refFor(form, 'f'),
            name: clean(form.getAttribute('name') || form.getAttribute('aria-label')),
            visible: isRendered(form),
            isPage: false,
        }));
        // Controls outside any <form> are grouped under the page itself.
        forms.push({ ref: refFor(document.body, 'f'), name: '', visible: true, isPage: true });

        const controls = Array.from(document.querySelectorAll(controlSelector)).slice(0, maxControls);
        const buttons = Array.from(document.querySelectorAll(buttonSelector))
            .filter((button) => !button.parentElement || !button.parentElement.closest(buttonSelector))
            .slice(0, maxButtons);
        const siteName = document.querySelector('meta[property="og:site_name" i]');
        const main = document.querySelector('main') || document.body;
        return {
            url: location.href,
            title: clean(document.title),
            siteName: siteName ? clean(siteName.getAttribute('content')) : null,
            forms,
            fields: controls.map(describeControl),
            buttons: buttons.map(describeButton),
            messages: messages(),
            mainText: (main.innerText || '').slice(0, maxPageText),
        };
    }

    const valueSetters = {
        input: Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value').set,
        textarea: Object.getOwnPropertyDescriptor(HTMLTextAreaElement.prototype, 'value').set,
        select: Object.getOwnPropertyDescriptor(HTMLSelectElement.prototype, 'value').set,
    };

    function fire(element, type) {
        element.dispatchEvent(new Event(type, { bubbles: true }));
    }

    // Fills the way a person would, so React, Vue and plain scripts all see the change: the
    // prototype setter goes past a framework's own `value` property, then the events tell it.
    function apply(actions) {
        return actions.map((action) => {
            const element = elementFor(action.ref);
            if (!element) {
                return { ref: action.ref, found: false };
            }
            if (action.kind === 'check') {
                if (element.checked !== action.checked) {
                    element.click();
                }
            } else {
                const setter = valueSetters[element.tagName.toLowerCase()];
                element.focus();
                if (setter) {
                    setter.call(element, action.value);
                }
                fire(element, 'input');
                fire(element, 'change');
                element.blur();
            }
            return { ref: action.ref, found: true, value: (element.value || '').slice(0, maxValue), checked: Boolean(element.checked) };
        });
    }

    let lastChange = 0;
    let observer = null;

    function millisecondsSinceLastChange() {
        if (!observer) {
            lastChange = Date.now();
            observer = new MutationObserver(() => {
                lastChange = Date.now();
            });
            observer.observe(document, { subtree: true, childList: true, attributes: true, characterData: true });
        }
        return Date.now() - lastChange;
    }

    function click(ref) {
        const element = elementFor(ref);
        if (!element) {
            return false;
        }
        millisecondsSinceLastChange();
        lastChange = Date.now();
        element.click();
        return true;
    }

    function isSubmitType(element) {
        const tag = element.tagName;
        return (tag === 'BUTTON' && element.type === 'submit') || (tag === 'INPUT' && (element.type === 'submit' || element.type === 'image'));
    }

    function submit(formRef, submitterRef) {
        const form = elementFor(formRef);
        const submitter = submitterRef ? elementFor(submitterRef) : null;
        if (!form) {
            return false;
        }
        millisecondsSinceLastChange();
        lastChange = Date.now();
        if (form instanceof HTMLFormElement) {
            if (submitter && submitter.form === form && isSubmitType(submitter)) {
                form.requestSubmit(submitter);
            } else if (submitter) {
                submitter.click();
            } else {
                form.requestSubmit();
            }
            return true;
        }
        // A "form" without a <form> element can only be sent through its button.
        if (submitter) {
            submitter.click();
            return true;
        }
        return false;
    }

    globalThis.__duckAIForms = { page, apply, click, submit, millisecondsSinceLastChange };
})();
