import { h } from 'preact';
import { Stack } from '../components/Stack';
import { Launch, SlideUp } from '../components/Icons';
import { Button, ButtonBar } from '../components/Buttons';
import { noneSettingsRowItems, settingsRowItems } from '../data';
// eslint-disable-next-line @typescript-eslint/no-unused-vars
import { ListItemPlain, availableIcons } from '../components/ListItem';
import { SummaryList } from '../components/List';
import { Trans } from '../../../../shared/components/TranslationsProvider';
import { useTypedTranslation } from '../types';

/**
 * Renders a summary component
 *
 * @param {Object} props - The component props
 * @param {import('../types').GlobalState['values']} props.values - The component props
 * @param {() => void} props.onDismiss - The function to call when dismissing
 * @param {() => void} props.onSettings - The function to call when opening settings
 */
export function Summary({ values, onDismiss, onSettings }) {
    const { t } = useTypedTranslation();

    // list of features that are 'on by default', so we always show them
    /** @type {{icon: availableIcons[number]; summary: string}[]} */
    const items = Object.values(noneSettingsRowItems).map((fn) => {
        const subject = fn(t);
        return {
            icon: subject.icon,
            summary: subject.summary,
        };
    });

    // list of settings that were enabled by the user during onboarding
    /** @type {{icon: availableIcons[number]; summary: string}[]} */
    const enabledSettingsItems = Object.keys(values)
        // only include items that were 'enabled' + have corresponding data
        .filter((key) => values[key].enabled === true && Object.hasOwnProperty.call(settingsRowItems, key))
        // for each enabled item, select the corresponding data
        .map((key) => {
            const subject = settingsRowItems[key](t);
            return {
                icon: subject.icon,
                summary: subject.summary,
            };
        });

    function onSettingsHandler(e) {
        e.preventDefault();
        onSettings();
    }

    return (
        <Stack gap={Stack.gaps['3'] /* 12px */}>
            <SummaryList>
                {items.concat(enabledSettingsItems).map((item) => {
                    return <ListItemPlain key={item.summary} icon={item.icon} title={item.summary} />;
                })}
            </SummaryList>
            <SlideUp>
                <ButtonBar style={{ marginTop: '19px' /* this matches the designs perfectly */ }}>
                    <Button onClick={onDismiss} size={'xl'}>
                        {t('startBrowsing')}
                        <Launch />
                    </Button>
                </ButtonBar>
            </SlideUp>
            <div style={{ marginTop: '50px' /* this matches the designs perfectly */ }}>
                <Trans
                    str={t('youCanChangeYourChoicesAnyTimeInSettings')}
                    values={{
                        a: {
                            href: 'about:preferences',
                            click: onSettingsHandler,
                        },
                    }}
                />
            </div>
        </Stack>
    );
}
