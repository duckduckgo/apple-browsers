/** @typedef {import('../../types').ORDER_V3[number]} StepsV3  */

/**
 * @typedef {object} Progress
 * @property {number} current - Current step position withing total number of steps
 * @property {number} total - Total number of steps
 */

/**
 * @typedef {object} BeforeAfterFunctions
 * @property {() => import('./BeforeAfterProvider').BeforeAfter|null} get - Gets current before/after state
 * @property {(value: import('./BeforeAfterProvider').BeforeAfter) => void} set - Sets before/after state
 * @property {() => void} toggle - Toggles before/after state
 */

/**
 * @typedef {object} HeadingConfig
 * @property {string|string[]} title - Heading title
 * @property {string|null} [subtitle] - Optional heading subtitle
 * @property {boolean} speechBubble - Whether to wrap the heading in a speech bubble
 * @property {import('preact').ComponentChild} [children] - Optional additional content to include in the heading
 */

/**
 * @typedef {object} ButtonConfig
 * @property {string} text - Button text
 * @property {import('preact').JSX.Element} [startIcon] - Optional leading icon
 * @property {import('preact').JSX.Element} [endIcon] - Optional trailing icon
 * @property {string} [longestText] - Optional array of all possible strings the button can use as text
 * @property {() => void} handler - Function that gets called on button click
 */

/**
 * @typedef {object} StepConfigParams
 * @property {ReturnType<typeof import('../../types')['useTypedTranslation']>['t']} t
 * @property {ImportMeta['platform']} platformName - Current platform
 * @property {import('../../types').GlobalState} globalState - Application state
 * @property {Progress} progress - Step progress
 * @property {() => void} advance - Function that advances to the next step
 * @property {() => void} dismiss - Function that dismisses onboarding completely
 * @property {(id: import('../../types').SystemValueId) => void} enableSystemValue - Function that switches a system setting to ON
 * @property {BeforeAfterFunctions} beforeAfter - Functions that control a step's before/after state
 */

/**
 * @typedef {object} StepConfig
 * @property {'plain'|'box'} variant - Whether the panel is displayed within a rounded rectangle (box) or on a transparent background (plain)
 * @property {HeadingConfig} heading - Configuration for step heading
 * @property {ButtonConfig|null} [dismissButton] - Configuration for dismiss/skip button
 * @property {ButtonConfig|null} [acceptButton] - Configuration for accept button
 * @property {import('preact').ComponentChild} [content] - Step content
 */

/**
 * @typedef {StepConfigParams & StepConfig} StepData
 */

export {};
