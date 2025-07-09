import { h } from 'preact';
import { useContext, useEffect, useState, useCallback } from 'preact/hooks';
import { GlobalContext } from '../../global';
import { useEnv } from '../../../../../shared/components/EnvironmentProvider';

import styles from './Animation.module.css';

/**
 * @typedef {'idle'|'animating'|'done'} AnimationState
 */

/**
 * @param {object} props
 * @param {() => void} [props.onAnimationEnd]
 * @param {import("preact").ComponentChild} props.children
 */
export function SlideIn({ children, onAnimationEnd }) {
    const [animationState, setAnimationState] = useState(/** @type {AnimationState} */ 'idle');
    const { activeStepVisible, activeStep } = useContext(GlobalContext);
    const { isReducedMotion } = useEnv();

    const animationEnd = useCallback(() => {
        setAnimationState('done');
        // eslint-disable-next-line @typescript-eslint/no-unused-expressions
        onAnimationEnd && onAnimationEnd();
    }, [onAnimationEnd]);

    useEffect(() => {
        setAnimationState(activeStepVisible ? 'animating' : 'idle');
        if (isReducedMotion) animationEnd();
    }, [activeStep, activeStepVisible, isReducedMotion]);

    const animationDidEnd = (e) => {
        if (e.animationName === 'Animation_slide') animationEnd();
    };

    return (
        <div class={styles.container} onAnimationEnd={animationDidEnd} key={activeStep} data-animation-state={animationState}>
            <div className={styles.slideIn}>{children}</div>
        </div>
    );
}
