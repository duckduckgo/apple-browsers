// eslint-disable-next-line @typescript-eslint/no-unused-vars
import { h, Fragment } from 'preact';
import { ListItem } from '../components/ListItem';
import { BounceIn, Check, FadeIn, SlideUp } from '../components/Icons';
import { List } from '../components/List';
import { Stack } from '../components/Stack';
import { Button, ButtonBar } from '../components/Buttons';
import { useGlobalDispatch, useGlobalState } from '../global';
import { useRollin } from '../hooks/useRollin';
import { Switch } from '../../../../shared/components/Switch/Switch.js';
import { useTypedTranslation } from '../types';
import { RiveAnimation } from '../components/RiveAnimation';
import { useEnv } from '../../../../shared/components/EnvironmentProvider';
import { usePlatformName } from '../components/SettingsProvider.js';

/**
 * @param {object} props
 * @param {(args: any) => void} props.onNextPage
 * @param {typeof import('../data').settingsRowItems} props.data
 * @param {typeof import('../data').stepMeta} props.metaData
 * @param {string} [props.subtitle] - optional subtitle
 */
export function SettingsStep({ onNextPage, data, metaData, subtitle }) {
    const { injectName } = useEnv();
    const { state } = useRollin([300]);
    const { t } = useTypedTranslation();

    const dispatch = useGlobalDispatch();
    const appState = useGlobalState();
    if (appState.step.kind !== 'settings') throw new Error('unreachable, for TS benefit');

    const { step, status } = appState;
    const pendingId = status.kind === 'executing' && status.action.kind === 'update-system-value' && status.action.id;
    const complete = appState.activeRow >= step.rows.length;

    /** @type {import("preact").ComponentProps<SettingListItem>['item'][]} */
    const rows = step.rows.map((rowId, index) => {
        return {
            visible: appState.activeRow >= index,
            current: appState.activeRow === index,
            systemValue: appState.values[rowId] || null,
            uiValue: appState.UIValues[rowId],
            pending: pendingId === rowId,
            id: rowId,
            data: data[rowId](t, injectName),
            meta: metaData[step.id]?.rows?.[rowId],
        };
    });

    return (
        <Stack>
            <Stack animate>
                {appState.status.kind === 'idle' && appState.status.error && <p>{appState.status.error}</p>}
                {state.current > 0 && (
                    <Stack gap={Stack.gaps['4']}>
                        {subtitle && <h2>{subtitle}</h2>}
                        <List>
                            {rows
                                .filter((item) => item.visible)
                                .map((item, index) => {
                                    return <SettingListItem key={item.id} dispatch={dispatch} item={item} index={index} />;
                                })}
                        </List>
                    </Stack>
                )}
            </Stack>
            {complete && (
                <SlideUp delay={'double'}>
                    <ButtonBar>
                        <Button onClick={onNextPage} size={'large'}>
                            {t('nextButton')}
                        </Button>
                    </ButtonBar>
                </SlideUp>
            )}
        </Stack>
    );
}

/**
 * Renders a setting list item with optional interactive components.
 *
 * @param {Object} props - The props object.
 * @param {{
 *    visible: boolean;
 *    current: boolean;
 *    pending: boolean;
 *    id: import('../types').SystemValueId;
 *    systemValue: import('../types').SystemValue | null;
 *    data: import('../data').RowData;
 *    uiValue: import('../types').UIValue;
 *    meta: Record<string, any>;
 * }} props.item - The item object containing the row data.
 * @param {ReturnType<typeof useGlobalDispatch>} props.dispatch - The function to dispatch actions.
 * @param {number} props.index
 */
export function SettingListItem({ index, item, dispatch }) {
    const data = item.data;
    const { t } = useTypedTranslation();
    const platformName = /** @type {'macos'|'windows'} */ (usePlatformName());
    const { isDarkMode } = useEnv();

    const accept = () => {
        dispatch({
            kind: 'update-system-value',
            id: data.id,
            payload: { enabled: true },
            current: item.current,
        });
    };

    const deny = () => {
        dispatch({
            kind: 'update-system-value',
            id: data.id,
            payload: { enabled: false },
            current: item.current,
        });
    };

    const inline = (() => {
        if (item.uiValue === 'idle') return null;
        if (!item.systemValue) return null;
        const enabled = item.systemValue.enabled;

        // was this item previously skipped?
        if (item.uiValue === 'skipped') {
            // is the item something that can only be enabled once?
            if (enabled && item.data.kind === 'one-time') {
                return (
                    <BounceIn delay={'normal'}>
                        <Check />
                    </BounceIn>
                );
            }
            // otherwise, allow it to be toggled
            return (
                <FadeIn>
                    {item.data.kind === 'one-time' && (
                        <Button disabled={item.pending} variant={'secondary'} onClick={accept}>
                            {item.data.acceptText}
                        </Button>
                    )}
                    {item.data.kind === 'toggle' && (
                        <Switch
                            ariaLabel={item.data.acceptText}
                            pending={item.pending}
                            checked={enabled}
                            onChecked={accept}
                            onUnchecked={deny}
                            platformName={platformName}
                            theme={isDarkMode ? 'dark' : 'light'}
                        />
                    )}
                </FadeIn>
            );
        }

        // otherwise, it must have been accepted
        if (item.uiValue === 'accepted') {
            return (
                <BounceIn delay={'normal'}>
                    <Check />
                </BounceIn>
            );
        }

        throw new Error('unreachable');
    })();

    const display = (() => {
        if (item.meta) {
            return item.meta;
        }
        return { kind: 'button-bar' };
    })();

    return (
        <ListItem
            key={data.id}
            icon={data.icon}
            title={data.title}
            secondaryText={item.current && data.secondaryText}
            inline={inline}
            animate={true}
            index={index}
        >
            {item.current && display.kind === 'button-bar' && (
                <ListItem.Indent>
                    <ButtonBar>
                        <Button disabled={item.pending} variant={'secondary'} onClick={deny}>
                            {t('skipButton')}
                        </Button>
                        <Button disabled={item.pending} variant={'secondary'} onClick={accept}>
                            {item.data.acceptText}
                        </Button>
                    </ButtonBar>
                </ListItem.Indent>
            )}
            {item.current && display.kind === 'animation' && (
                <Stack gap="var(--sp-3)">
                    <RiveAnimation animation={display.path} state={'before'} isDarkMode={isDarkMode} stateMachine={'State Machine 1'} />
                    <ButtonBar>
                        <Button disabled={item.pending} variant={'secondary'} onClick={deny}>
                            {t('skipButton')}
                        </Button>
                        <Button disabled={item.pending} variant={'secondary'} onClick={accept}>
                            {item.data.acceptText}
                        </Button>
                    </ButtonBar>
                </Stack>
            )}
        </ListItem>
    );
}
