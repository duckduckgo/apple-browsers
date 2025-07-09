import { h } from 'preact';
import styles from './Background.module.css';
import cn from 'classnames';

export function Background() {
    return (
        <div class={styles.background}>
            <div class={cn(styles.foreground, styles.animated, styles.clouds)} />
            <div class={cn(styles.foreground, styles.animated, styles.mountains)} />
            <div class={cn(styles.foreground, styles.stars)} />
        </div>
    );
}
