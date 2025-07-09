import { h } from 'preact';
import cn from 'classnames';
import styles from './PlayerContainer.module.css';

/**
 * Creates a container for player elements.
 *
 * @param {Object} props - The properties for the PlayerContainer component.
 * @param {import("preact").ComponentChild} props.children - The child elements to render inside the container.
 * @param {boolean} [props.inset] - whether the UI is all inset
 */
export function PlayerContainer({ children, inset }) {
    return (
        <div
            class={cn(styles.container, {
                [styles.inset]: inset,
            })}
        >
            {children}
        </div>
    );
}

/**
 * Creates a container for player elements.
 *
 * @param {Object} props - The properties for the PlayerContainer component.
 * @param {import("preact").ComponentChild} props.children - The child elements to render inside the container.
 * @param {boolean} [props.inset] - whether the UI is all inset
 */
export function PlayerInternal({ children, inset }) {
    return <div class={cn(styles.internals, { [styles.insetInternals]: inset })}>{children}</div>;
}
