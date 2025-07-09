import { h } from 'preact';
import { useTypedTranslation } from '../types';

export function ErrorFallback() {
    const { t } = useTypedTranslation();

    return <h1>{t('somethingWentWrong')}</h1>;
}
