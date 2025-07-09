import { h } from 'preact';
import styles from './App.module.css';
import { useTypedTranslation } from '../types.js';

export function App() {
    const { t } = useTypedTranslation();
    return <main class={styles.main}>{t('helloWorld')}</main>;
}
