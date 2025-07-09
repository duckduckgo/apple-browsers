import { h } from 'preact';
import styles from './Icons.module.css';

/**
 * BounceIn animates the given children by applying bounce-in animation effect using CSS.
 *
 * @param {Object} props - The props object containing children.
 * @param {import("preact").ComponentChild} props.children - The children nodes to apply bounce-in animation effect.
 * @param {'none' | 'normal' | 'double'} [props.delay="none"] - The children nodes to apply bounce-in animation effect.
 */
export function BounceIn({ children, delay = 'none' }) {
    return (
        <div className={styles.bounceIn} data-delay={delay}>
            {children}
        </div>
    );
}

/**
 * A simple fade-in wrapper
 *
 * @param {Object} props - The props object containing children.
 * @param {import("preact").ComponentChild} props.children - The children nodes to apply bounce-in animation effect.
 * @param {'none' | 'normal' | 'double'} [props.delay="none"] - The children nodes to apply bounce-in animation effect.
 */
export function FadeIn({ children, delay = 'none' }) {
    return (
        <div className={styles.fadeIn} data-delay={delay}>
            {children}
        </div>
    );
}

/**
 * SlideIn animates the given children by applying bounce-in animation effect using CSS.
 *
 * @param {Object} props - The props object containing children.
 * @param {import("preact").ComponentChild} props.children - The children nodes to apply bounce-in animation effect.
 * @param {'none' | 'normal' | 'double'} [props.delay="none"] - The children nodes to apply bounce-in animation effect.
 */
export function SlideIn({ children, delay = 'none' }) {
    return (
        <div className={styles.slideIn} data-delay={delay}>
            {children}
        </div>
    );
}

/**
 * SlideIn animates the given children by applying bounce-in animation effect using CSS.
 *
 * @param {Object} props - The props object containing children.
 * @param {import("preact").ComponentChild} props.children - The children nodes to apply bounce-in animation effect.
 * @param {'none' | 'normal' | 'double'} [props.delay="none"] - The children nodes to apply bounce-in animation effect.
 */
export function SlideUp({ children, delay = 'none' }) {
    return (
        <div className={styles.slideUp} data-delay={delay}>
            {children}
        </div>
    );
}

export function Check() {
    return (
        <svg width="16" height="16" viewBox="0 0 16 16" fill="none" aria-labelledby="svgTitle svgDesc" role="img">
            <title id="svgCheckTitle">Completed Action</title>
            <desc id="svgCheckDesc">Green check mark indicating action completed successfully.</desc>
            <g clip-path="url(#clip0_3030_17975)">
                <path
                    fill-rule="evenodd"
                    clip-rule="evenodd"
                    d="M8 16C12.4183 16 16 12.4183 16 8C16 3.58172 12.4183 0 8 0C3.58172 0 0 3.58172 0 8C0 12.4183 3.58172 16 8 16Z"
                    fill="#21C000"
                />
                <path
                    fill-rule="evenodd"
                    clip-rule="evenodd"
                    d="M11.6668 5.28423C11.924 5.51439 11.946 5.90951 11.7158 6.16675L7.46579 10.9168C7.34402 11.0529 7.1688 11.1289 6.98622 11.1249C6.80363 11.1208 6.63194 11.0371 6.5163 10.8958L4.2663 8.14578C4.04772 7.87863 4.08709 7.48486 4.35425 7.26628C4.6214 7.0477 5.01516 7.08708 5.23374 7.35423L7.02125 9.53896L10.7842 5.33326C11.0144 5.07602 11.4095 5.05407 11.6668 5.28423Z"
                    fill="white"
                />
            </g>
            <defs>
                <clipPath id="clip0_3030_17975">
                    <rect width="16" height="16" fill="white" />
                </clipPath>
            </defs>
        </svg>
    );
}

export function Play() {
    return (
        <svg width="12" height="12" viewBox="0 0 12 12" fill="none" xmlns="http://www.w3.org/2000/svg">
            <path
                d="M1 10.2768V1.72318C1 0.955357 1.82948 0.47399 2.49614 0.854937L9.98057 5.13176C10.6524 5.51565 10.6524 6.48435 9.98057 6.86824L2.49614 11.1451C1.82948 11.526 1 11.0446 1 10.2768Z"
                fill="currentColor"
            />
        </svg>
    );
}

/**
 *
 * @param {object} props
 * @param {'backward'|'forward'} [props.direction='backward'] - Direction to which the icon is turning
 */
export function Replay({ direction = 'backward' }) {
    return (
        <svg
            width="12"
            height="12"
            viewBox="0 0 12 12"
            fill="none"
            xmlns="http://www.w3.org/2000/svg"
            style={direction === 'forward' ? { transform: 'scale(-1,1)' } : {}}
        >
            <g clip-path="url(#clip0_10021_2837)">
                <path
                    d="M7.11485 1.37611C6.05231 1.12541 4.93573 1.25089 3.95534 1.73116C3.06198 2.1688 2.33208 2.87636 1.86665 3.75003H3.9837C4.32888 3.75003 4.6087 4.02985 4.6087 4.37503C4.6087 4.7202 4.32888 5.00003 3.9837 5.00003H0.625013C0.279836 5.00003 1.33514e-05 4.7202 1.33514e-05 4.37503V0.651184C1.33514e-05 0.306006 0.279836 0.0261841 0.625013 0.0261841C0.970191 0.0261841 1.25001 0.306006 1.25001 0.651184V2.39582C1.81304 1.64241 2.54999 1.02768 3.40543 0.608623C4.64552 0.00112504 6.05789 -0.157593 7.40189 0.159513C8.74589 0.476619 9.93836 1.24993 10.7761 2.34768C11.6139 3.44543 12.0451 4.7997 11.9963 6.17974C11.9475 7.55977 11.4216 8.88019 10.5084 9.91601C9.59521 10.9518 8.35109 11.639 6.98804 11.8603C5.625 12.0817 4.22737 11.8236 3.03329 11.13C1.83922 10.4364 0.922573 9.35022 0.43955 8.05655C0.318811 7.73318 0.483079 7.37316 0.806451 7.25242C1.12982 7.13168 1.48985 7.29595 1.61059 7.61932C1.99245 8.64206 2.71713 9.50076 3.66114 10.0491C4.60514 10.5974 5.71008 10.8015 6.78767 10.6265C7.86526 10.4515 8.84883 9.90826 9.5708 9.08936C10.2928 8.27047 10.7085 7.22658 10.747 6.13555C10.7856 5.04453 10.4447 3.97387 9.78243 3.10602C9.12012 2.23816 8.17738 1.6268 7.11485 1.37611Z"
                    fill="currentColor"
                    fill-opacity="0.84"
                />
            </g>
            <defs>
                <clipPath id="clip0_10021_2837">
                    <rect width="12" height="12" fill="white" />
                </clipPath>
            </defs>
        </svg>
    );
}

export function Launch() {
    return (
        <svg width="17" height="16" viewBox="0 0 17 16" fill="none" xmlns="http://www.w3.org/2000/svg">
            <g clip-path="url(#clip0_3098_23365)">
                <path
                    fill-rule="evenodd"
                    clip-rule="evenodd"
                    d="M12.0465 7.31875C11.269 8.09623 10.0085 8.09623 9.23102 7.31875C8.45354 6.54128 8.45354 5.28074 9.23102 4.50327C10.0085 3.7258 11.269 3.7258 12.0465 4.50327C12.824 5.28074 12.824 6.54128 12.0465 7.31875ZM11.1626 6.43487C10.8733 6.72419 10.4042 6.72419 10.1149 6.43487C9.82558 6.14555 9.82558 5.67647 10.1149 5.38715C10.4042 5.09783 10.8733 5.09783 11.1626 5.38715C11.4519 5.67647 11.4519 6.14555 11.1626 6.43487Z"
                    fill="white"
                    fill-opacity="0.84"
                />
                <path
                    fill-rule="evenodd"
                    clip-rule="evenodd"
                    d="M15.0163 0.357982C10.4268 0.792444 7.29295 2.76331 5.19328 5.43188C5.03761 5.41854 4.88167 5.40999 4.72564 5.40608C3.54981 5.37661 2.36922 5.61098 1.26629 6.0488C0.653083 6.29222 0.543501 7.07682 1.01002 7.54334L2.92009 9.45341C2.86071 9.6032 2.80326 9.75371 2.74768 9.90485C2.61756 10.2587 2.71271 10.6538 2.97932 10.9204L5.62864 13.5698C5.89525 13.8364 6.29037 13.9315 6.64424 13.8014C6.79555 13.7458 6.94624 13.6882 7.0962 13.6288L9.0054 15.538C9.47191 16.0045 10.2565 15.8949 10.4999 15.2817C10.9378 14.1788 11.1721 12.9982 11.1427 11.8224C11.1388 11.6668 11.1302 11.5112 11.117 11.356C13.7857 9.25633 15.7566 6.1224 16.1911 1.53282C16.2296 1.12649 16.256 0.708745 16.2698 0.279297C15.8403 0.293094 15.4226 0.319516 15.0163 0.357982ZM3.9867 10.1601L6.38903 12.5624C8.6807 11.6928 10.7461 10.3775 12.2764 8.46444C13.2183 7.28687 13.9808 5.85389 14.4628 4.10497L12.4441 2.08628C10.6952 2.56825 9.26222 3.33082 8.08465 4.27272C6.17156 5.80296 4.85624 7.86839 3.9867 10.1601ZM2.25561 7.02117C2.84462 6.83216 3.44604 6.71284 4.04467 6.67074L3.29585 8.06141L2.25561 7.02117ZM9.52757 14.2924C9.71658 13.7034 9.8359 13.102 9.878 12.5033L8.48733 13.2522L9.52757 14.2924ZM14.7828 2.65724L13.8919 1.76626C14.2259 1.7093 14.5703 1.6616 14.9253 1.62375C14.8875 1.97878 14.8398 2.32317 14.7828 2.65724Z"
                    fill="white"
                    fill-opacity="0.84"
                />
                <path
                    d="M4.98318 13.664C5.19417 13.9372 5.14374 14.3297 4.87055 14.5407C3.96675 15.2387 2.81266 15.6173 1.50788 15.7098L0.78927 15.7608L0.840231 15.0422C0.932761 13.7374 1.31133 12.5833 2.00934 11.6795C2.22032 11.4063 2.61283 11.3559 2.88602 11.5669C3.15921 11.7779 3.20963 12.1704 2.99865 12.4436C2.60779 12.9497 2.32977 13.5927 2.18426 14.3658C2.95736 14.2203 3.60041 13.9423 4.1065 13.5514C4.37969 13.3404 4.77219 13.3909 4.98318 13.664Z"
                    fill="white"
                    fill-opacity="0.84"
                />
            </g>
            <defs>
                <clipPath id="clip0_3098_23365">
                    <rect width="16" height="16" fill="white" transform="translate(0.5)" />
                </clipPath>
            </defs>
        </svg>
    );
}
