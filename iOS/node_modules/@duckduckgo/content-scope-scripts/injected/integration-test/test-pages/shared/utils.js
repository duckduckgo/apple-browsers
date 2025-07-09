/**
 * @typedef {object} ResultRow
 * @property {string} name The name of the test.
 * @property {any} result The result of the test.
 * @property {any} expected The expected result.
 */
function buildTableCell(value, tagName = 'td') {
    const td = document.createElement(tagName);
    td.textContent = value;
    return td;
}

/**
 * Builds a result table for the given results.
 * @param {Record<string, ResultRow>} results The results to build the table for.
 * @return {Element} The table element.
 */
function buildResultTable(results) {
    const table = document.createElement('table');
    table.className = 'results';
    const thead = document.createElement('thead');
    let tr = document.createElement('tr');
    tr.appendChild(buildTableCell('Test', 'th'));
    tr.appendChild(buildTableCell('Result', 'th'));
    tr.appendChild(buildTableCell('Expected', 'th'));
    thead.appendChild(tr);
    table.appendChild(thead);
    for (const name in results) {
        const resultSection = results[name];
        const tbody = document.createElement('tbody');
        tr = document.createElement('tr');
        const heading = buildTableCell(name, 'th');
        // @ts-expect-error - colSpan is not defined in the type definition
        heading.colSpan = 3;
        tr.appendChild(heading);
        tbody.appendChild(tr);

        // @ts-expect-error - resultSection.forEach is not defined in the type definition
        resultSection.forEach((result) => {
            const resultOut = JSON.stringify(result.result);
            const expectedOut = JSON.stringify(result.expected);
            tr = document.createElement('tr');
            tr.appendChild(buildTableCell(result.name));
            tr.appendChild(buildTableCell(resultOut));
            tr.appendChild(buildTableCell(expectedOut));
            tr.classList.add(resultOut === expectedOut ? 'pass' : 'fail');
            tbody.appendChild(tr);
        });
        table.appendChild(tbody);
    }
    return table;
}

let isInAutomation = false;
let isReadyPromiseResolve = null;
const isReadyPromise = new Promise((resolve) => {
    isReadyPromiseResolve = resolve;
});
const url = new URL(window.location.href);
createResultsHeader();
if (url.searchParams.get('automation')) {
    createRunButton();
    isInAutomation = true;
    window.addEventListener('content-scope-init-complete', () => {
        isReadyPromiseResolve();
    });
}

function createResultsHeader() {
    const summary = document.createElement('summary');
    summary.textContent = 'Test suite status: ';
    const output = document.createElement('output');
    output.id = 'test-status';
    output.textContent = 'pending';
    summary.appendChild(output);
    document.body.appendChild(summary);
}

function createRunButton() {
    const button = document.createElement('button');
    button.textContent = 'Run Tests';
    button.id = 'run-tests';
    button.addEventListener('click', () => {
        button.disabled = true;
        window.dispatchEvent(new Event('content-scope-init-complete'));
    });
    document.body.appendChild(button);
}

// @ts-expect-error - ongoingTests is not defined in the type definition
window.ongoingTests = [];
// eslint-disable-next-line @typescript-eslint/no-unused-vars
function test(name, test) {
    // @ts-expect-error - ongoingTests is not defined in the type definition
    window.ongoingTests.push({ name, test });
}

function updateResultsHeader(results) {
    const totalTests = Object.values(results).flat().length;
    const passed = Object.values(results)
        .flat()
        .filter((result) => result.result === result.expected).length;
    const output = document.getElementById('test-status');
    output.textContent = totalTests > 0 && passed === totalTests ? 'pass' : 'fail';
}

// eslint-disable-next-line @typescript-eslint/no-unused-vars
async function renderResults() {
    const results = {};
    if (isInAutomation) {
        await isReadyPromise;
    }
    // @ts-expect-error - ongoingTests is not defined in the type definition
    for (const test of window.ongoingTests) {
        const result = await test.test().catch((e) => console.error(`${test.name} threw`, e));
        results[test.name] = result;
    }
    updateResultsHeader(results);
    // @ts-expect-error - buildResultTable is not defined in the type definition
    document.body.appendChild(buildResultTable(results));
    // @ts-expect-error - results is not defined in the type definition
    window.results = results;
    window.dispatchEvent(new CustomEvent('results-ready', { detail: results }));
}
