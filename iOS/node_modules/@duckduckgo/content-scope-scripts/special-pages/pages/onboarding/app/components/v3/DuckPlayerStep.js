import { h } from 'preact';
import { useEffect, useRef, useState } from 'preact/hooks';
import { useEnv } from '../../../../../shared/components/EnvironmentProvider';
import { RiveAnimation } from '../../components/RiveAnimation';
import { useBeforeAfter } from './BeforeAfterProvider';
import { SlideIn } from './Animation';

import onboardingAnimation from '../../animations/Onboarding.riv';

import styles from './DuckPlayerStep.module.css';

export function DuckPlayerStep() {
    const { isDarkMode, isReducedMotion } = useEnv();
    const [canPlay, setCanPlay] = useState(false);
    const { getStep, setStep } = useBeforeAfter();
    /** @type {import('preact/hooks').MutableRef<ReturnType<setTimeout>|null>} */
    const timer = useRef(null);

    useEffect(() => {
        if (canPlay && !timer.current) {
            timer.current = setTimeout(
                () => {
                    setStep('duckPlayerSingle', 'after');
                },
                isReducedMotion ? 100 : 0,
            );
        }

        return () => {
            if (timer.current) clearTimeout(timer.current);
        };
    }, [canPlay, isReducedMotion]);

    const animationDidEnd = () => {
        if (!timer.current) setCanPlay(true);
    };

    return (
        <SlideIn onAnimationEnd={animationDidEnd}>
            <div className={styles.animationContainer}>
                <RiveAnimation
                    animation={onboardingAnimation}
                    state={getStep('duckPlayerSingle') || 'before'}
                    isDarkMode={isDarkMode}
                    artboard="Duck Player"
                    inputName="Duck Player?"
                    stateMachine="State Machine 2"
                />
            </div>
        </SlideIn>
    );
}
