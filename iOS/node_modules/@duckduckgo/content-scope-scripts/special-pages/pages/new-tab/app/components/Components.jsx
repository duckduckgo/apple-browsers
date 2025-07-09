import { Fragment, h } from 'preact';
import styles from './Components.module.css';
import { mainExamples, otherExamples } from './Examples.jsx';
import { useThemes } from '../customizer/themes.js';
import { useSignal } from '@preact/signals';
import { BackgroundConsumer } from './BackgroundProvider.js';
import { CustomizerThemesContext } from '../customizer/CustomizerProvider.js';
const url = new URL(window.location.href);

const list = {
    ...mainExamples,
    ...otherExamples,
};

const entries = Object.entries(list);

export function Components() {
    const ids = url.searchParams.getAll('id');
    const isolated = url.searchParams.has('isolate');
    const e2e = url.searchParams.has('e2e');
    const entryIds = entries.map(([id]) => id);
    const validIds = ids.filter((id) => entryIds.includes(id));
    const filtered = validIds.length ? validIds.map((id) => /** @type {const} */ ([id, list[id]])) : entries;

    /** @type {import('../../types/new-tab').CustomizerData} */
    const data = {
        background: { kind: 'default' },
        userImages: [],
        theme: 'system',
        userColor: null,
    };
    const dataSignal = useSignal(data);
    const { main, browser } = useThemes(dataSignal);

    return (
        <CustomizerThemesContext.Provider value={{ main, browser }}>
            <div class={styles.main} data-main-scroller data-theme={main}>
                <BackgroundConsumer browser={browser} />
                <div data-content-tube class={styles.contentTube}>
                    {isolated && <Isolated entries={filtered} e2e={e2e} />}
                    {!isolated && (
                        <Fragment>
                            <DebugBar id={ids[0]} ids={ids} entries={entries} />
                            <Stage entries={/** @type {any} */ (filtered)} />
                        </Fragment>
                    )}
                </div>
            </div>
        </CustomizerThemesContext.Provider>
    );
}

/**
 * Represents a stage in a software application.
 *
 * @param {Object} options - The stage options.
 * @param {Array<[string, {factory: () => any}]>} options.entries - An array of entries in the stage.
 */
function Stage({ entries }) {
    return (
        <div class={styles.componentList} data-testid="stage">
            {entries.map(([id, item]) => {
                const next = new URL(url);
                next.searchParams.set('isolate', 'true');
                next.searchParams.set('id', id);

                const selected = new URL(url);
                selected.searchParams.set('id', id);

                const e2e = new URL(url);
                e2e.searchParams.set('isolate', 'true');
                e2e.searchParams.set('id', id);
                e2e.searchParams.set('e2e', 'true');

                const without = new URL(url);
                const current = without.searchParams.getAll('id');
                const others = current.filter((x) => x !== id);
                const matching = current.filter((x) => x === id);
                const matchingMinus1 = matching.length === 1 ? [] : matching.slice(0, -1);

                without.searchParams.delete('id');
                for (let string of [...others, ...matchingMinus1]) {
                    without.searchParams.append('id', string);
                }

                return (
                    <Fragment>
                        <div class={styles.itemInfo}>
                            <div class={styles.itemLinks}>
                                <code>{id}</code>
                                <a href={next.toString()} target="_blank" title="open in new tab">
                                    Open 🔗
                                </a>{' '}
                                <a href={without.toString()} hidden={current.length === 0}>
                                    Remove
                                </a>
                            </div>
                            <div class={styles.itemLinks}>
                                <a href={selected.toString()} class={styles.itemLink} title="show this component only">
                                    select
                                </a>{' '}
                                <a href={next.toString()} target="_blank" class={styles.itemLink} title="isolate this component">
                                    isolate
                                </a>{' '}
                                <a href={e2e.toString()} target="_blank" class={styles.itemLink} title="isolate this component">
                                    edge-to-edge
                                </a>
                            </div>
                        </div>
                        <div className={styles.item} key={id}>
                            {item.factory()}
                        </div>
                    </Fragment>
                );
            })}
        </div>
    );
}

function Isolated({ entries, e2e }) {
    if (e2e) {
        return (
            <div data-isolated={true}>
                {entries.map(([id, item]) => {
                    return <Fragment key={id}>{item.factory()}</Fragment>;
                })}
            </div>
        );
    }
    return (
        <div class={styles.componentList} data-testid="stage" data-isolated={true}>
            {entries.map(([id, item], index) => {
                return <div key={id + index}>{item.factory()}</div>;
            })}
        </div>
    );
}

function DebugBar({ entries, id, ids }) {
    return (
        <div class={styles.debugBar} data-testid="selector">
            <ExampleSelector entries={entries} id={id} />
            {ids.length > 0 && <Append entries={entries} />}
            <TextLength />
            <Isolate />
        </div>
    );
}

function TextLength() {
    function onClick() {
        url.searchParams.set('textLength', '1.5');
        window.location.href = url.toString();
    }
    function onReset() {
        url.searchParams.delete('textLength');
        window.location.href = url.toString();
    }
    return (
        <div class={styles.buttonRow}>
            <button onClick={onReset} type="button">
                Text Length 1x
            </button>
            <button onClick={onClick} type="button">
                Text Length 1.5x
            </button>
        </div>
    );
}

function Isolate() {
    const next = new URL(url);
    next.searchParams.set('isolate', 'true');
    const prod = new URL('/build/pages/new-tab', 'https://content-scope-scripts.netlify.app');
    prod.search = url.search;
    return (
        <div class={styles.buttonRow}>
            <a href={next.toString()} target={'_blank'}>
                Isolate (open in a new tab)
            </a>
            <a href={prod.toString()} target={'_blank'}>
                Open in Production (new tab)
            </a>
        </div>
    );
}

/**
 * Allows users to select an example from a list and update the URL accordingly.
 *
 * @param {Object} options - The options object.
 * @param {Array} options.entries - The list of examples to choose from, each represented as an array with an id.
 * @param {string} options.id - The current selected example id.
 */
function ExampleSelector({ entries, id }) {
    function onReset() {
        const url = new URL(window.location.href);
        url.searchParams.delete('id');
        window.location.href = url.toString();
    }

    function onChange(event) {
        if (!event.target) return;
        if (!(event.target instanceof HTMLSelectElement)) return;
        const selectedId = event.target.value;
        if (selectedId) {
            if (selectedId === 'none') return onReset();
            const url = new URL(window.location.href);
            url.searchParams.set('id', selectedId);
            window.location.href = url.toString();
        }
    }
    return (
        <Fragment>
            <div class={styles.buttonRow}>
                <label>
                    Single:{' '}
                    <select value={id || 'none'} onChange={onChange}>
                        <option value="none">Select an example</option>
                        {entries.map(([id]) => (
                            <option key={id} value={id}>
                                {id}
                            </option>
                        ))}
                    </select>
                </label>
                <button onClick={onReset}>RESET 🔁</button>
            </div>
        </Fragment>
    );
}

export function TubeGrid({ children }) {
    return <div class={styles.tubeGrid}>{children}</div>;
}

/**
 * Allows users to select an example from a list and update the URL accordingly.
 *
 * @param {Object} options - The options object.
 * @param {Array} options.entries - The list of examples to choose from, each represented as an array with an id.
 */
function Append({ entries }) {
    function onReset() {
        const url = new URL(window.location.href);
        url.searchParams.delete('id');
        window.location.href = url.toString();
    }

    function onSubmit(event) {
        if (!event.target) return;
        event.preventDefault();
        const form = event.target;
        const data = new FormData(form);
        const value = data.get('add-id');
        if (typeof value !== 'string') return;
        const url = new URL(window.location.href);
        url.searchParams.append('id', value);
        window.location.href = url.toString();
    }

    return (
        <Fragment>
            <form class={styles.buttonRow} onSubmit={onSubmit}>
                <label>
                    Append:{' '}
                    <select value="none" name="add-id">
                        <option value="none">Select an example</option>
                        {entries.map(([id]) => (
                            <option key={id} value={id}>
                                {id}
                            </option>
                        ))}
                    </select>
                </label>
                <button>Confirm</button>
            </form>
        </Fragment>
    );
}
