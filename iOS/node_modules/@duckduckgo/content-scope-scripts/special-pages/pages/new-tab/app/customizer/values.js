/**
 * @import { PredefinedColor, PredefinedGradient, BackgroundColorScheme, UserImage } from "../../types/new-tab"
 * @type {{
 *     colors: Record<PredefinedColor, { hex: string; colorScheme: BackgroundColorScheme }>,
 *     gradients: Record<PredefinedGradient, { path: string; colorScheme: BackgroundColorScheme, fallback: string }>
 *     userImages: Record<'01' | '02' | '03', UserImage>
 * }}
 */
export const values = {
    colors: {
        color01: { hex: '#000000', colorScheme: 'dark' },
        color02: { hex: '#342e42', colorScheme: 'dark' },
        color03: { hex: '#4d5f7f', colorScheme: 'dark' },
        color04: { hex: '#9a979d', colorScheme: 'dark' },
        color05: { hex: '#dbdddf', colorScheme: 'light' },
        color06: { hex: '#577de4', colorScheme: 'dark' },
        color07: { hex: '#75b9f0', colorScheme: 'light' },
        color08: { hex: '#5552ac', colorScheme: 'dark' },
        color09: { hex: '#b79ed4', colorScheme: 'light' },
        color10: { hex: '#e4def2', colorScheme: 'light' },
        color11: { hex: '#b5e2ce', colorScheme: 'light' },
        color12: { hex: '#5bc787', colorScheme: 'light' },
        color13: { hex: '#4594a7', colorScheme: 'dark' },
        color14: { hex: '#e9dccd', colorScheme: 'light' },
        color15: { hex: '#f3bb44', colorScheme: 'light' },
        color16: { hex: '#e5724f', colorScheme: 'light' },
        color17: { hex: '#d55154', colorScheme: 'dark' },
        color18: { hex: '#f7dee5', colorScheme: 'light' },
        color19: { hex: '#e28499', colorScheme: 'light' },
    },
    gradients: {
        gradient01: { path: 'gradients/gradient01.svg', fallback: '#f2e5d4', colorScheme: 'light' },
        gradient02: { path: 'gradients/gradient02.svg', fallback: '#d5bcd1', colorScheme: 'light' },
        /**
         * Note: the following name `gradient02.01` is used to allow migration for existing macOS users.
         * When switching to the web-based NTP, we introduced an eight gradient to round-out the columns, but
         * the colors in the gradient meant it needed to be wedged in between 02 and 03.
         */
        'gradient02.01': { path: 'gradients/gradient02.01.svg', fallback: '#f4ca78', colorScheme: 'light' },
        gradient03: { path: 'gradients/gradient03.svg', fallback: '#e6a356', colorScheme: 'light' },
        gradient04: { path: 'gradients/gradient04.svg', fallback: '#4448ae', colorScheme: 'dark' },
        gradient05: { path: 'gradients/gradient05.svg', fallback: '#a55778', colorScheme: 'dark' },
        gradient06: { path: 'gradients/gradient06.svg', fallback: '#222566', colorScheme: 'dark' },
        gradient07: { path: 'gradients/gradient07.svg', fallback: '#0e0e3d', colorScheme: 'dark' },
    },
    userImages: {
        '01': {
            colorScheme: 'dark',
            id: '01',
            src: 'backgrounds/bg-01.jpg',
            thumb: 'backgrounds/bg-01-thumb.jpg',
        },
        '02': {
            colorScheme: 'light',
            id: '02',
            src: 'backgrounds/bg-02.jpg',
            thumb: 'backgrounds/bg-02-thumb.jpg',
        },
        '03': {
            colorScheme: 'light',
            id: '03',
            src: 'backgrounds/bg-03.jpg',
            thumb: 'backgrounds/bg-03-thumb.jpg',
        },
    },
};
