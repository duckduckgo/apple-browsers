import { blockedFBLogo, blockedYTVideo, videoPlayDark, videoPlayLight } from './ctl-assets.js';

import localesJSON from '../../../../build/locales/ctl-locales.js';

/*********************************************************
 *  Style Definitions
 *********************************************************/
/**
 * Get CSS style defintions for CTL, using the provided AssetConfig for any non-embedded assets
 * (e.g. fonts.)
 * @param {import('../../content-feature.js').AssetConfig} [assets]
 */
export function getStyles(assets) {
    let fontStyle = '';
    let regularFontFamily =
        "system, -apple-system, system-ui, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif, 'Apple Color Emoji', 'Segoe UI Emoji', 'Segoe UI Symbol'";
    let boldFontFamily = regularFontFamily;
    if (assets?.regularFontUrl && assets?.boldFontUrl) {
        fontStyle = `
        @font-face{
            font-family: DuckDuckGoPrivacyEssentials;
            src: url(${assets.regularFontUrl});
        }
        @font-face{
            font-family: DuckDuckGoPrivacyEssentialsBold;
            font-weight: bold;
            src: url(${assets.boldFontUrl});
        }
    `;
        regularFontFamily = 'DuckDuckGoPrivacyEssentials';
        boldFontFamily = 'DuckDuckGoPrivacyEssentialsBold';
    }
    return {
        fontStyle,
        darkMode: {
            background: `
            background: #111111;
        `,
            textFont: `
            color: rgba(255, 255, 255, 0.9);
        `,
            buttonFont: `
            color: #111111;
        `,
            linkFont: `
            color: #7295F6;
        `,
            buttonBackground: `
            background: #5784FF;
        `,
            buttonBackgroundHover: `
            background: #557FF3;
        `,
            buttonBackgroundPress: `
            background: #3969EF;
        `,
            toggleButtonText: `
            color: #EEEEEE;
        `,
            toggleButtonBgState: {
                active: `
                background: #5784FF;
            `,
                inactive: `
                background-color: #666666;
            `,
            },
        },
        lightMode: {
            background: `
            background: #FFFFFF;
        `,
            textFont: `
            color: #222222;
        `,
            buttonFont: `
            color: #FFFFFF;
        `,
            linkFont: `
            color: #3969EF;
        `,
            buttonBackground: `
            background: #3969EF;
        `,
            buttonBackgroundHover: `
            background: #2B55CA;
        `,
            buttonBackgroundPress: `
            background: #1E42A4;
        `,
            toggleButtonText: `
            color: #666666;
        `,
            toggleButtonBgState: {
                active: `
                background: #3969EF;
            `,
                inactive: `
                background-color: #666666;
            `,
            },
        },
        loginMode: {
            buttonBackground: `
            background: #666666;
        `,
            buttonFont: `
            color: #FFFFFF;
        `,
        },
        cancelMode: {
            buttonBackground: `
            background: rgba(34, 34, 34, 0.1);
        `,
            buttonFont: `
            color: #222222;
        `,
            buttonBackgroundHover: `
            background: rgba(0, 0, 0, 0.12);
        `,
            buttonBackgroundPress: `
            background: rgba(0, 0, 0, 0.18);
        `,
        },
        button: `
        border-radius: 8px;

        padding: 11px 22px;
        font-weight: bold;
        margin: 0px auto;
        border-color: #3969EF;
        border: none;

        font-family: ${boldFontFamily};
        font-size: 14px;

        position: relative;
        cursor: pointer;
        box-shadow: none;
        z-index: 2147483646;
    `,
        circle: `
        border-radius: 50%;
        width: 18px;
        height: 18px;
        background: #E0E0E0;
        border: 1px solid #E0E0E0;
        position: absolute;
        top: -8px;
        right: -8px;
    `,
        loginIcon: `
        position: absolute;
        top: -13px;
        right: -10px;
        height: 28px;
        width: 28px;
    `,
        rectangle: `
        width: 12px;
        height: 3px;
        background: #666666;
        position: relative;
        top: 42.5%;
        margin: auto;
    `,
        textBubble: `
        background: #FFFFFF;
        border: 1px solid rgba(0, 0, 0, 0.1);
        border-radius: 16px;
        box-shadow: 0px 2px 6px rgba(0, 0, 0, 0.12), 0px 8px 16px rgba(0, 0, 0, 0.08);
        width: 360px;
        margin-top: 10px;
        z-index: 2147483647;
        position: absolute;
        line-height: normal;
    `,
        textBubbleWidth: 360, // Should match the width rule in textBubble
        textBubbleLeftShift: 100, // Should match the CSS left: rule in textBubble
        textArrow: `
        display: inline-block;
        background: #FFFFFF;
        border: solid rgba(0, 0, 0, 0.1);
        border-width: 0 1px 1px 0;
        padding: 5px;
        transform: rotate(-135deg);
        -webkit-transform: rotate(-135deg);
        position: relative;
        top: -9px;
    `,
        arrowDefaultLocationPercent: 50,
        hoverTextTitle: `
        padding: 0px 12px 12px;
        margin-top: -5px;
    `,
        hoverTextBody: `
        font-family: ${regularFontFamily};
        font-size: 14px;
        line-height: 21px;
        margin: auto;
        padding: 17px;
        text-align: left;
    `,
        hoverContainer: `
        padding-bottom: 10px;
    `,
        buttonTextContainer: `
        display: flex;
        flex-direction: row;
        align-items: center;
        border: none;
        padding: 0;
        margin: 0;
    `,
        headerRow: `

    `,
        block: `
        box-sizing: border-box;
        border: 1px solid rgba(0,0,0,0.1);
        border-radius: 12px;
        max-width: 600px;
        min-height: 300px;
        margin: auto;
        display: flex;
        flex-direction: column;

        font-family: ${regularFontFamily};
        line-height: 1;
    `,
        youTubeDialogBlock: `
        height: calc(100% - 30px);
        max-width: initial;
        min-height: initial;
    `,
        imgRow: `
        display: flex;
        flex-direction: column;
        margin: 20px 0px;
    `,
        content: `
        display: flex;
        flex-direction: column;
        padding: 16px 0;
        flex: 1 1 1px;
    `,
        feedbackLink: `
        font-family: ${regularFontFamily};
        font-style: normal;
        font-weight: 400;
        font-size: 12px;
        line-height: 12px;
        color: #ABABAB;
        text-decoration: none;
    `,
        feedbackRow: `
        height: 30px;
        display: flex;
        justify-content: flex-end;
        align-items: center;
    `,
        titleBox: `
        display: flex;
        padding: 12px;
        max-height: 44px;
        border-bottom: 1px solid;
        border-color: rgba(196, 196, 196, 0.3);
        margin: 0;
        margin-bottom: 4px;
    `,
        title: `
        font-family: ${regularFontFamily};
        line-height: 1.4;
        font-size: 14px;
        margin: auto 10px;
        flex-basis: 100%;
        height: 1.4em;
        flex-wrap: wrap;
        overflow: hidden;
        text-align: left;
        border: none;
        padding: 0;
    `,
        buttonRow: `
        display: flex;
        height: 100%
        flex-direction: row;
        margin: 20px auto 0px;
        height: 100%;
        align-items: flex-start;
    `,
        modalContentTitle: `
        font-family: ${boldFontFamily};
        font-size: 17px;
        font-weight: bold;
        line-height: 21px;
        margin: 10px auto;
        text-align: center;
        border: none;
        padding: 0px 32px;
    `,
        modalContentText: `
        font-family: ${regularFontFamily};
        font-size: 14px;
        line-height: 21px;
        margin: 0px auto 14px;
        text-align: center;
        border: none;
        padding: 0;
    `,
        modalButtonRow: `
        border: none;
        padding: 0;
        margin: auto;
        width: 100%;
        display: flex;
        flex-direction: column;
        align-items: center;
    `,
        modalButton: `
        width: 100%;
        display: flex;
        justify-content: center;
        align-items: center;
    `,
        modalIcon: `
        display: block;
    `,
        contentTitle: `
        font-family: ${boldFontFamily};
        font-size: 17px;
        font-weight: bold;
        margin: 20px auto 10px;
        padding: 0px 30px;
        text-align: center;
        margin-top: auto;
    `,
        contentText: `
        font-family: ${regularFontFamily};
        font-size: 14px;
        line-height: 21px;
        padding: 0px 40px;
        text-align: center;
        margin: 0 auto auto;
    `,
        icon: `
        height: 80px;
        width: 80px;
        margin: auto;
    `,
        closeIcon: `
        height: 12px;
        width: 12px;
        margin: auto;
    `,
        closeButton: `
        display: flex;
        justify-content: center;
        align-items: center;
        min-width: 20px;
        height: 21px;
        border: 0;
        background: transparent;
        cursor: pointer;
    `,
        logo: `
        flex-basis: 0%;
        min-width: 20px;
        height: 21px;
        border: none;
        padding: 0;
        margin: 0;
    `,
        logoImg: `
        height: 21px;
        width: 21px;
    `,
        loadingImg: `
        display: block;
        margin: 0px 8px 0px 0px;
        height: 14px;
        width: 14px;
    `,
        modal: `
        width: 340px;
        padding: 0;
        margin: auto;
        background-color: #FFFFFF;
        position: absolute;
        top: 50%;
        left: 50%;
        transform: translate(-50%, -50%);
        display: block;
        box-shadow: 0px 1px 3px rgba(0, 0, 0, 0.08), 0px 2px 4px rgba(0, 0, 0, 0.1);
        border-radius: 12px;
        border: none;
    `,
        modalContent: `
        padding: 24px;
        display: flex;
        flex-direction: column;
        border: none;
        margin: 0;
    `,
        overlay: `
        height: 100%;
        width: 100%;
        background-color: #666666;
        opacity: .5;
        display: block;
        position: fixed;
        top: 0;
        right: 0;
        border: none;
        padding: 0;
        margin: 0;
    `,
        modalContainer: `
        height: 100vh;
        width: 100vw;
        box-sizing: border-box;
        z-index: 2147483647;
        display: block;
        position: fixed;
        border: 0;
        margin: 0;
        padding: 0;
    `,
        headerLinkContainer: `
        flex-basis: 100%;
        display: grid;
        justify-content: flex-end;
    `,
        headerLink: `
        line-height: 1.4;
        font-size: 14px;
        font-weight: bold;
        font-family: ${boldFontFamily};
        text-decoration: none;
        cursor: pointer;
        min-width: 100px;
        text-align: end;
        float: right;
        display: none;
    `,
        generalLink: `
        line-height: 1.4;
        font-size: 14px;
        font-weight: bold;
        font-family: ${boldFontFamily};
        cursor: pointer;
        text-decoration: none;
    `,
        wrapperDiv: `
        display: inline-block;
        border: 0;
        padding: 0;
        margin: 0;
        max-width: 600px;
        min-height: 300px;
    `,
        toggleButtonWrapper: `
        display: flex;
        align-items: center;
        cursor: pointer;
    `,
        toggleButton: `
        cursor: pointer;
        position: relative;
        width: 30px;
        height: 16px;
        margin-top: -3px;
        margin: 0;
        padding: 0;
        border: none;
        background-color: transparent;
        text-align: left;
    `,
        toggleButtonBg: `
        right: 0;
        width: 30px;
        height: 16px;
        overflow: visible;
        border-radius: 10px;
    `,
        toggleButtonText: `
        display: inline-block;
        margin: 0 0 0 7px;
        padding: 0;
    `,
        toggleButtonKnob: `
        position: absolute;
        display: inline-block;
        width: 14px;
        height: 14px;
        border-radius: 10px;
        background-color: #ffffff;
        margin-top: 1px;
        top: calc(50% - 14px/2 - 1px);
        box-shadow: 0px 0px 1px rgba(0, 0, 0, 0.05), 0px 1px 1px rgba(0, 0, 0, 0.1);
    `,
        toggleButtonKnobState: {
            active: `
            right: 1px;
        `,
            inactive: `
            left: 1px;
        `,
        },
        placeholderWrapperDiv: `
        position: relative;
        overflow: hidden;
        border-radius: 12px;
        box-sizing: border-box;
        max-width: initial;
        min-width: 380px;
        min-height: 300px;
        margin: auto;
    `,
        youTubeWrapperDiv: `
        position: relative;
        overflow: hidden;
        max-width: initial;
        min-width: 380px;
        min-height: 300px;
        height: 100%;
    `,
        youTubeDialogDiv: `
        position: relative;
        overflow: hidden;
        border-radius: 12px;
        max-width: initial;
        min-height: initial;
        height: calc(100% - 30px);
    `,
        youTubeDialogBottomRow: `
        display: flex;
        flex-direction: column;
        align-items: center;
        justify-content: flex-end;
        margin-top: auto;
    `,
        youTubePlaceholder: `
        display: flex;
        flex-direction: column;
        justify-content: flex-start;
        position: relative;
        width: 100%;
        height: 100%;
        background: rgba(45, 45, 45, 0.8);
    `,
        youTubePreviewWrapperImg: `
        position: absolute;
        display: flex;
        justify-content: center;
        align-items: center;
        width: 100%;
        height: 100%;
    `,
        youTubePreviewImg: `
        min-width: 100%;
        min-height: 100%;
        height: auto;
    `,
        youTubeTopSection: `
        font-family: ${boldFontFamily};
        flex: 1;
        display: flex;
        justify-content: space-between;
        position: relative;
        padding: 18px 12px 0;
    `,
        youTubeTitle: `
        font-size: 14px;
        font-weight: bold;
        line-height: 14px;
        color: #FFFFFF;
        margin: 0;
        width: 100%;
        white-space: nowrap;
        overflow: hidden;
        text-overflow: ellipsis;
        box-sizing: border-box;
    `,
        youTubePlayButtonRow: `
        flex: 2;
        display: flex;
        align-items: center;
        justify-content: center;
    `,
        youTubePlayButton: `
        display: flex;
        justify-content: center;
        align-items: center;
        height: 48px;
        width: 80px;
        padding: 0px 24px;
        border-radius: 8px;
    `,
        youTubePreviewToggleRow: `
        flex: 1;
        display: flex;
        flex-direction: column;
        justify-content: flex-end;
        align-items: center;
        padding: 0 12px 18px;
    `,
        youTubePreviewToggleText: `
        color: #EEEEEE;
        font-weight: 400;
    `,
        youTubePreviewInfoText: `
        color: #ABABAB;
    `,
    };
}

/**
 * @param {string} locale UI locale
 */
export function getConfig(locale) {
    const allLocales = JSON.parse(localesJSON);
    const localeStrings = allLocales[locale] || allLocales.en;

    const fbStrings = localeStrings['facebook.json'];
    const ytStrings = localeStrings['youtube.json'];
    const sharedStrings = localeStrings['shared.json'];

    const config = {
        'Facebook, Inc.': {
            informationalModal: {
                icon: blockedFBLogo,
                messageTitle: fbStrings.informationalModalMessageTitle,
                messageBody: fbStrings.informationalModalMessageBody,
                confirmButtonText: fbStrings.informationalModalConfirmButtonText,
                rejectButtonText: fbStrings.informationalModalRejectButtonText,
            },
            elementData: {
                'FB Like Button': {
                    selectors: ['.fb-like'],
                    replaceSettings: {
                        type: 'blank',
                    },
                },
                'FB Button iFrames': {
                    selectors: [
                        "iframe[src*='//www.facebook.com/plugins/like.php']",
                        "iframe[src*='//www.facebook.com/v2.0/plugins/like.php']",
                        "iframe[src*='//www.facebook.com/plugins/share_button.php']",
                        "iframe[src*='//www.facebook.com/v2.0/plugins/share_button.php']",
                    ],
                    replaceSettings: {
                        type: 'blank',
                    },
                },
                'FB Save Button': {
                    selectors: ['.fb-save'],
                    replaceSettings: {
                        type: 'blank',
                    },
                },
                'FB Share Button': {
                    selectors: ['.fb-share-button'],
                    replaceSettings: {
                        type: 'blank',
                    },
                },
                'FB Page iFrames': {
                    selectors: [
                        "iframe[src*='//www.facebook.com/plugins/page.php']",
                        "iframe[src*='//www.facebook.com/v2.0/plugins/page.php']",
                    ],
                    replaceSettings: {
                        type: 'dialog',
                        buttonText: fbStrings.buttonTextUnblockContent,
                        infoTitle: fbStrings.infoTitleUnblockContent,
                        infoText: fbStrings.infoTextUnblockContent,
                    },
                    clickAction: {
                        type: 'originalElement',
                    },
                },
                'FB Page Div': {
                    selectors: ['.fb-page'],
                    replaceSettings: {
                        type: 'dialog',
                        buttonText: fbStrings.buttonTextUnblockContent,
                        infoTitle: fbStrings.infoTitleUnblockContent,
                        infoText: fbStrings.infoTextUnblockContent,
                    },
                    clickAction: {
                        type: 'iFrame',
                        targetURL:
                            'https://www.facebook.com/plugins/page.php?href=data-href&tabs=data-tabs&width=data-width&height=data-height',
                        urlDataAttributesToPreserve: {
                            'data-href': {
                                default: '',
                                required: true,
                            },
                            'data-tabs': {
                                default: 'timeline',
                            },
                            'data-height': {
                                default: '500',
                            },
                            'data-width': {
                                default: '500',
                            },
                        },
                        styleDataAttributes: {
                            width: {
                                name: 'data-width',
                                unit: 'px',
                            },
                            height: {
                                name: 'data-height',
                                unit: 'px',
                            },
                        },
                    },
                },
                'FB Comment iFrames': {
                    selectors: [
                        "iframe[src*='//www.facebook.com/plugins/comment_embed.php']",
                        "iframe[src*='//www.facebook.com/v2.0/plugins/comment_embed.php']",
                    ],
                    replaceSettings: {
                        type: 'dialog',
                        buttonText: fbStrings.buttonTextUnblockComment,
                        infoTitle: fbStrings.infoTitleUnblockComment,
                        infoText: fbStrings.infoTextUnblockContent,
                    },
                    clickAction: {
                        type: 'originalElement',
                    },
                },
                'FB Comments': {
                    selectors: ['.fb-comments', 'fb\\:comments'],
                    replaceSettings: {
                        type: 'dialog',
                        buttonText: fbStrings.buttonTextUnblockComments,
                        infoTitle: fbStrings.infoTitleUnblockComments,
                        infoText: fbStrings.infoTextUnblockContent,
                    },
                    clickAction: {
                        type: 'allowFull',
                        targetURL:
                            'https://www.facebook.com/v9.0/plugins/comments.php?href=data-href&numposts=data-numposts&sdk=joey&version=v9.0&width=data-width',
                        urlDataAttributesToPreserve: {
                            'data-href': {
                                default: '',
                                required: true,
                            },
                            'data-numposts': {
                                default: 10,
                            },
                            'data-width': {
                                default: '500',
                            },
                        },
                    },
                },
                'FB Embedded Comment Div': {
                    selectors: ['.fb-comment-embed'],
                    replaceSettings: {
                        type: 'dialog',
                        buttonText: fbStrings.buttonTextUnblockComment,
                        infoTitle: fbStrings.infoTitleUnblockComment,
                        infoText: fbStrings.infoTextUnblockContent,
                    },
                    clickAction: {
                        type: 'iFrame',
                        targetURL:
                            'https://www.facebook.com/v9.0/plugins/comment_embed.php?href=data-href&sdk=joey&width=data-width&include_parent=data-include-parent',
                        urlDataAttributesToPreserve: {
                            'data-href': {
                                default: '',
                                required: true,
                            },
                            'data-width': {
                                default: '500',
                            },
                            'data-include-parent': {
                                default: 'false',
                            },
                        },
                        styleDataAttributes: {
                            width: {
                                name: 'data-width',
                                unit: 'px',
                            },
                        },
                    },
                },
                'FB Post iFrames': {
                    selectors: [
                        "iframe[src*='//www.facebook.com/plugins/post.php']",
                        "iframe[src*='//www.facebook.com/v2.0/plugins/post.php']",
                    ],
                    replaceSettings: {
                        type: 'dialog',
                        buttonText: fbStrings.buttonTextUnblockPost,
                        infoTitle: fbStrings.infoTitleUnblockPost,
                        infoText: fbStrings.infoTextUnblockContent,
                    },
                    clickAction: {
                        type: 'originalElement',
                    },
                },
                'FB Posts Div': {
                    selectors: ['.fb-post'],
                    replaceSettings: {
                        type: 'dialog',
                        buttonText: fbStrings.buttonTextUnblockPost,
                        infoTitle: fbStrings.infoTitleUnblockPost,
                        infoText: fbStrings.infoTextUnblockContent,
                    },
                    clickAction: {
                        type: 'allowFull',
                        targetURL: 'https://www.facebook.com/v9.0/plugins/post.php?href=data-href&sdk=joey&show_text=true&width=data-width',
                        urlDataAttributesToPreserve: {
                            'data-href': {
                                default: '',
                                required: true,
                            },
                            'data-width': {
                                default: '500',
                            },
                        },
                        styleDataAttributes: {
                            width: {
                                name: 'data-width',
                                unit: 'px',
                            },
                            height: {
                                name: 'data-height',
                                unit: 'px',
                                fallbackAttribute: 'data-width',
                            },
                        },
                    },
                },
                'FB Video iFrames': {
                    selectors: [
                        "iframe[src*='//www.facebook.com/plugins/video.php']",
                        "iframe[src*='//www.facebook.com/v2.0/plugins/video.php']",
                    ],
                    replaceSettings: {
                        type: 'dialog',
                        buttonText: fbStrings.buttonTextUnblockVideo,
                        infoTitle: fbStrings.infoTitleUnblockVideo,
                        infoText: fbStrings.infoTextUnblockContent,
                    },
                    clickAction: {
                        type: 'originalElement',
                    },
                },
                'FB Video': {
                    selectors: ['.fb-video'],
                    replaceSettings: {
                        type: 'dialog',
                        buttonText: fbStrings.buttonTextUnblockVideo,
                        infoTitle: fbStrings.infoTitleUnblockVideo,
                        infoText: fbStrings.infoTextUnblockContent,
                    },
                    clickAction: {
                        type: 'iFrame',
                        targetURL: 'https://www.facebook.com/plugins/video.php?href=data-href&show_text=true&width=data-width',
                        urlDataAttributesToPreserve: {
                            'data-href': {
                                default: '',
                                required: true,
                            },
                            'data-width': {
                                default: '500',
                            },
                        },
                        styleDataAttributes: {
                            width: {
                                name: 'data-width',
                                unit: 'px',
                            },
                            height: {
                                name: 'data-height',
                                unit: 'px',
                                fallbackAttribute: 'data-width',
                            },
                        },
                    },
                },
                'FB Group iFrames': {
                    selectors: [
                        "iframe[src*='//www.facebook.com/plugins/group.php']",
                        "iframe[src*='//www.facebook.com/v2.0/plugins/group.php']",
                    ],
                    replaceSettings: {
                        type: 'dialog',
                        buttonText: fbStrings.buttonTextUnblockContent,
                        infoTitle: fbStrings.infoTitleUnblockContent,
                        infoText: fbStrings.infoTextUnblockContent,
                    },
                    clickAction: {
                        type: 'originalElement',
                    },
                },
                'FB Group': {
                    selectors: ['.fb-group'],
                    replaceSettings: {
                        type: 'dialog',
                        buttonText: fbStrings.buttonTextUnblockContent,
                        infoTitle: fbStrings.infoTitleUnblockContent,
                        infoText: fbStrings.infoTextUnblockContent,
                    },
                    clickAction: {
                        type: 'iFrame',
                        targetURL: 'https://www.facebook.com/plugins/group.php?href=data-href&width=data-width',
                        urlDataAttributesToPreserve: {
                            'data-href': {
                                default: '',
                                required: true,
                            },
                            'data-width': {
                                default: '500',
                            },
                        },
                        styleDataAttributes: {
                            width: {
                                name: 'data-width',
                                unit: 'px',
                            },
                        },
                    },
                },
                'FB Login Button': {
                    selectors: ['.fb-login-button'],
                    replaceSettings: {
                        type: 'loginButton',
                        icon: blockedFBLogo,
                        buttonText: fbStrings.loginButtonText,
                        buttonTextUnblockLogin: fbStrings.buttonTextUnblockLogin,
                        popupBodyText: fbStrings.loginBodyText,
                    },
                    clickAction: {
                        type: 'allowFull',
                        targetURL:
                            'https://www.facebook.com/v9.0/plugins/login_button.php?app_id=app_id_replace&auto_logout_link=false&button_type=continue_with&sdk=joey&size=large&use_continue_as=false&width=',
                        urlDataAttributesToPreserve: {
                            'data-href': {
                                default: '',
                                required: true,
                            },
                            'data-width': {
                                default: '500',
                            },
                            app_id_replace: {
                                default: 'null',
                            },
                        },
                    },
                },
            },
        },
        Youtube: {
            informationalModal: {
                icon: blockedYTVideo,
                messageTitle: ytStrings.informationalModalMessageTitle,
                messageBody: ytStrings.informationalModalMessageBody,
                confirmButtonText: ytStrings.informationalModalConfirmButtonText,
                rejectButtonText: ytStrings.informationalModalRejectButtonText,
            },
            elementData: {
                'YouTube embedded video': {
                    selectors: [
                        "iframe[src*='//youtube.com/embed']",
                        "iframe[src*='//youtube-nocookie.com/embed']",
                        "iframe[src*='//www.youtube.com/embed']",
                        "iframe[src*='//www.youtube-nocookie.com/embed']",
                        "iframe[data-src*='//youtube.com/embed']",
                        "iframe[data-src*='//youtube-nocookie.com/embed']",
                        "iframe[data-src*='//www.youtube.com/embed']",
                        "iframe[data-src*='//www.youtube-nocookie.com/embed']",
                    ],
                    replaceSettings: {
                        type: 'youtube-video',
                        buttonText: ytStrings.buttonTextUnblockVideo,
                        infoTitle: ytStrings.infoTitleUnblockVideo,
                        infoText: ytStrings.infoTextUnblockVideo,
                        previewToggleText: ytStrings.infoPreviewToggleText,
                        placeholder: {
                            previewToggleEnabledText: ytStrings.infoPreviewToggleEnabledText,
                            previewInfoText: ytStrings.infoPreviewInfoText,
                            previewToggleEnabledDuckDuckGoText: ytStrings.infoPreviewToggleEnabledText,
                            videoPlayIcon: {
                                lightMode: videoPlayLight,
                                darkMode: videoPlayDark,
                            },
                        },
                    },
                    clickAction: {
                        type: 'youtube-video',
                    },
                },
                'YouTube embedded subscription button': {
                    selectors: [
                        "iframe[src*='//youtube.com/subscribe_embed']",
                        "iframe[src*='//youtube-nocookie.com/subscribe_embed']",
                        "iframe[src*='//www.youtube.com/subscribe_embed']",
                        "iframe[src*='//www.youtube-nocookie.com/subscribe_embed']",
                        "iframe[data-src*='//youtube.com/subscribe_embed']",
                        "iframe[data-src*='//youtube-nocookie.com/subscribe_embed']",
                        "iframe[data-src*='//www.youtube.com/subscribe_embed']",
                        "iframe[data-src*='//www.youtube-nocookie.com/subscribe_embed']",
                    ],
                    replaceSettings: {
                        type: 'blank',
                    },
                },
            },
        },
    };

    return { config, sharedStrings };
}
