import styles from './components/App.module.css';
import { Stack } from './components/Stack';
import { Header } from './components/Header';
import { Progress, SingleLineProgress } from './components/Progress';
import { ListItem } from './components/ListItem';
import { BounceIn, Check, Launch, Replay } from './components/Icons';
import { List } from './components/List';
import { Button, ButtonBar } from './components/Buttons';
import { ElasticButton } from './components/v3/ElasticButton';
import classNames from 'classnames';
import { h } from 'preact';
import { Background } from './components/Background';
import { settingsRowItems } from './data';
import { Summary } from './pages/Summary';
import { Switch } from '../../../shared/components/Switch/Switch.js';
import { Typed } from './components/Typed';
import { CleanBrowsing } from './pages/CleanBrowsing';
import { useTypedTranslation } from './types';
import { ComparisonTable } from './components/v3/ComparisonTable';
import { Heading } from './components/v3/Heading';
import { Hiker } from './components/v3/Hiker';

function noop(name) {
    return () => {
        console.log('clicked ' + name);
    };
}

export function Components() {
    const { t } = useTypedTranslation();
    return (
        <main className={styles.main}>
            <Background />
            <div class={styles.container}>
                <Stack gap="var(--sp-8)">
                    <p>
                        <a href="?env=app">Onboarding Flow</a>
                    </p>
                    <Header>
                        <Typed text={t('welcome_title')} />
                    </Header>
                    <Header>
                        <Typed text={t('getStarted_title', { newline: '\n' })} />
                    </Header>
                    <Header>
                        <Typed text={t('privateByDefault_title', { newline: '\n' })} />
                    </Header>
                    <Header>
                        <Typed text={t('cleanerBrowsing_title', { newline: '\n' })} />
                    </Header>
                    <Header>
                        <Typed text={t('systemSettings_title')} />
                    </Header>
                    <Header>
                        <Typed text={t('customize_title')} />
                    </Header>
                    <Header>
                        <Typed text={t('summary_title')} />
                    </Header>
                    <Progress current={1} total={4} />
                    <div>
                        <CleanBrowsing onNextPage={console.log} />
                    </div>
                    <div>
                        <p>On Light</p>
                        <AllSwitches theme={'light'} />
                    </div>
                    <div>
                        <p>On Dark</p>
                        <div style="background: #333; padding: 1rem;">
                            <AllSwitches theme={'dark'} />
                        </div>
                    </div>
                    <ButtonBar>
                        <Button size="large">L Button</Button>
                        <Button size="large" variant={'secondary'}>
                            L Button
                        </Button>
                    </ButtonBar>
                    <ButtonBar>
                        <Button size="xl">XL Button</Button>
                        <Button size="xl">
                            XL Button + <Launch />
                        </Button>
                    </ButtonBar>
                    <ListItem
                        icon={'search.png'}
                        title={'Private Search'}
                        secondaryText={"We don't track you. Ever."}
                        inline={
                            <BounceIn>
                                <Check />
                            </BounceIn>
                        }
                    />
                    <ListItem
                        icon={'shield.png'}
                        title={'Advanced Tracking Protection'}
                        secondaryText={'We block most trackers before they even load.'}
                    />
                    <ListItem
                        icon={'cookie.png'}
                        title={'Automatic Cookie Pop-Up Blocking'}
                        secondaryText={'We deny optional cookies for you & hide pop-ups.'}
                    />
                    <ListItem
                        icon={'switch.png'}
                        title={'Switch your default browser'}
                        secondaryText={'Always browse privately by default.'}
                    />
                    <ListItem
                        icon={'bookmarks.png'}
                        title={'Put your bookmarks in easy reach'}
                        secondaryText={'Show a bookmarks bar with your favorite bookmarks.'}
                    />
                    <ListItem
                        icon={'session-restore.png'}
                        title={'Pick up where you left off'}
                        secondaryText={'Always restart with all windows from your last session.'}
                    />
                    <ListItem
                        icon={'home.png'}
                        title={'Add a shortcut to your homepage'}
                        secondaryText={'Show a home button in your toolbar'}
                    />
                    <ListItem
                        icon={'shield.png'}
                        title={'Advanced Tracking Protection'}
                        secondaryText={'We block most trackers before they even load.'}
                    />
                    <ListItem
                        icon={'import.png'}
                        title={'Bring your stuff'}
                        secondaryText={'Import bookmarks, favorites, and passwords.'}
                    />

                    <div style={{ width: '480px' }}>
                        <List>
                            <ListItem
                                icon={'search.png'}
                                title={'Private Search'}
                                secondaryText={"We don't track you. Ever."}
                                inline={<Check />}
                            />
                            <ListItem
                                icon={'shield.png'}
                                title={'Advanced Tracking Protection'}
                                secondaryText={'We block most trackers before they even load.'}
                                inline={<Check />}
                            />
                            <ListItem
                                icon={'cookie.png'}
                                title={'Automatic Cookie Pop-Up Blocking'}
                                secondaryText={'We deny optional cookies for you & hide pop-ups.'}
                                inline={<Check />}
                            />
                        </List>
                    </div>

                    <div style={{ width: '480px' }}>
                        <List>
                            <ListItem
                                icon={'dock.png'}
                                title={'Keep DuckDuckGo in your Dock'}
                                secondaryText={'Get to DuckDuckGo faster'}
                                inline={<Check />}
                            ></ListItem>
                            <ListItem
                                icon={'import.png'}
                                title={'Bring your stuff'}
                                secondaryText={'Import bookmarks, favorites, and passwords.'}
                            >
                                <ListItem.Indent>
                                    <ButtonBar>
                                        <Button variant={'secondary'}>Skip</Button>
                                        <Button variant={'secondary'}>Import</Button>
                                    </ButtonBar>
                                </ListItem.Indent>
                            </ListItem>
                        </List>
                    </div>

                    <div style={{ width: '480px' }}>
                        <Stack>
                            <List>
                                {Object.keys(settingsRowItems).map((key) => {
                                    return (
                                        <ListItem
                                            icon={settingsRowItems[key](t).icon}
                                            title={settingsRowItems[key](t).title}
                                            secondaryText={settingsRowItems[key](t).secondaryText}
                                        />
                                    );
                                })}
                            </List>
                        </Stack>
                    </div>
                    <div style={{ width: '480px' }}>
                        <Stack>
                            <List>
                                <ListItem icon={'browsing.png'} title={'While browsing the web'} inline={<Check />} />
                                <ListItem icon={'duckplayer.png'} title={'While watching YouTube'} inline={<Check />} />
                            </List>
                            <ButtonBar>
                                <Button onClick={noop('next page')} size={'large'}>
                                    Next
                                </Button>
                            </ButtonBar>
                        </Stack>
                    </div>
                    <Summary
                        onDismiss={noop('onDismiss')}
                        onSettings={noop('onSettings')}
                        values={{
                            dock: { enabled: true },
                            'session-restore': { enabled: true },
                        }}
                    />

                    <h2 style={{ fontSize: '24px', fontWeight: 'bold' }}>V3 - Highlights</h2>

                    <Heading title={'Welcome to DuckDuckGo!'} />
                    <Heading title={'Welcome to DuckDuckGo!'} subtitle={"Let's get you set up..."} />
                    <Heading title={'Welcome to DuckDuckGo!'} subtitle={"Let's get you set up..."}>
                        <ElasticButton text={'Next'} elastic={true} />
                    </Heading>

                    <Heading title={'Welcome to DuckDuckGo!'} speechBubble={true} />
                    <Heading title={'Welcome to DuckDuckGo!'} subtitle={"Let's get you set up..."} speechBubble={true} />
                    <Heading title={'Welcome to DuckDuckGo!'} speechBubble={true}>
                        <ElasticButton text={'Next'} elastic={true} />
                    </Heading>

                    <SingleLineProgress current={2} total={5} />

                    <ComparisonTable />

                    <ButtonBar>
                        <ElasticButton variant={'secondary'} text={'Skip'} elastic={false} />
                        <ElasticButton variant={'secondary'} text={'Replay'} startIcon={<Replay />} elastic={false} />
                        <ElasticButton variant={'secondary'} text={'Replay'} endIcon={<Replay direction={'forward'} />} elastic={false} />
                    </ButtonBar>

                    <ButtonBar>
                        <ElasticButton text={'Next'} elastic={true} />
                        <ElasticButton text={'Start Browsing'} startIcon={<Launch />} elastic={true} />
                        <ElasticButton text={'Start Browsing'} endIcon={<Launch />} elastic={true} />
                    </ButtonBar>

                    <div style={{ position: 'relative', overflow: 'hidden', width: '400px', height: '400px' }}>
                        <Hiker />
                    </div>
                </Stack>
                <div style={{ height: '100px' }} />
            </div>
            <div className={classNames(styles.foreground, styles.layer1)} />
            <div className={classNames(styles.foreground, styles.layer2)} />
            <div className={classNames(styles.foreground, styles.layer3)} />
        </main>
    );
}

/**
 * @param {object} props
 * @param {'light' | 'dark'} props.theme
 */
function AllSwitches({ theme = 'light' }) {
    return (
        <ButtonBar>
            <Switch
                pending={false}
                ariaLabel={'op'}
                checked={true}
                onChecked={noop('onChecked')}
                onUnchecked={noop('onUnchecked')}
                platformName={'macos'}
                theme={theme}
            />
            <Switch
                pending={false}
                ariaLabel={'op'}
                checked={false}
                onChecked={noop('onChecked')}
                onUnchecked={noop('onUnchecked')}
                platformName={'macos'}
                theme={theme}
            />
            <Switch
                pending={false}
                ariaLabel={'op'}
                platformName={'windows'}
                checked={true}
                onChecked={noop('onChecked')}
                onUnchecked={noop('onUnchecked')}
                theme={theme}
            />
            <Switch
                pending={false}
                ariaLabel={'op'}
                platformName={'windows'}
                checked={false}
                onChecked={noop('onChecked')}
                onUnchecked={noop('onUnchecked')}
                theme={theme}
            />
        </ButtonBar>
    );
}
