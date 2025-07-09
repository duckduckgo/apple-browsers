import { h, Fragment } from 'preact';
import { useReducer } from 'preact/hooks';
import { Stack } from './Stack';
import { Button, ButtonBar } from './Buttons';
import { Play, Replay, SlideIn } from './Icons';

import styles from './BeforeAfter.module.css';
import { useAutoAnimate } from '@formkit/auto-animate/preact';
import { useEnv } from '../../../../shared/components/EnvironmentProvider';
import { useTypedTranslation } from '../types';

/**
 * A component that renders an image with a before and after effect.
 *
 * @param {Object} props - The parameters for the component.
 * @param {() => void} props.onDone - The function to be called when the "Got it" button is clicked.
 * @param {string} props.btnBefore - The label for the button to show the before effect.
 * @param {string} props.btnAfter - The label for the button to show the after effect.
 * @param {(args: {state: 'initial' | 'before' | 'after', className: string}) => import("preact").ComponentChild} props.media - A function that returns the media to display
 */
export function BeforeAfter({ media, onDone, btnBefore, btnAfter }) {
    const { t } = useTypedTranslation();
    const { isReducedMotion } = useEnv();
    const [imageParent] = useAutoAnimate(isReducedMotion ? { duration: 0 } : undefined);

    // differentiate between initial states vs before/after
    const [state, dispatch] = useReducer((/** @type {'initial' | 'before' | 'after'} */ prev) => {
        if (prev === 'initial') return 'after';
        if (prev === 'before') return 'after';
        if (prev === 'after') return 'before';
        throw new Error('unreachable');
    }, 'initial');

    return (
        <Stack gap="var(--sp-3)">
            <div className={styles.imgWrap} ref={imageParent}>
                {media({ state, className: styles.media })}
            </div>
            <ButtonBar>
                <Button variant={'secondary'} onClick={() => dispatch('toggle')} style={{ minWidth: '210px' }}>
                    {state === 'after' && (
                        <>
                            <Replay />
                            {btnAfter}
                        </>
                    )}
                    {(state === 'before' || state === 'initial') && (
                        <>
                            <Play />
                            {btnBefore}
                        </>
                    )}
                </Button>
                {state !== 'initial' && (
                    <SlideIn delay="double">
                        <Button onClick={onDone}>{t('gotIt')}</Button>
                    </SlideIn>
                )}
            </ButtonBar>
        </Stack>
    );
}
