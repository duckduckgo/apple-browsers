import { useAutoAnimate } from '@formkit/auto-animate/preact';
import { h } from 'preact';
import { useEnv } from '../../../../shared/components/EnvironmentProvider';

/**
 * Apply auto-animate to arbitrary elements
 * @param {Object} props - The properties of the component.
 * @param {import("preact").ComponentChild} props.children - The child elements to be animated.
 */
export function Animate(props) {
    const { isReducedMotion } = useEnv();
    const [parent] = useAutoAnimate(isReducedMotion ? { duration: 0 } : undefined);
    return <div ref={parent}>{props.children}</div>;
}
