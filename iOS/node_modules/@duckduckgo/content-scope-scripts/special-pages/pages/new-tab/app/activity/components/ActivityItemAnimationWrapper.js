import { useContext, useEffect, useLayoutEffect, useRef } from 'preact/hooks';
import { ActivityBurningSignalContext } from '../../burning/BurnProvider.js';
import { useComputed } from '@preact/signals';
import cn from 'classnames';
import styles from './Activity.module.css';
import { lazy, Suspense } from 'preact/compat';
import { h } from 'preact';

// eslint-disable-next-line promise/prefer-await-to-then
const BurnAnimationLazy = lazy(() => import('../../burning/BurnAnimationLottieWeb.js').then((x) => x.BurnAnimation));

/**
 * A wrapper component that provides animation effects for activity items. It handles
 * animations for items entering and exiting, as well as animations for a "burning" state
 * based on the provided context signals.
 *
 * @param {Object} props
 * @param {import("preact").ComponentChild} props.children The child components or elements to be rendered inside the wrapper.
 * @param {string} props.url The unique URL associated with the activity item used for identifying its state in the context.
 */
export function ActivityItemAnimationWrapper({ children, url }) {
    const ref = useRef(/** @type {HTMLDivElement|null} */ (null));
    const { exiting, burning, showBurnAnimation, doneBurning } = useContext(ActivityBurningSignalContext);
    const isBurning = useComputed(() => burning.value.some((x) => x === url));
    const isExiting = useComputed(() => exiting.value.some((x) => x === url));

    useLayoutEffect(() => {
        let canceled = false;
        let sent = false;
        if (isBurning.value && ref.current) {
            const element = ref.current;
            element.style.height = element.scrollHeight + 'px';
        } else if (isExiting.value && ref.current) {
            const element = ref.current;
            const anim = element.animate([{ height: element.style.height }, { height: '0px' }], {
                duration: 200,
                iterations: 1,
                fill: 'both',
                easing: 'ease-in-out',
            });
            const handler = (_) => {
                if (canceled) return;
                if (sent) return;
                sent = true;
                anim.removeEventListener('finish', handler);
                window.dispatchEvent(
                    new CustomEvent('done-exiting', {
                        detail: {
                            url,
                            reason: 'animation completed',
                        },
                    }),
                );
            };
            anim.addEventListener('finish', handler, { once: true });
            document.addEventListener('visibilitychange', handler, { once: true });
            return () => {
                anim.removeEventListener('finish', handler);
                document.removeEventListener('visibilitychange', handler);
            };
        }
        return () => {
            canceled = true;
        };
    }, [isBurning.value, isExiting.value, url]);

    return (
        <div class={cn(styles.anim, isBurning.value && styles.burning)} ref={ref}>
            {!isExiting.value && children}
            {!isExiting.value && isBurning.value && showBurnAnimation && (
                <Suspense fallback={null}>
                    <BurnAnimationLazy url={url} doneBurning={doneBurning} />
                </Suspense>
            )}
            {!isExiting.value && isBurning.value && !showBurnAnimation && <NullBurner url={url} doneBurning={doneBurning} />}
        </div>
    );
}

function NullBurner({ url, doneBurning }) {
    useEffect(() => doneBurning(url), [url]);
    return null;
}
