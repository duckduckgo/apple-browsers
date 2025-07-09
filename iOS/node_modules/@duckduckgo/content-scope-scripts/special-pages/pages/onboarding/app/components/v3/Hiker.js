import { h } from 'preact';

import styles from './Hiker.module.css';

export function Hiker() {
    return <img className={styles.hiker} src="assets/img/hiker.svg" alt="Image of hiker" />;
}
