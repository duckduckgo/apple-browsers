import { h } from 'preact';
import { useRef } from 'preact/hooks';
import { useTypedTranslation } from '../types';
import { Text } from '../../../../shared/components/Text/Text';
import { useMessaging } from '../providers/MessagingProvider';
import { useAdvancedInfoHeading, useAdvancedInfoContent } from '../hooks/ErrorStrings';

import styles from './AdvancedInfo.module.css';

function useScrollTarget() {
    /** @type {import("preact/hooks").MutableRef<HTMLAnchorElement|null>} */
    const linkRef = useRef(null);
    return {
        ref: linkRef,
        trigger: () => {
            linkRef.current?.scrollIntoView({ behavior: 'smooth' });
        },
    };
}

/**
 * @param {object} props
 * @param {import("preact/hooks").MutableRef<HTMLAnchorElement|null>} [props.elemRef]
 */
export function VisitSiteLink({ elemRef }) {
    const { t } = useTypedTranslation();
    const { messaging } = useMessaging();
    return (
        <a className={styles.visitSite} onClick={() => messaging?.visitSite()} ref={elemRef}>
            {t('visitSiteButton')}
        </a>
    );
}

export function AdvancedInfoHeading() {
    const heading = useAdvancedInfoHeading();
    if (!heading) return null;

    return (
        <header className={styles.heading}>
            <Text as="h2" variant="body">
                {heading}
            </Text>
        </header>
    );
}

export function AdvancedInfoContent() {
    const content = useAdvancedInfoContent();
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

export function AdvancedInfo() {
    const { ref, trigger } = useScrollTarget();

    return (
        <div className={styles.wrapper}>
            <div className={styles.animationContainer} onAnimationEnd={trigger}>
                <div className={styles.container}>
                    <AdvancedInfoHeading />

                    <AdvancedInfoContent />

                    <VisitSiteLink elemRef={ref} />
                </div>
            </div>
        </div>
    );
}
