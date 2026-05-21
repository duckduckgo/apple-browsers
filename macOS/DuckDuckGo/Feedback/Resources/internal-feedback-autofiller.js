var quickMode = %QUICK_MODE%;
var diagnosticsText = %DIAGNOSTICS%;
var screenshotBase64 = %SCREENSHOT_BASE64%;
var osVersion = %OS_VERSION%;
var appVersion = %APP_VERSION%;

function openDropdown(label) {
    const dropdown = document.querySelector(`[aria-label^="${label}"]`);
    if (dropdown) {
        dropdown.click();
    } else {
        console.error(`Dropdown with label "${label}" not found.`);
    }
}

function selectOption(optionText) {
    setTimeout(() => {
        const option = Array.from(document.querySelectorAll('[role="option"], .dropdown-option, .select-option'))
            .find(el => el.textContent.trim() === optionText);
        if (option) {
            option.click();
        } else {
            console.error(`Option "${optionText}" not found in dropdown.`);
        }
    }, 100);
}

function setInputValue(input, value) {
    const nativeInputValueSetter = Object.getOwnPropertyDescriptor(
        window.HTMLInputElement.prototype,
        'value'
    ).set;

    nativeInputValueSetter.call(input, value);

    const inputEvent = new Event('input', { bubbles: true });
    input.dispatchEvent(inputEvent);
}

function setInputAfterLabel(tag, labelText, value) {
    const xpath = `//${tag}[contains(text(), '${labelText}')]/following::input[@type='text'][1]`;
    const result = document.evaluate(xpath, document, null, XPathResult.FIRST_ORDERED_NODE_TYPE, null);
    const input = result.singleNodeValue;

    if (input) {
        if (value) {
            setInputValue(input, value);
        } else {
            input.focus();
        }
    } else {
        console.error(`${tag} field after label "${labelText}" not found.`);
    }
}

function waitForElement(tag, text, timeout = 5000) {
    return new Promise((resolve, reject) => {
        const startTime = Date.now();

        const checkForElement = () => {
            const element = Array.from(document.querySelectorAll(tag))
                .find(x => x.textContent.trim().startsWith(text));

            if (element) {
                resolve(element);
                return;
            }

            if (Date.now() - startTime >= timeout) {
                reject(new Error(`Timeout: ${tag} with text "${text}" not found within ${timeout}ms`));
                return;
            }

            setTimeout(checkForElement, 100);
        };

        checkForElement();
    });
}

function hideFormQuestion(labelText) {
    const labels = Array.from(document.querySelectorAll('label'));
    const match = labels.find(l => l.textContent.trim().startsWith(labelText));
    if (match) {
        const question = match.closest('.WorkRequestsFieldRow');
        if (question) {
            question.style.display = 'none';
        }
    }
}

function rehideFieldsWhenReturningToNativeApps() {
    var wasNativeApps = true;
    const observer = new MutationObserver(() => {
        const selected = document.querySelector('[aria-label^="Which product area or team does this feedback relate to?"]');
        if (!selected) return;
        const isNativeApps = selected.textContent.trim().includes('Native Apps');
        if (isNativeApps && !wasNativeApps) {
            fillOutFormAfterNativeAppsSelected();
        }
        wasNativeApps = isNativeApps;
    });
    observer.observe(document.body, { childList: true, subtree: true, characterData: true });
}

var quickModeUIInjected = false;

function addEmailFieldPadding() {
    var emailLabel = Array.from(document.querySelectorAll('label'))
        .find(function(l) {
            var text = l.textContent.trim().toLowerCase();
            return text.startsWith('your email') || text.startsWith('email');
        });
    if (!emailLabel) return;
    var emailRow = emailLabel.closest('.WorkRequestsFieldRow');
    if (emailRow) {
        emailRow.style.marginTop = '16px';
    }
}

function hideIrrelevantFields() {
    const fieldsToHide = [
        'Which platform?',
        'Which macOS version',
        'Which version of the DuckDuckGo',
        'Describe the issue',
        '[IGNORE IF NO]',
        'If available, attach any screenshots',
        'Which downstream provider',
        'Ban type',
    ];
    fieldsToHide.forEach(hideFormQuestion);

    if (quickModeUIInjected) return;
    quickModeUIInjected = true;

    addEmailFieldPadding();
    moveSubmitButtonUnderDescription();
    injectDiagnosticsSection();
    injectScreenshotSection();
    hookSubmitForDiagnostics();
    rehideFieldsWhenReturningToNativeApps();

    var hider = document.getElementById('ddg-form-hider');
    if (hider) {
        hider.textContent = '.WorkRequestsSection { opacity: 1; transition: opacity 0.15s; }';
    }

    setTimeout(function() {
        var descLabel = Array.from(document.querySelectorAll('label'))
            .find(function(l) { return l.textContent.trim().startsWith('Please describe your issue/feedback'); });
        if (descLabel) {
            var descRow = descLabel.closest('.WorkRequestsFieldRow');
            if (descRow) {
                descLabel.textContent = 'Please provide your feedback here!';
                var helperText = descRow.querySelector('.WorkRequestsFieldRow-helpText, .WorkRequestsFieldRow-description');
                if (!helperText) {
                    var spans = descRow.querySelectorAll('span, p, div');
                    for (var i = 0; i < spans.length; i++) {
                        if (spans[i].textContent.trim().startsWith('What was the expectation')) {
                            helperText = spans[i];
                            break;
                        }
                    }
                }
                if (helperText) {
                    helperText.textContent = 'An engineer will contact you via Asana if more information is required or helpful. Thank you!';
                }
                var textarea = descRow.querySelector('textarea');
                if (textarea) {
                    textarea.click();
                    textarea.focus();
                }
            }
        }
    }, 300);
}

function moveSubmitButtonUnderDescription() {
    var descLabel = Array.from(document.querySelectorAll('label'))
        .find(function(l) { return l.textContent.trim().startsWith('Please describe your issue/feedback'); });
    if (!descLabel) return;
    var descRow = descLabel.closest('.WorkRequestsFieldRow');
    if (!descRow) return;

    var realSubmitArea = document.querySelector('.WorkRequestsSubmissionForm-submitButtonAndError');
    if (!realSubmitArea) return;

    var realSubmitBtn = document.querySelector('.WorkRequestsSubmissionForm-submitButton');
    if (!realSubmitBtn) return;

    realSubmitArea.style.display = 'none';

    var clone = realSubmitBtn.cloneNode(true);
    clone.style.cssText = 'margin: 12px 0 0; width: 100%; cursor: pointer;';
    clone.id = 'ddg-submit-clone';

    clone.addEventListener('click', function(e) {
        e.preventDefault();
        e.stopPropagation();
        realSubmitBtn.click();
    });

    descRow.parentNode.insertBefore(clone, descRow.nextSibling);
}

function injectDiagnosticsSection() {
    var submitClone = document.getElementById('ddg-submit-clone');
    var anchor = submitClone;

    if (!anchor) {
        var labels = Array.from(document.querySelectorAll('label'));
        var descLabel = labels.find(function(l) {
            return l.textContent.trim().startsWith('Please describe your issue/feedback');
        });
        if (descLabel) anchor = descLabel.closest('.WorkRequestsFieldRow');
    }
    if (!anchor) return;

    var section = document.createElement('div');
    section.id = 'ddg-diagnostics-section';
    section.style.cssText = 'margin: 12px 24px 0; padding: 0;';

    var headerRow = document.createElement('div');
    headerRow.style.cssText = 'display: flex; align-items: center; gap: 8px;';

    var cb = document.createElement('input');
    cb.type = 'checkbox';
    cb.id = 'ddg-include-diagnostics';
    cb.checked = true;
    headerRow.appendChild(cb);

    var cbLabel = document.createElement('label');
    cbLabel.setAttribute('for', 'ddg-include-diagnostics');
    cbLabel.textContent = 'Include system diagnostics';
    cbLabel.style.cssText = 'font-size: 14px; cursor: pointer;';
    headerRow.appendChild(cbLabel);

    section.appendChild(headerRow);

    var details = document.createElement('details');
    details.style.cssText = 'margin-top: 6px;';

    var summary = document.createElement('summary');
    summary.textContent = 'View diagnostics';
    summary.style.cssText = 'font-size: 12px; color: #666; cursor: pointer; user-select: none;';
    details.appendChild(summary);

    var pre = document.createElement('pre');
    pre.textContent = diagnosticsText;
    pre.style.cssText = 'font-size: 11px; background: #f5f5f5; padding: 10px; border-radius: 4px; margin: 6px 0 0; overflow-x: auto; white-space: pre-wrap; word-break: break-word; max-height: 200px; overflow-y: auto;';
    details.appendChild(pre);

    section.appendChild(details);

    anchor.parentNode.insertBefore(section, anchor.nextSibling);
}

function injectScreenshotSection() {
    if (!screenshotBase64 || screenshotBase64 === '') return;

    var anchor = document.getElementById('ddg-diagnostics-section') || document.getElementById('ddg-submit-clone');
    if (!anchor) return;

    var section = document.createElement('div');
    section.id = 'ddg-screenshot-section';
    section.style.cssText = 'margin: 12px 24px 0; padding: 0;';

    var headerRow = document.createElement('div');
    headerRow.style.cssText = 'display: flex; align-items: center; gap: 8px;';

    var cb = document.createElement('input');
    cb.type = 'checkbox';
    cb.id = 'ddg-include-screenshot';
    cb.checked = false;
    headerRow.appendChild(cb);

    var cbLabel = document.createElement('label');
    cbLabel.setAttribute('for', 'ddg-include-screenshot');
    cbLabel.textContent = 'Include screenshot';
    cbLabel.style.cssText = 'font-size: 14px; cursor: pointer;';
    headerRow.appendChild(cbLabel);

    section.appendChild(headerRow);

    var warning = document.createElement('div');
    warning.style.cssText = 'font-size: 12px; color: #856404; background: #fff3cd; padding: 6px 10px; border-radius: 4px; margin: 6px 0 8px; display: none;';
    warning.textContent = '\u26A0 This screenshot may contain private information. Please review carefully before including it.';
    section.appendChild(warning);

    cb.addEventListener('change', function() {
        warning.style.display = cb.checked ? '' : 'none';
    });

    var img = document.createElement('img');
    img.src = 'data:image/png;base64,' + screenshotBase64;
    img.style.cssText = 'max-width: 100%; max-height: 150px; margin-top: 6px; border: 1px solid #ddd; border-radius: 4px; cursor: pointer;';
    img.title = 'Click to enlarge';

    img.addEventListener('click', function() {
        var overlay = document.createElement('div');
        overlay.style.cssText = 'position:fixed;top:0;left:0;width:100%;height:100%;background:rgba(0,0,0,0.85);z-index:99999;display:flex;flex-direction:column;align-items:center;justify-content:center;cursor:pointer;padding:16px;box-sizing:border-box;';

        var closeBtn = document.createElement('button');
        closeBtn.textContent = '\u2715 Close';
        closeBtn.style.cssText = 'position:absolute;top:12px;right:16px;background:rgba(255,255,255,0.15);border:1px solid rgba(255,255,255,0.3);color:white;font-size:14px;padding:6px 14px;border-radius:6px;cursor:pointer;';
        closeBtn.addEventListener('click', function() { overlay.remove(); });
        overlay.appendChild(closeBtn);

        var bigImg = document.createElement('img');
        bigImg.src = img.src;
        bigImg.style.cssText = 'max-width:100%;max-height:calc(100% - 40px);object-fit:contain;border-radius:4px;';
        overlay.appendChild(bigImg);
        overlay.addEventListener('click', function(e) { if (e.target === overlay) overlay.remove(); });
        document.body.appendChild(overlay);
    });

    section.appendChild(img);

    anchor.parentNode.insertBefore(section, anchor.nextSibling);
}

function attachScreenshotToForm() {
    var img = document.querySelector('#ddg-screenshot-section img');
    if (!img || !img.src.startsWith('data:image/png;base64,')) return;

    var base64 = img.src.split(',')[1];
    var binary = atob(base64);
    var array = new Uint8Array(binary.length);
    for (var i = 0; i < binary.length; i++) {
        array[i] = binary.charCodeAt(i);
    }
    var file = new File([array], 'screenshot.png', { type: 'image/png' });

    var attachLabel = Array.from(document.querySelectorAll('label'))
        .find(function(l) { return l.textContent.trim().startsWith('If available, attach'); });
    if (!attachLabel) return;

    var attachRow = attachLabel.closest('.WorkRequestsFieldRow');
    if (!attachRow) return;

    attachRow.style.display = '';
    var fileInput = attachRow.querySelector('input[type="file"]');
    if (fileInput) {
        var dt = new DataTransfer();
        dt.items.add(file);
        fileInput.files = dt.files;
        fileInput.dispatchEvent(new Event('change', { bubbles: true }));
    }
    setTimeout(function() { attachRow.style.display = 'none'; }, 200);
}

function hookSubmitForDiagnostics() {
    var submitBtn = document.querySelector('.WorkRequestsSubmissionForm-submitButton');
    if (!submitBtn) return;

    submitBtn.addEventListener('click', function() {
        var descLabel = Array.from(document.querySelectorAll('label'))
            .find(function(l) {
                var t = l.textContent.trim();
                return t.startsWith('Please provide your feedback') || t.startsWith('Please describe your issue/feedback');
            });
        if (!descLabel) return;
        var descRow = descLabel.closest('.WorkRequestsFieldRow');
        if (!descRow) return;
        var textarea = descRow.querySelector('textarea');
        if (!textarea) return;

        var diagsSentinel = '--- Diagnostics (auto-collected) ---';
        var rawText = textarea.value;
        var sentinelIdx = rawText.indexOf(diagsSentinel);
        var userText = (sentinelIdx !== -1 ? rawText.substring(0, sentinelIdx) : rawText).trim();

        var titleLabel = Array.from(document.querySelectorAll('label'))
            .find(function(l) { return l.textContent.trim().startsWith('Describe the issue'); });
        if (titleLabel) {
            var titleInput = document.getElementById(titleLabel.getAttribute('for'));
            if (titleInput) {
                var titleText = userText.length > 100 ? userText.substring(0, 100) + '...' : userText;
                if (!titleText) titleText = 'Feedback (no description)';
                setInputValue(titleInput, titleText);
            }
        }

        var diagsCb = document.getElementById('ddg-include-diagnostics');
        if (diagsCb && diagsCb.checked && diagnosticsText) {
            var combined = userText
                ? userText + '\n\n' + diagnosticsText
                : diagnosticsText;

            var setter = Object.getOwnPropertyDescriptor(
                window.HTMLTextAreaElement.prototype, 'value'
            ).set;
            setter.call(textarea, combined);
            textarea.dispatchEvent(new Event('input', { bubbles: true }));
        }

        var screenshotCb = document.getElementById('ddg-include-screenshot');
        if (screenshotCb && screenshotCb.checked) {
            attachScreenshotToForm();
        }

    }, true);
}

function fillOutFormAfterNativeAppsSelected() {
    waitForElement('label', 'Which platform?')
        .then(() => {
            openDropdown('Which platform?');
            selectOption('macOS Browser');

            waitForElement('label', 'Which macOS version?')
                .then(() => {
                    setInputAfterLabel('label', 'Which macOS version?', osVersion);
                    setInputAfterLabel('label', 'Which version of the DuckDuckGo Browser?', appVersion);

                    if (quickMode) {
                        setTimeout(hideIrrelevantFields, 50);
                    } else {
                        setInputAfterLabel('label', 'Asana Task Title');
                    }
                })
                .catch(error => console.error('"Which macOS version?" label not found:', error));
        })
        .catch(error => console.error('"Which platform?" label not found:', error));
}

function handleNativeAppsDropdown() {
    openDropdown('Which product area or team does this feedback relate to?');
    selectOption('Native Apps & Extensions');

    const observer = new MutationObserver(() => {
        const selected = document.querySelector('[aria-label^="Which product area or team does this feedback relate to?"]');
        if (selected && selected.textContent.trim().includes('Native Apps')) {
            observer.disconnect();
            fillOutFormAfterNativeAppsSelected();
        }
    });

    observer.observe(document.body, { childList: true, subtree: true, characterData: true });
}

waitForElement('h1', 'Internal Product Feedback Form')
    .then(_ => handleNativeAppsDropdown())
    .catch(_ => console.error('Internal Product Feedback Form is not loaded after 5s'));
