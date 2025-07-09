import { h } from 'preact';
import styles from './Background.module.css';
import cn from 'classnames';

export function Background() {
    return (
        <div className={styles.background}>
            <div className={cn(styles.foreground, styles.layer1)} />
            <div className={cn(styles.foreground, styles.layer2)} />
            <div className={cn(styles.foreground, styles.layer3)} />
        </div>
    );
}
