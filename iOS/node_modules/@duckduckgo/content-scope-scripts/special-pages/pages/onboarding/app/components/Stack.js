import { h } from 'preact';
import styles from './Stack.module.css';
import { useAutoAnimate } from '@formkit/auto-animate/preact';
import { useEnv } from '../../../../shared/components/EnvironmentProvider';

/**
 * Represents a stack component, use it for vertical spacing
 *
 * @param {Object} props
 * @param {import("preact").ComponentChild} [props.children] - The content to be rendered inside the stack component.
 * @param {string} [props.gap] - A CSS custom property to use as the gap
 * Defaults to `--sp-8` which is 2rem/32px
 * @param {boolean} [props.debug=false] - Specifies whether to enable debug mode for the stack component.
 * @param {boolean} [props.animate=false] - Should immediate children be animated into place?
 */
export function Stack({ children, gap = 'var(--sp-6)', animate = false, debug = false }) {
    const { isReducedMotion } = useEnv();
    const [parent] = useAutoAnimate({ duration: isReducedMotion ? 0 : 300 });
    return (
        <div class={styles.stack} ref={animate ? parent : null} data-debug={String(debug)} style={{ gap }}>
            {children}
        </div>
    );
}

Stack.gaps = {
    6: 'var(--sp-6)',
    4: 'var(--sp-4)',
    3: 'var(--sp-3)',
    0: 0,
};
