import { useContext } from 'preact/hooks';
import { GlobalContext, GlobalDispatch } from '../../global';
import { useTypedTranslation } from '../../types';
import { usePlatformName } from '../SettingsProvider';
import { stepsConfig } from './data';
import { useBeforeAfter } from './BeforeAfterProvider';

/**
 * @param {import('../../types').Step['id'][]} order
 * @param {import('../../types').Step['id']} activeStep
 * @returns {import('./data-types').Progress}
 */
function calculateProgress(order, activeStep) {
    const progressSteps = order.slice(2, order.length);

    return {
        current: progressSteps.indexOf(activeStep) + 1,
        total: progressSteps.length,
    };
}

/**
 *
 * @returns {import('./data-types').StepData}
 */
export function useStepConfig() {
    const globalState = useContext(GlobalContext);
    const platformName = usePlatformName() || 'macos';
    const dispatch = useContext(GlobalDispatch);
    const { t } = useTypedTranslation();
    const { getStep, setStep, toggleStep } = useBeforeAfter();

    const { order, activeStep } = globalState;

    const progress = calculateProgress(order, activeStep);

    const advance = () => {
        dispatch({ kind: 'advance' });
    };

    const dismiss = () => dispatch({ kind: 'dismiss' });

    /** @type {(id: import('../../types').SystemValueId) => void} */
    const enableSystemValue = (id) =>
        dispatch({
            kind: 'update-system-value',
            id,
            payload: { enabled: true },
            current: true,
        });

    /** @type {import('./data-types').BeforeAfterFunctions} */
    const beforeAfter = {
        get: () => getStep(activeStep),
        set: (value) => setStep(activeStep, value),
        toggle: () => toggleStep(activeStep),
    };

    /** @type {import('./data-types').StepConfigParams} */
    const configParams = {
        t,
        platformName,
        globalState,
        progress,
        advance,
        dismiss,
        enableSystemValue,
        beforeAfter,
    };

    if (!stepsConfig[activeStep]) {
        throw new Error(`Missing step config for ${activeStep}`);
    }

    return {
        ...configParams,
        ...stepsConfig[activeStep](configParams),
    };
}
