import { h } from 'preact';

import { noop } from '../../utils.js';
import { NextStepsCard } from './NextStepsCard.js';
import { NextStepsCardGroup, NextStepsBubbleHeader } from './NextStepsGroup.js';

/** @type {Record<string, {factory: () => import("preact").ComponentChild}>} */

export const nextStepsExamples = {
    'next-steps.cardGroup.all': {
        factory: () => (
            <NextStepsCardGroup
                types={[
                    'bringStuff',
                    'defaultApp',
                    'blockCookies',
                    'emailProtection',
                    'duckplayer',
                    'addAppToDockMac',
                    'pinAppToTaskbarWindows',
                ]}
                expansion="collapsed"
                toggle={noop('toggle')}
                dismiss={noop('dismiss')}
                action={noop('action')}
            />
        ),
    },
    'next-steps.cardGroup.all-expanded': {
        factory: () => (
            <NextStepsCardGroup
                types={[
                    'bringStuff',
                    'defaultApp',
                    'blockCookies',
                    'emailProtection',
                    'duckplayer',
                    'addAppToDockMac',
                    'pinAppToTaskbarWindows',
                ]}
                expansion="expanded"
                toggle={noop('toggle')}
                dismiss={noop('dismiss')}
                action={noop('action')}
            />
        ),
    },
    'next-steps.cardGroup.two': {
        factory: () => (
            <NextStepsCardGroup
                types={['bringStuff', 'defaultApp']}
                expansion="collapsed"
                toggle={noop('toggle')}
                dismiss={noop('dismiss')}
                action={noop('action')}
            />
        ),
    },
    'next-steps.cardGroup.one': {
        factory: () => (
            <NextStepsCardGroup
                types={['bringStuff']}
                expansion="collapsed"
                toggle={noop('toggle')}
                dismiss={noop('dismiss')}
                action={noop('action')}
            />
        ),
    },
};

export const otherNextStepsExamples = {
    'next-steps.bringStuff': {
        factory: () => <NextStepsCard type="bringStuff" dismiss={noop('dismiss')} action={noop('action')} />,
    },
    'next-steps.duckplayer': {
        factory: () => <NextStepsCard type="duckplayer" dismiss={noop('dismiss')} action={noop('action')} />,
    },
    'next-steps.defaultApp': {
        factory: () => <NextStepsCard type="defaultApp" dismiss={noop('dismiss')} action={noop('action')} />,
    },
    'next-steps.emailProtection': {
        factory: () => <NextStepsCard type="emailProtection" dismiss={noop('dismiss')} action={noop('action')} />,
    },
    'next-steps.blockCookies': {
        factory: () => <NextStepsCard type="blockCookies" dismiss={noop('dismiss')} action={noop('action')} />,
    },
    'next-steps.addAppToDockMac': {
        factory: () => <NextStepsCard type="addAppToDockMac" dismiss={noop('dismiss')} action={noop('action')} />,
    },
    'next-steps.pinToTaskbarWindows': {
        factory: () => <NextStepsCard type="pinAppToTaskbarWindows" dismiss={noop('dismiss')} action={noop('action')} />,
    },
    'next-steps.bubble': {
        factory: () => <NextStepsBubbleHeader />,
    },
};
