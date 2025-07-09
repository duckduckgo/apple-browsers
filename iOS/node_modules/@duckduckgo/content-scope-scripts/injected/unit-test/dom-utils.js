import { html } from '../src/dom-utils.js';

describe('dom-utils.js - escapedTemplate', () => {
    const tests = [
        { title: 'single', input: () => html`<p>Foo</p>`, expected: '<p>Foo</p>' },
        {
            title: 'siblings',
            input: () =>
                html`<p>Foo</p>
                    <p>Bar</p>`,
            expected: `<p>Foo</p>
                    <p>Bar</p>`,
        },
        { title: 'nested', input: () => html`<div>${html`<p>${'Nested'}</p>`}</div>`, expected: '<div><p>Nested</p></div>' },
        {
            title: 'loop',
            input: () => {
                const items = [{ value: 'foo' }, { value: 'bar' }];
                return html`<h1>Heading</h1>
                    <ul>
                        ${items.map((item) => html`<li>${item.value}</li>`)};
                    </ul>`;
            },
            expected: `<h1>Heading</h1>
                    <ul>
                        <li>foo</li><li>bar</li>;
                    </ul>`,
        },
    ];
    for (const test of tests) {
        it(`should generate ${test.title}`, () => {
            const actual = test.input().toString();
            expect(actual).toEqual(test.expected);
        });
    }
});
