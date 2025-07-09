import { h } from 'preact';
import cn from 'classnames';
import styles from './Button.module.css';

/**
 *
 * @param {object} props
 * @param {import("preact").ComponentChild} props.children
 * @param {"mobile" | "desktop"} [props.formfactor]
 * @param {"standard" | "accent"} [props.variant]
 * @param {boolean} [props.icon]
 * @param {boolean} [props.fill]
 * @param {boolean} [props.highlight]
 * @param {import("preact").ComponentProps<"button">} [props.buttonProps]
 */
export function Button({
    children,
    formfactor = 'mobile',
    variant = 'standard',
    icon = false,
    fill = false,
    highlight = false,
    buttonProps = {},
}) {
    const classes = cn({
        [styles.button]: true,
        [styles.desktop]: formfactor === 'desktop',
        [styles.highlight]: highlight === true,
        [styles.accent]: variant === 'accent',
        [styles.fill]: fill === true,
        [styles.iconOnly]: icon === true,
    });
    return (
        <button class={classes} type="button" {...buttonProps}>
            {children}
        </button>
    );
}

/**
 * @param {object} props
 * @param {import("preact").ComponentChild} props.children
 * @param {"mobile" | "desktop"} [props.formfactor]
 * @param {boolean} [props.icon]
 * @param {boolean} [props.fill]
 * @param {boolean} [props.highlight]
 * @param {import("preact").ComponentProps<"a">} [props.anchorProps]
 */
export function ButtonLink({ children, formfactor = 'mobile', icon = false, fill = false, highlight = false, anchorProps = {} }) {
    const classes = cn({
        [styles.button]: true,
        [styles.desktop]: formfactor === 'desktop',
        [styles.highlight]: highlight === true,
        [styles.fill]: fill === true,
        [styles.iconOnly]: icon === true,
    });
    return (
        <a class={classes} type="button" {...anchorProps}>
            {children}
        </a>
    );
}

export function Icon({ src }) {
    return (
        <span class={styles.icon}>
            <img src={src} alt="" />
        </span>
    );
}

export function OpenInIcon() {
    return (
        <svg fill="none" viewBox="0 0 16 16" xmlns="http://www.w3.org/2000/svg" className={styles.svgIcon}>
            <path
                fill="currentColor"
                d="M7.361 1.013a.626.626 0 0 1 0 1.224l-.126.013H5A2.75 2.75 0 0 0 2.25 5v6A2.75 2.75 0 0 0 5 13.75h6A2.75 2.75 0 0 0 13.75 11V8.765a.625.625 0 0 1 1.25 0V11a4 4 0 0 1-4 4H5a4 4 0 0 1-4-4V5a4 4 0 0 1 4-4h2.235l.126.013Z"
            />
            <path
                fill="currentColor"
                d="M12.875 1C14.049 1 15 1.951 15 3.125v2.25a.625.625 0 1 1-1.25 0v-2.24L9.067 7.817a.626.626 0 0 1-.884-.884l4.682-4.683h-2.24a.625.625 0 1 1 0-1.25h2.25Z"
            />
        </svg>
    );
}
