import { h } from 'preact';
import lottie from 'lottie-web';
import { useContext, useEffect, useRef } from 'preact/hooks';
import { ActivityBurningSignalContext } from './BurnProvider.js';

/**
 * BurnAnimation is a React component that renders a Lottie animation and dispatches custom events when the animation stops or the component unmounts.
 *
 * @param {Object} props The properties object.
 * @param {string} props.url The URL associated with the animation, used to identify or provide additional context in the dispatched events.
 * @param {(url: string) => void} props.doneBurning
 */
export function BurnAnimation({ url, doneBurning }) {
    const ref = useRef(/** @type {Lottie} */ null);
    const json = useContext(ActivityBurningSignalContext);
    useEffect(() => {
        if (!ref.current) return;
        let finished = false;
        let timer = null;

        const publish = (_reason) => {
            if (finished) return;
            doneBurning(url);
            finished = true;
            clearTimeout(timer);
        };

        timer = setTimeout(() => {
            publish('timeout occurred');
        }, 1200);

        const animationHandler = () => publish('timeout occurred');
        const hasJson = json.animation.value.state === 'ready' && json.animation.value.data;

        /** @type {import('lottie-web').AnimationItem | null} */
        let animation = lottie.loadAnimation({
            container: ref.current,
            renderer: 'svg',
            loop: false,
            autoplay: true,
            animationData: hasJson || undefined,
            path: hasJson === undefined ? 'burn.json' : undefined,
        });

        animation.addEventListener('complete', animationHandler);

        return () => {
            clearTimeout(timer);
            // animation?.removeEventListener('complete', animationHandler);
            animation = null;

            if (!finished) {
                publish('unmount occurred');
            }
        };
    }, [url, json, doneBurning]);
    return <div ref={ref} data-lottie-player></div>;
}
