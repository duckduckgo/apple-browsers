/* eslint-disable no-use-before-define */
import { snippets } from './eval-snippets';
import { Config, ConsentState, RuleBundle } from './types';

export type BackgroundMessage = InitResponseMessage | EvalResponseMessage | OptOutMessage | OptInMessage | SelfTestMessage;

export type ContentScriptMessage =
    | InitMessage
    | EvalMessage
    | DetectedMessage
    | FoundMessage
    | OptOutResultMessage
    | OptInResultMessage
    | SelfTestResultMessage
    | DoneMessage
    | ErrorMessage
    | ReportMessage;

export type BackgroundDevtoolsMessage = DevtoolsAuditMessage | InstanceTerminatedMessage | InitResponseMessage;

export type DevtoolsMessage = DevtoolsInitMessage;

export type InitMessage = {
    type: 'init';
    url: string;
};

export type EvalMessage = {
    type: 'eval';
    id: string;
    code: string;
    snippetId?: keyof typeof snippets;
};

export type DetectedMessage = {
    type: 'cmpDetected';
    cmp: string;
    url: string;
};

export type FoundMessage = {
    type: 'popupFound';
    cmp: string;
    url: string;
};

export type OptOutResultMessage = {
    type: 'optOutResult';
    cmp: string;
    result: boolean;
    scheduleSelfTest: boolean;
    url: string;
};

export type OptInResultMessage = {
    type: 'optInResult';
    cmp: string;
    result: boolean;
    scheduleSelfTest: boolean;
    url: string;
};

export type SelfTestResultMessage = {
    type: 'selfTestResult';
    cmp: string;
    result: boolean;
    url: string;
};

export type DoneMessage = {
    type: 'autoconsentDone';
    cmp: string;
    isCosmetic: boolean;
    url: string;
};

export type ErrorMessage = {
    type: 'autoconsentError';
    details: any;
};

export type InitResponseMessage = {
    type: 'initResp';
    rules: RuleBundle;
    config: Config;
};

export type EvalResponseMessage = {
    type: 'evalResp';
    id: string;
    result: any;
};

export type OptOutMessage = {
    type: 'optOut';
};

export type OptInMessage = {
    type: 'optIn';
};

export type SelfTestMessage = {
    type: 'selfTest';
};

export type ReportMessage = {
    type: 'report';
    instanceId: string; // A unique identifier for the frame.
    url: string; // Current frame URL
    mainFrame: boolean; // `true` iff this frame is the top frame.
    state: ConsentState;
};

export type DevtoolsAuditMessage = ReportMessage & { tabId: number; frameId: number };

export type InstanceTerminatedMessage = {
    type: 'instanceTerminated';
    tabId: number;
    instanceId: string;
};

export type DevtoolsInitMessage = {
    type: 'init';
    tabId: number;
};
