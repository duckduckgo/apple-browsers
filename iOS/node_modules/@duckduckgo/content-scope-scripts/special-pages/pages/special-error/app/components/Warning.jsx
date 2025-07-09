import { h } from 'preact';
import classNames from 'classnames';
import { useTypedTranslation } from '../types';
import { useMessaging } from '../providers/MessagingProvider';
import { useErrorData } from '../providers/SpecialErrorProvider';
import { usePlatformName, useIsMobile } from '../providers/SettingsProvider';
import { useWarningHeading, useWarningContent } from '../hooks/ErrorStrings';
import { Text } from '../../../../shared/components/Text/Text';
import { Button } from '../../../../shared/components/Button/Button';

import styles from './Warning.module.css';

/**
 * @param {object} props
 * @param {import('preact').JSX.MouseEventHandler<EventTarget>} props.onClick
 */
export function AdvancedInfoButton({ onClick }) {
    const { t } = useTypedTranslation();
    const isMobile = useIsMobile();
    const buttonVariant = isMobile ? 'ghost' : 'standard';

    return (
        <Button variant={buttonVariant} className={classNames(styles.button, styles.advanced)} onClick={onClick}>
            {isMobile ? t('advancedButton') : t('advancedEllipsisButton')}
        </Button>
    );
}

export function LeaveSiteButton() {
    const { t } = useTypedTranslation();
    const { messaging } = useMessaging();
    const platformName = usePlatformName();

    /** @type {import('../../../../shared/components/Button/Button').ButtonProps['variant']} */
    let buttonVariant;
    switch (platformName) {
        case 'ios':
        case 'android':
            buttonVariant = 'primary';
            break;
        case 'windows':
            buttonVariant = 'accentBrand';
            break;
        default:
            buttonVariant = 'accent';
    }

    return (
        <Button variant={buttonVariant} className={classNames(styles.button, styles.leaveSite)} onClick={() => messaging?.leaveSite()}>
            {t('leaveSiteButton')}
        </Button>
    );
}

export function WarningHeading() {
    const heading = useWarningHeading();
    if (!heading) return null;

    const { kind } = useErrorData();
    const platformName = usePlatformName();
    const isMobile = useIsMobile();

    /** @type {'title-2'|'title-2-emphasis'|'custom-title-1'} */
    let textVariant;
    switch (platformName) {
        case 'ios':
        case 'android':
            textVariant = 'title-2';
            break;
        case 'windows':
            textVariant = 'custom-title-1';
            break;
        default:
            textVariant = 'title-2-emphasis';
    }

    return (
        <header className={classNames(styles.heading, styles[kind])}>
            <i className={styles.icon} aria-hidden="true" />
            <Text as="h1" variant={textVariant} strictSpacing={isMobile} className={styles.title}>
                {heading}
            </Text>
        </header>
    );
}

export function WarningContent() {
    const content = useWarningContent();
    if (!content.length) return null;

    return (
        <div className={styles.content}>
            {content.map((text) => (
                <Text as="p" variant="body">
                    {text}
                </Text>
            ))}
        </div>
    );
}

/**
 * @param {object} props
 * @param {boolean} props.advancedInfoVisible
 * @param {() => void} props.advancedButtonHandler
 */
export function Warning({ advancedInfoVisible, advancedButtonHandler }) {
    return (
        <section className={styles.container}>
            <WarningHeading />

            <WarningContent />

            <div className={styles.buttonContainer}>
                {!advancedInfoVisible && <AdvancedInfoButton onClick={() => advancedButtonHandler()} />}
                <LeaveSiteButton />
            </div>
        </section>
    );
}
