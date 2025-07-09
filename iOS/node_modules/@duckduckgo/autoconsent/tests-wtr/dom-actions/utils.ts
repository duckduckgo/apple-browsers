import { DomActions } from '../../lib/dom-actions';

export const instantiateDomActions = () => {
    // @ts-expect-error we don't need to add a full AutoConsent instance, DomActions only needs config.logs from it
    return new DomActions({ config: { logs: { rulesteps: false, lifecycle: false, evals: false, errors: false, messages: false } } });
};
