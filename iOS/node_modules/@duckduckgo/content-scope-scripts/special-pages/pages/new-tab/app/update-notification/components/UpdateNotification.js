import { Fragment, h } from 'preact';
import cn from 'classnames';
import styles from './UpdateNotification.module.css';
import { useContext, useId, useRef } from 'preact/hooks';
import { UpdateNotificationContext } from '../UpdateNotificationProvider.js';
import { useTypedTranslationWith } from '../../types.js';
import { Trans } from '../../../../../shared/components/TranslationsProvider.js';
import { DismissButton } from '../../components/DismissButton';

/**
 * @param {object} props
 * @param {string[]} props.notes
 * @param {string} props.version
 * @param {() => void} [props.dismiss]
 */

export function UpdateNotification({ notes, dismiss, version }) {
    return (
        <div class={styles.root} data-reset-layout="true">
            <div class={cn('layout-centered', styles.body)}>
                {notes.length > 0 ? <WithNotes notes={notes} version={version} /> : <WithoutNotes version={version} />}
            </div>
            <DismissButton onClick={dismiss} className={styles.dismiss} />
        </div>
    );
}

/**
 * @param {object} props
 * @param {string[]} props.notes
 * @param {string} props.version
 */
export function WithNotes({ notes, version }) {
    const id = useId();
    const ref = useRef(/** @type {HTMLDetailsElement|null} */ (null));
    const { t } = useTypedTranslationWith(/** @type {import("../strings.json")} */ ({}));
    const inlineLink = (
        <Trans
            str={t('updateNotification_whats_new')}
            values={{
                a: {
                    href: `#${id}`,
                    class: styles.inlineLink,
                    click: (e) => {
                        e.preventDefault();
                        if (!ref.current) return;
                        ref.current.open = !ref.current.open;
                    },
                },
            }}
        />
    );
    /** @type {{title: string, notes:string[]}[]} */
    const chunks = [{ title: '', notes: [] }];
    let index = 0;

    for (const note of notes) {
        const trimmed = note.trim();
        if (!trimmed) continue;
        if (trimmed.startsWith('•')) {
            /**
             * Note: Doing this here as a very specific 'view' concern
             * Note: using the `if` + `.slice` to avoid regex
             * Note: `.slice` is safe on `•` because it is a single Unicode character
             *       and is represented by a single UTF-16 code unit.
             */
            const bullet = trimmed.slice(1).trim();
            chunks[index].notes.push(bullet);
        } else {
            chunks.push({ title: trimmed, notes: [] });
            index += 1;
        }
    }

    return (
        <details ref={ref}>
            <summary tabIndex={-1} className={styles.summary}>
                {t('updateNotification_updated_version', { version })} {inlineLink}
            </summary>
            <div id={id} class={styles.detailsContent}>
                {chunks.map((chunk, index) => {
                    return (
                        <Fragment key={chunk.title + index}>
                            {chunk.title && <p class={styles.title}>{chunk.title}</p>}
                            <ul class={styles.list}>
                                {chunk.notes.map((note, index) => {
                                    return <li key={note + index}>{note}</li>;
                                })}
                            </ul>
                        </Fragment>
                    );
                })}
            </div>
        </details>
    );
}

export function WithoutNotes({ version }) {
    const { t } = useTypedTranslationWith(/** @type {import("../strings.json")} */ ({}));
    return <p>{t('updateNotification_updated_version', { version })}</p>;
}

export function UpdateNotificationConsumer() {
    const { state, dismiss } = useContext(UpdateNotificationContext);

    // `state.data.content` can be empty - meaning there's no message to display!
    if (state.status === 'ready' && state.data.content) {
        return <UpdateNotification notes={state.data.content.notes} version={state.data.content.version} dismiss={dismiss} />;
    }
    return null;
}
