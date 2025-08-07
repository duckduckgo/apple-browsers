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
            input.focus()
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

function fillOutForm() {
    openDropdown('Which product area or team does this feedback relate to?');
    selectOption('Native Apps');

    waitForElement('label', 'Which platform?')
        .then(() => {
            openDropdown('Which platform?');
            selectOption('macOS Browser');

            waitForElement('label', 'Which macOS version?')
                .then(() => {
                    setInputAfterLabel('label', 'Which macOS version?', '%OS_VERSION%');
                    setInputAfterLabel('label', 'Which version of the DuckDuckGo Browser?', '%APP_VERSION%');
                    // set with no value -> just focus it
                    setInputAfterLabel('label', 'Asana Task Title');
                })
                .catch(error => console.error('"Which macOS version?" label not found:', error));
        })
        .catch(error => console.error('"Which platform?" label not found:', error));
}

waitForElement('h1', 'Internal Product Feedback Form')
    .then(_ => fillOutForm())
    .catch(_ => console.error('Internal Product Feedback Form is not loaded after 5s'));
