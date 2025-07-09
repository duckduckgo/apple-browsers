import { h } from 'preact';
import { useId } from 'preact/hooks';
import { ShowHideBar, ShowHideButtonPill } from '../../components/ShowHideButton';
import { useTypedTranslationWith } from '../../types';
import { otherText } from '../nextsteps.data';
import styles from './NextSteps.module.css';
import { NextStepsCard } from './NextStepsCard';

/**
 * @import enStrings from '../strings.json';
 * @import ntpStrings from '../../strings.json';
 * @typedef {enStrings & ntpStrings} strings
 * @typedef {import('../../../types/new-tab').Expansion} Expansion
 * @typedef {import('../../../types/new-tab').Animation} Animation
 * @typedef {import('../../../types/new-tab').NextStepsCardTypes} NextStepsCardTypes
 */

/**
 * @param {object} props
 * @param {NextStepsCardTypes[]} props.types
 * @param {Expansion} props.expansion
 * @param {()=>void} props.toggle
 * @param {(id: string)=>void} props.action
 * @param {(id: string)=>void} props.dismiss
 */
export function NextStepsCardGroup({ types, expansion, toggle, action, dismiss }) {
    const { t } = useTypedTranslationWith(/** @type {strings} */ ({}));
    const WIDGET_ID = useId();
    const TOGGLE_ID = useId();
    const alwaysShown = types.length > 2 ? types.slice(0, 2) : types;

    return (
        <div class={styles.cardGroup} id={WIDGET_ID}>
            {types.length > 0 && <NextStepsBubbleHeader />}
            <div class={styles.cardGrid}>
                {alwaysShown.map((type) => (
                    <NextStepsCard key={type} type={type} dismiss={dismiss} action={action} />
                ))}
                {expansion === 'expanded' &&
                    types.length > 2 &&
                    types.slice(2).map((type) => <NextStepsCard key={type} type={type} dismiss={dismiss} action={action} />)}
            </div>

            {types.length > 2 && (
                <ShowHideBar>
                    <ShowHideButtonPill
                        buttonAttrs={{
                            'aria-expanded': expansion === 'expanded',
                            'aria-pressed': expansion === 'expanded',
                            'aria-controls': WIDGET_ID,
                            id: TOGGLE_ID,
                        }}
                        text={expansion === 'expanded' ? otherText.showLess(t) : otherText.showMore(t)}
                        label={undefined}
                        onClick={toggle}
                    />
                </ShowHideBar>
            )}
        </div>
    );
}

export function NextStepsBubbleHeader() {
    const { t } = useTypedTranslationWith(/** @type {strings} */ ({}));
    const text = otherText.nextSteps_sectionTitle(t);
    return (
        <div class={styles.bubble}>
            <svg xmlns="http://www.w3.org/2000/svg" width="12" height="26" viewBox="0 0 12 26" fill="none">
                <path
                    fill-rule="evenodd"
                    clip-rule="evenodd"
                    d="M12 0C5.37258 0 0 5.37258 0 12V25.3388C2.56367 22.0873 6.53807 20 11 20H12V0Z"
                    fill="#3969EF"
                />
            </svg>
            <div>
                <h2>{text}</h2>
            </div>
            <svg xmlns="http://www.w3.org/2000/svg" width="10" height="20" viewBox="0 0 10 20" fill="none">
                <path
                    d="M3.8147e-06 0C1.31322 1.566e-08 2.61358 0.258658 3.82684 0.761205C5.04009 1.26375 6.14249 2.00035 7.07107 2.92893C7.99966 3.85752 8.73625 4.95991 9.2388 6.17317C9.74135 7.38642 10 8.68678 10 10C10 11.3132 9.74135 12.6136 9.2388 13.8268C8.73625 15.0401 7.99966 16.1425 7.07107 17.0711C6.14248 17.9997 5.04009 18.7362 3.82684 19.2388C2.61358 19.7413 1.31322 20 0 20L3.8147e-06 10V0Z"
                    fill="#3969EF"
                />
            </svg>
        </div>
    );
}
