import { h } from 'preact';
import cn from 'classnames';
import { useState, useRef, useLayoutEffect, useEffect } from 'preact/hooks';
import { Typed } from '../Typed';
import { useEnv } from '../../../../../shared/components/EnvironmentProvider';

import styles from './Heading.module.css';

/**
 * Animated Dax heading with optional speech bubble
 *
 * @param {object} props
 * @param {string|string[]|null} [props.title] - Heading title
 * @param {string|null} [props.subtitle] - Optional heading subtitle
 * @param {boolean} [props.speechBubble=false] - Display title and subtitle inside speech bubble
 * @param {() => void} [props.onTitleComplete] - Fires when title is done animating
 * @param {import('preact').ComponentChildren} [props.children]
 */
export function Heading({ title, subtitle, speechBubble = false, onTitleComplete, children }) {
    const onComplete = () => {
        // eslint-disable-next-line @typescript-eslint/no-unused-expressions
        onTitleComplete && onTitleComplete();
    };
    const HeadingComponent = speechBubble ? SpeechBubble : PlainHeading;

    if (!title) {
        console.warn('Missing title');
        return null;
    }

    const titleArray = Array.isArray(title) ? title : [title];

    return (
        <header className={styles.heading}>
            <div className={styles.logo}>
                <img className={styles.svg} src="assets/img/dax.svg" alt="DuckDuckGo Logo" />
            </div>
            <HeadingComponent title={titleArray} subtitle={subtitle} onComplete={onComplete}>
                {children}
            </HeadingComponent>
        </header>
    );
}

/**
 * @param {object} props
 * @param {string[]} props.title - Heading title
 * @param {string|null} [props.subtitle] - Optional heading subtitle
 * @param {() => void} [props.onComplete] - Fires when title is done animating
 * @param {import('preact').ComponentChildren} props.children
 */
function PlainHeading({ title, subtitle, onComplete, children }) {
    const [typingDone, setTypingDone] = useState(false);
    const onTypingComplete = () => {
        setTypingDone(true);
        // eslint-disable-next-line @typescript-eslint/no-unused-expressions
        onComplete && onComplete();
    };

    const subtitleClass = cn({
        [styles.subTitle]: true,
        [styles.hidden]: !typingDone,
    });

    return (
        <div className={styles.headingContents}>
            <h1 className={styles.title}>{<TypedTitle title={title} paused={false} onComplete={onTypingComplete} />}</h1>
            {subtitle && <h2 className={subtitleClass}>{subtitle}</h2>}
            {typingDone && children}
        </div>
    );
}

/** @typedef {'animating'|'animation-done'|'typing-done'} AnimationState */

/**
 * @param {object} props
 * @param {string[]} props.title - Heading title
 * @param {string|null} [props.subtitle] - Optional heading subtitle
 * @param {() => void} [props.onComplete]
 * @param {import('preact').ComponentChildren} props.children
 */
function SpeechBubble({ title, subtitle, onComplete, children }) {
    const bubbleContents = useRef(null);
    const { isReducedMotion } = useEnv();
    const [dimensions, setDimensions] = useState({ width: 0, height: 0 });

    const initialState = /** @type {AnimationState} */ (isReducedMotion ? 'typing-done' : 'animating');
    const [animationState, setAnimationState] = useState(initialState);

    /** @type {(element: HTMLElement) => { width: number, height: number }} */
    const calculateMaximumWidth = (element) => {
        const { height } = element.getBoundingClientRect();
        const widths = Array.from(element.querySelectorAll('.bubbleTitle span, .bubbleSubtitle, .bubbleChildren > *')).map(
            (e) => e.getBoundingClientRect().width,
        );
        const width = Math.max(...widths);

        return { width, height };
    };

    useLayoutEffect(() => {
        if (bubbleContents.current) {
            const { width, height } = calculateMaximumWidth(/** @type {HTMLDivElement} */ (bubbleContents.current));
            if (dimensions.width !== width || dimensions.height !== height) {
                setAnimationState(initialState);
                setDimensions({ width, height });
            }
        }
    }, [bubbleContents, title, subtitle, children]);

    useEffect(() => {
        let debounce;
        const handleResize = () => {
            if (bubbleContents.current) {
                const { width, height } = calculateMaximumWidth(/** @type {HTMLDivElement} */ (bubbleContents.current));
                if (dimensions.width !== width || dimensions.height !== height) {
                    setDimensions({ width, height });
                }
            }
        };

        window.addEventListener('resize', () => {
            clearTimeout(debounce);
            debounce = setTimeout(handleResize, 30);
        });

        return () => {
            clearTimeout(debounce);
            window.removeEventListener('resize', handleResize);
        };
    }, []);

    const onTransitionEnd = () => {
        setAnimationState((state) => {
            if (state === 'animating') return 'animation-done';
            return state;
        });
    };

    const onTypingComplete = () => {
        setAnimationState('typing-done');
        // eslint-disable-next-line @typescript-eslint/no-unused-expressions
        onComplete && onComplete();
    };

    const titleClass = cn(['bubbleTitle', styles.title]);

    const subtitleClass = cn({
        bubbleSubtitle: true,
        [styles.subTitle]: true,
        [styles.hidden]: animationState !== 'typing-done',
    });

    const childrenClass = cn({
        bubbleChildren: true,
        [styles.additionalContent]: true,
        [styles.hidden]: animationState !== 'typing-done',
    });

    return (
        <div className={styles.speechBubble}>
            <div className={styles.speechBubbleCallout} />
            <div className={styles.speechBubbleContainer}>
                <div
                    className={styles.speechBubbleBackground}
                    style={{ width: `${dimensions.width}px`, height: `${dimensions.height}px` }}
                    onTransitionEnd={onTransitionEnd}
                ></div>
                <div className={styles.speechBubbleContents} ref={bubbleContents}>
                    <h1 className={titleClass}>
                        {<TypedTitle title={title} paused={animationState === 'animating'} onComplete={onTypingComplete} />}
                    </h1>
                    {subtitle && <h2 className={subtitleClass}>{subtitle}</h2>}
                    {children && animationState === 'typing-done' && <div className={childrenClass}>{children}</div>}
                </div>
            </div>
        </div>
    );
}

/**
 * @param {object} props
 * @param {string[]} props.title
 * @param {boolean} [props.paused=true]
 * @param {() => void} [props.onComplete]
 */
export function TypedTitle({ title, paused = true, onComplete }) {
    const [textIndex, setTextIndex] = useState(0);

    const onTypingComplete = () => {
        setTextIndex((value) => (value += 1));

        if (textIndex >= title.length - 1) {
            // eslint-disable-next-line @typescript-eslint/no-unused-expressions
            onComplete && onComplete();
        }
    };

    return (
        <div className={styles.titleContainer}>
            {title.map((text, index) => (
                <Typed key={index} onComplete={onTypingComplete} text={text} paused={paused || textIndex < index} />
            ))}
        </div>
    );
}
