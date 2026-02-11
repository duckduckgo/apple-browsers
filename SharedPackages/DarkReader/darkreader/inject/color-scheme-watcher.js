(function () {
    'use strict';

    const isNavigatorDefined = typeof navigator !== 'undefined';
    const userAgent = isNavigatorDefined ? (navigator.userAgentData && Array.isArray(navigator.userAgentData.brands)) ?
        navigator.userAgentData.brands.map((brand) => `${brand.brand.toLowerCase()} ${brand.version}`).join(' ') : navigator.userAgent.toLowerCase()
        : 'some useragent';
    const platform = isNavigatorDefined ? (navigator.userAgentData && typeof navigator.userAgentData.platform === 'string') ?
        navigator.userAgentData.platform.toLowerCase() : navigator.platform.toLowerCase()
        : 'some platform';
    (userAgent.includes('vivaldi'));
    (userAgent.includes('yabrowser'));
    ((userAgent.includes('opr') || userAgent.includes('opera')));
    (userAgent.includes('edg'));
    platform.startsWith('win');
    platform.startsWith('mac');
    (isNavigatorDefined && navigator.userAgentData) ? navigator.userAgentData.mobile : (userAgent.includes('mobile') || (false));
    // Return true if browser is known to have a bug with Media Queries, specifically Chromium on Linux and Kiwi on Android
    // We assume that if we are on Android, then we are running in Kiwi since it is the only mobile browser we can install Dark Reader in
    (((isNavigatorDefined && navigator.userAgentData) && ['Linux', 'Android'].includes(navigator.userAgentData.platform))
        || platform.startsWith('linux'));
    (() => {
        const m = userAgent.match(/chrom(?:e|ium)(?:\/| )([^ ]+)/);
        if (m && m[1]) {
            return m[1];
        }
        return '';
    })();
    (() => {
        const m = userAgent.match(/(?:firefox|librewolf)(?:\/| )([^ ]+)/);
        if (m && m[1]) {
            return m[1];
        }
        return '';
    })();
    (() => {
        try {
            document.querySelector(':defined');
            return true;
        }
        catch (err) {
            return false;
        }
    })();

    let query = null;
    const onChange = ({ matches }) => listeners.forEach((listener) => listener(matches));
    const listeners = new Set();
    function runColorSchemeChangeDetector(callback) {
        listeners.add(callback);
        if (query) {
            return;
        }
        query = matchMedia('(prefers-color-scheme: dark)');
        {
            // MediaQueryList change event is not cancellable and does not bubble
            query.addEventListener('change', onChange);
        }
    }
    function stopColorSchemeChangeDetector() {
        if (!query || !onChange) {
            return;
        }
        {
            query.removeEventListener('change', onChange);
        }
        listeners.clear();
        query = null;
    }
    const isSystemDarkModeEnabled = () => (query || matchMedia('(prefers-color-scheme: dark)')).matches;

    var MessageTypeUItoBG;
    (function (MessageTypeUItoBG) {
        MessageTypeUItoBG["GET_DATA"] = "ui-bg-get-data";
        MessageTypeUItoBG["GET_DEVTOOLS_DATA"] = "ui-bg-get-devtools-data";
        MessageTypeUItoBG["SUBSCRIBE_TO_CHANGES"] = "ui-bg-subscribe-to-changes";
        MessageTypeUItoBG["UNSUBSCRIBE_FROM_CHANGES"] = "ui-bg-unsubscribe-from-changes";
        MessageTypeUItoBG["CHANGE_SETTINGS"] = "ui-bg-change-settings";
        MessageTypeUItoBG["SET_THEME"] = "ui-bg-set-theme";
        MessageTypeUItoBG["TOGGLE_ACTIVE_TAB"] = "ui-bg-toggle-active-tab";
        MessageTypeUItoBG["MARK_NEWS_AS_READ"] = "ui-bg-mark-news-as-read";
        MessageTypeUItoBG["MARK_NEWS_AS_DISPLAYED"] = "ui-bg-mark-news-as-displayed";
        MessageTypeUItoBG["LOAD_CONFIG"] = "ui-bg-load-config";
        MessageTypeUItoBG["APPLY_DEV_DYNAMIC_THEME_FIXES"] = "ui-bg-apply-dev-dynamic-theme-fixes";
        MessageTypeUItoBG["RESET_DEV_DYNAMIC_THEME_FIXES"] = "ui-bg-reset-dev-dynamic-theme-fixes";
        MessageTypeUItoBG["APPLY_DEV_INVERSION_FIXES"] = "ui-bg-apply-dev-inversion-fixes";
        MessageTypeUItoBG["RESET_DEV_INVERSION_FIXES"] = "ui-bg-reset-dev-inversion-fixes";
        MessageTypeUItoBG["APPLY_DEV_STATIC_THEMES"] = "ui-bg-apply-dev-static-themes";
        MessageTypeUItoBG["RESET_DEV_STATIC_THEMES"] = "ui-bg-reset-dev-static-themes";
        MessageTypeUItoBG["START_ACTIVATION"] = "ui-bg-start-activation";
        MessageTypeUItoBG["RESET_ACTIVATION"] = "ui-bg-reset-activation";
        MessageTypeUItoBG["COLOR_SCHEME_CHANGE"] = "ui-bg-color-scheme-change";
        MessageTypeUItoBG["HIDE_HIGHLIGHTS"] = "ui-bg-hide-highlights";
    })(MessageTypeUItoBG || (MessageTypeUItoBG = {}));
    var MessageTypeBGtoUI;
    (function (MessageTypeBGtoUI) {
        MessageTypeBGtoUI["CHANGES"] = "bg-ui-changes";
    })(MessageTypeBGtoUI || (MessageTypeBGtoUI = {}));
    var DebugMessageTypeBGtoUI;
    (function (DebugMessageTypeBGtoUI) {
        DebugMessageTypeBGtoUI["CSS_UPDATE"] = "debug-bg-ui-css-update";
        DebugMessageTypeBGtoUI["UPDATE"] = "debug-bg-ui-update";
    })(DebugMessageTypeBGtoUI || (DebugMessageTypeBGtoUI = {}));
    var MessageTypeBGtoCS;
    (function (MessageTypeBGtoCS) {
        MessageTypeBGtoCS["ADD_CSS_FILTER"] = "bg-cs-add-css-filter";
        MessageTypeBGtoCS["ADD_DYNAMIC_THEME"] = "bg-cs-add-dynamic-theme";
        MessageTypeBGtoCS["ADD_STATIC_THEME"] = "bg-cs-add-static-theme";
        MessageTypeBGtoCS["ADD_SVG_FILTER"] = "bg-cs-add-svg-filter";
        MessageTypeBGtoCS["CLEAN_UP"] = "bg-cs-clean-up";
        MessageTypeBGtoCS["FETCH_RESPONSE"] = "bg-cs-fetch-response";
        MessageTypeBGtoCS["UNSUPPORTED_SENDER"] = "bg-cs-unsupported-sender";
    })(MessageTypeBGtoCS || (MessageTypeBGtoCS = {}));
    var DebugMessageTypeBGtoCS;
    (function (DebugMessageTypeBGtoCS) {
        DebugMessageTypeBGtoCS["RELOAD"] = "debug-bg-cs-reload";
    })(DebugMessageTypeBGtoCS || (DebugMessageTypeBGtoCS = {}));
    var MessageTypeCStoBG;
    (function (MessageTypeCStoBG) {
        MessageTypeCStoBG["COLOR_SCHEME_CHANGE"] = "cs-bg-color-scheme-change";
        MessageTypeCStoBG["DARK_THEME_DETECTED"] = "cs-bg-dark-theme-detected";
        MessageTypeCStoBG["DARK_THEME_NOT_DETECTED"] = "cs-bg-dark-theme-not-detected";
        MessageTypeCStoBG["FETCH"] = "cs-bg-fetch";
        MessageTypeCStoBG["DOCUMENT_CONNECT"] = "cs-bg-document-connect";
        MessageTypeCStoBG["DOCUMENT_FORGET"] = "cs-bg-document-forget";
        MessageTypeCStoBG["DOCUMENT_FREEZE"] = "cs-bg-document-freeze";
        MessageTypeCStoBG["DOCUMENT_RESUME"] = "cs-bg-document-resume";
    })(MessageTypeCStoBG || (MessageTypeCStoBG = {}));
    var DebugMessageTypeCStoBG;
    (function (DebugMessageTypeCStoBG) {
        DebugMessageTypeCStoBG["LOG"] = "debug-cs-bg-log";
    })(DebugMessageTypeCStoBG || (DebugMessageTypeCStoBG = {}));
    var MessageTypeCStoUI;
    (function (MessageTypeCStoUI) {
        MessageTypeCStoUI["EXPORT_CSS_RESPONSE"] = "cs-ui-export-css-response";
    })(MessageTypeCStoUI || (MessageTypeCStoUI = {}));
    var MessageTypeUItoCS;
    (function (MessageTypeUItoCS) {
        MessageTypeUItoCS["EXPORT_CSS"] = "ui-cs-export-css";
    })(MessageTypeUItoCS || (MessageTypeUItoCS = {}));

    /**
     * The following code contains a workaround for extensions designed to prevent page from knowing when it is hidden
     * GitHub issue: https://github.com/darkreader/darkreader/issues/10004
     * GitHub PR: https://github.com/darkreader/darkreader/pull/10047
     *
     * Due to the intentional breakage introduced by these extensions, this utility might incorrectly report that document
     * is visible while it is not, but it will never report document as hidden while it is visible.
     *
     * This code exploits the fact that most such extensions block only a subset of Page Lifecycle API,
     * which notifies page of being hidden but not of being shown, while Dark Reader really cares only about
     * page being shown.
     * Specifically:
     *  - extensions block visibilitychange and blur event
     *  - extensions do not block focus event; browsers deliver focus event when user switches to
     *    a previously hidden tab or previously hidden window (assuming DevTools are closed so window gets the focus)
     *    if document has focus, then we can assume that it is visible
     *  - some extensions overwrite document.hidden but not document.visibilityState
     *  - Firefox has a bug: if extension overwrites document.hidden and document.visibilityState via Object.defineProperty,
     *    then Firefox will reset them to true and 'hidden' when tab is activated, but document.hasFocus() will be true
     *  - Safari supports document.visibilityState === 'prerender' which makes document.hidden === true even when document
     *    is visible to the user
     *
     * Note: This utility supports adding only one callback since currently calling code sets only one listener and Firefox
     * has issues optimizing code with multiple callbacks stored in array or in a set.
     */
    let documentVisibilityListener = null;
    let documentIsVisible_ = !document.hidden;
    // TODO: use EventListenerOptions class once it is updated
    const listenerOptions = {
        capture: true,
        passive: true,
    };
    function watchForDocumentVisibility() {
        document.addEventListener('visibilitychange', documentVisibilityListener, listenerOptions);
        window.addEventListener('pageshow', documentVisibilityListener, listenerOptions);
        window.addEventListener('focus', documentVisibilityListener, listenerOptions);
    }
    function stopWatchingForDocumentVisibility() {
        document.removeEventListener('visibilitychange', documentVisibilityListener, listenerOptions);
        window.removeEventListener('pageshow', documentVisibilityListener, listenerOptions);
        window.removeEventListener('focus', documentVisibilityListener, listenerOptions);
    }
    function setDocumentVisibilityListener(callback) {
        const alreadyWatching = Boolean(documentVisibilityListener);
        documentVisibilityListener = () => {
            if (!document.hidden) {
                removeDocumentVisibilityListener();
                callback();
                documentIsVisible_ = true;
            }
        };
        if (!alreadyWatching) {
            watchForDocumentVisibility();
        }
    }
    function removeDocumentVisibilityListener() {
        stopWatchingForDocumentVisibility();
        documentVisibilityListener = null;
    }
    function documentIsVisible() {
        return documentIsVisible_;
    }

    function cleanup() {
        stopColorSchemeChangeDetector();
        removeDocumentVisibilityListener();
    }
    function sendMessage(message) {
        const responseHandler = (response) => {
            // Vivaldi bug workaround. See TabManager for details.
            if (response === 'unsupportedSender') {
                cleanup();
            }
        };
        try {
            const promise = chrome.runtime.sendMessage(message);
            promise.then(responseHandler).catch(cleanup);
        }
        catch (error) {
            /*
             * We get here if Background context is unreachable which occurs when:
             *  - extension was disabled
             *  - extension was uninstalled
             *  - extension was updated and this is the old instance of content script
             *
             * Any async operations can be ignored here, but sync ones should run to completion.
             *
             * Regular message passing errors are returned via rejected promise or runtime.lastError.
             */
            if (error.message === 'Extension context invalidated.') {
                console.log('Dark Reader: instance of old CS detected, cleaning up.');
                cleanup();
            }
            else {
                console.log('Dark Reader: unexpected error during message passing.');
            }
        }
    }
    function notifyOfColorScheme(isDark) {
        sendMessage({ type: MessageTypeCStoBG.COLOR_SCHEME_CHANGE, data: { isDark } });
    }
    function updateEventListeners() {
        notifyOfColorScheme(isSystemDarkModeEnabled());
        if (documentIsVisible()) {
            runColorSchemeChangeDetector(notifyOfColorScheme);
        }
        else {
            stopColorSchemeChangeDetector();
        }
    }
    setDocumentVisibilityListener(updateEventListeners);
    updateEventListeners();

})();
//# sourceMappingURL=data:application/json;charset=utf-8;base64,eyJ2ZXJzaW9uIjozLCJmaWxlIjoiY29sb3Itc2NoZW1lLXdhdGNoZXIuanMiLCJzb3VyY2VzIjpbIi4uLy4uLy4uLy4uLy4uLy4uLy4uL3NyYy91dGlscy9wbGF0Zm9ybS50cyIsIi4uLy4uLy4uLy4uLy4uLy4uLy4uL3NyYy91dGlscy9tZWRpYS1xdWVyeS50cyIsIi4uLy4uLy4uLy4uLy4uLy4uLy4uL3NyYy91dGlscy9tZXNzYWdlLnRzIiwiLi4vLi4vLi4vLi4vLi4vLi4vLi4vc3JjL3V0aWxzL3Zpc2liaWxpdHkudHMiLCIuLi8uLi8uLi8uLi8uLi8uLi8uLi9zcmMvaW5qZWN0L2NvbG9yLXNjaGVtZS13YXRjaGVyLnRzIl0sInNvdXJjZXNDb250ZW50IjpbImRlY2xhcmUgY29uc3QgX19DSFJPTUlVTV9NVjJfXzogYm9vbGVhbjtcbmRlY2xhcmUgY29uc3QgX19DSFJPTUlVTV9NVjNfXzogYm9vbGVhbjtcbmRlY2xhcmUgY29uc3QgX19GSVJFRk9YX01WMl9fOiBib29sZWFuO1xuZGVjbGFyZSBjb25zdCBfX1RIVU5ERVJCSVJEX186IGJvb2xlYW47XG5kZWNsYXJlIGNvbnN0IF9fVEVTVF9fOiBib29sZWFuO1xuXG5pbnRlcmZhY2UgVXNlckFnZW50RGF0YSB7XG4gICAgYnJhbmRzOiBBcnJheTx7XG4gICAgICAgIGJyYW5kOiBzdHJpbmc7XG4gICAgICAgIHZlcnNpb246IHN0cmluZztcbiAgICB9PjtcbiAgICBtb2JpbGU6IGJvb2xlYW47XG4gICAgcGxhdGZvcm06IHN0cmluZztcbn1cblxuZGVjbGFyZSBnbG9iYWwge1xuICAgIGludGVyZmFjZSBOYXZpZ2F0b3JJRCB7XG4gICAgICAgIHVzZXJBZ2VudERhdGE6IFVzZXJBZ2VudERhdGE7XG4gICAgfVxufVxuXG5kZWNsYXJlIGNvbnN0IF9fUExVU19fOiBib29sZWFuO1xuXG5jb25zdCBpc05hdmlnYXRvckRlZmluZWQgPSB0eXBlb2YgbmF2aWdhdG9yICE9PSAndW5kZWZpbmVkJztcbmNvbnN0IHVzZXJBZ2VudCA9IGlzTmF2aWdhdG9yRGVmaW5lZCA/IChuYXZpZ2F0b3IudXNlckFnZW50RGF0YSAmJiBBcnJheS5pc0FycmF5KG5hdmlnYXRvci51c2VyQWdlbnREYXRhLmJyYW5kcykpID9cbiAgICBuYXZpZ2F0b3IudXNlckFnZW50RGF0YS5icmFuZHMubWFwKChicmFuZCkgPT4gYCR7YnJhbmQuYnJhbmQudG9Mb3dlckNhc2UoKX0gJHticmFuZC52ZXJzaW9ufWApLmpvaW4oJyAnKSA6IG5hdmlnYXRvci51c2VyQWdlbnQudG9Mb3dlckNhc2UoKVxuICAgIDogJ3NvbWUgdXNlcmFnZW50JztcblxuY29uc3QgcGxhdGZvcm0gPSBpc05hdmlnYXRvckRlZmluZWQgPyAobmF2aWdhdG9yLnVzZXJBZ2VudERhdGEgJiYgdHlwZW9mIG5hdmlnYXRvci51c2VyQWdlbnREYXRhLnBsYXRmb3JtID09PSAnc3RyaW5nJykgP1xuICAgIG5hdmlnYXRvci51c2VyQWdlbnREYXRhLnBsYXRmb3JtLnRvTG93ZXJDYXNlKCkgOiBuYXZpZ2F0b3IucGxhdGZvcm0udG9Mb3dlckNhc2UoKVxuICAgIDogJ3NvbWUgcGxhdGZvcm0nO1xuXG4vLyBOb3RlOiBpZiB5b3UgYXJlIHVzaW5nIHRoZXNlIGNvbnN0YW50cyBpbiB0ZXN0cywgbWFrZSBzdXJlIHRoZXkgYXJlIG5vdCBjb21waWxlZCBvdXQgYnkgYWRkaW5nIF9fVEVTVF9fIHRvIHRoZW1cbmV4cG9ydCBjb25zdCBpc0Nocm9taXVtID0gX19DSFJPTUlVTV9NVjJfXyB8fCBfX0NIUk9NSVVNX01WM19fIHx8ICghX19GSVJFRk9YX01WMl9fICYmICFfX1RIVU5ERVJCSVJEX18gJiYgKHVzZXJBZ2VudC5pbmNsdWRlcygnY2hyb21lJykgfHwgdXNlckFnZW50LmluY2x1ZGVzKCdjaHJvbWl1bScpKSk7XG5leHBvcnQgY29uc3QgaXNGaXJlZm94ID0gX19GSVJFRk9YX01WMl9fIHx8IF9fVEhVTkRFUkJJUkRfXyB8fCAoKF9fVEVTVF9fIHx8ICghX19DSFJPTUlVTV9NVjJfXyAmJiAhX19DSFJPTUlVTV9NVjNfXykpICYmICh1c2VyQWdlbnQuaW5jbHVkZXMoJ2ZpcmVmb3gnKSB8fCB1c2VyQWdlbnQuaW5jbHVkZXMoJ3RodW5kZXJiaXJkJykgfHwgdXNlckFnZW50LmluY2x1ZGVzKCdsaWJyZXdvbGYnKSkpO1xuZXhwb3J0IGNvbnN0IGlzVml2YWxkaSA9IChfX0NIUk9NSVVNX01WMl9fIHx8IF9fQ0hST01JVU1fTVYzX18pICYmICghX19GSVJFRk9YX01WMl9fICYmICFfX1RIVU5ERVJCSVJEX18gJiYgdXNlckFnZW50LmluY2x1ZGVzKCd2aXZhbGRpJykpO1xuZXhwb3J0IGNvbnN0IGlzWWFCcm93c2VyID0gKF9fQ0hST01JVU1fTVYyX18gfHwgX19DSFJPTUlVTV9NVjNfXykgJiYgKCFfX0ZJUkVGT1hfTVYyX18gJiYgIV9fVEhVTkRFUkJJUkRfXyAmJiB1c2VyQWdlbnQuaW5jbHVkZXMoJ3lhYnJvd3NlcicpKTtcbmV4cG9ydCBjb25zdCBpc09wZXJhID0gKF9fQ0hST01JVU1fTVYyX18gfHwgX19DSFJPTUlVTV9NVjNfXykgJiYgKCFfX0ZJUkVGT1hfTVYyX18gJiYgIV9fVEhVTkRFUkJJUkRfXyAmJiAodXNlckFnZW50LmluY2x1ZGVzKCdvcHInKSB8fCB1c2VyQWdlbnQuaW5jbHVkZXMoJ29wZXJhJykpKTtcbmV4cG9ydCBjb25zdCBpc0VkZ2UgPSAoX19DSFJPTUlVTV9NVjJfXyB8fCBfX0NIUk9NSVVNX01WM19fKSAmJiAoIV9fRklSRUZPWF9NVjJfXyAmJiAhX19USFVOREVSQklSRF9fICYmIHVzZXJBZ2VudC5pbmNsdWRlcygnZWRnJykpO1xuZXhwb3J0IGNvbnN0IGlzU2FmYXJpID0gIV9fQ0hST01JVU1fTVYyX18gJiYgIV9fQ0hST01JVU1fTVYzX18gJiYgIV9fRklSRUZPWF9NVjJfXyAmJiAhX19USFVOREVSQklSRF9fICYmIHVzZXJBZ2VudC5pbmNsdWRlcygnc2FmYXJpJykgJiYgIWlzQ2hyb21pdW07XG5leHBvcnQgY29uc3QgaXNXaW5kb3dzID0gcGxhdGZvcm0uc3RhcnRzV2l0aCgnd2luJyk7XG5leHBvcnQgY29uc3QgaXNNYWNPUyA9IHBsYXRmb3JtLnN0YXJ0c1dpdGgoJ21hYycpO1xuZXhwb3J0IGNvbnN0IGlzTW9iaWxlID0gKGlzTmF2aWdhdG9yRGVmaW5lZCAmJiBuYXZpZ2F0b3IudXNlckFnZW50RGF0YSkgPyBuYXZpZ2F0b3IudXNlckFnZW50RGF0YS5tb2JpbGUgOiAodXNlckFnZW50LmluY2x1ZGVzKCdtb2JpbGUnKSB8fCAoX19QTFVTX18gJiYgdXNlckFnZW50LmluY2x1ZGVzKCdlZGdpb3MnKSkpO1xuZXhwb3J0IGNvbnN0IGlzU2hhZG93RG9tU3VwcG9ydGVkID0gdHlwZW9mIFNoYWRvd1Jvb3QgPT09ICdmdW5jdGlvbic7XG5leHBvcnQgY29uc3QgaXNNYXRjaE1lZGlhQ2hhbmdlRXZlbnRMaXN0ZW5lclN1cHBvcnRlZCA9IF9fQ0hST01JVU1fTVYzX18gfHwgKFxuICAgIHR5cGVvZiBNZWRpYVF1ZXJ5TGlzdCA9PT0gJ2Z1bmN0aW9uJyAmJlxuICAgIHR5cGVvZiBNZWRpYVF1ZXJ5TGlzdC5wcm90b3R5cGUuYWRkRXZlbnRMaXN0ZW5lciA9PT0gJ2Z1bmN0aW9uJ1xuKTtcbmV4cG9ydCBjb25zdCBpc0xheWVyUnVsZVN1cHBvcnRlZCA9IHR5cGVvZiBDU1NMYXllckJsb2NrUnVsZSA9PT0gJ2Z1bmN0aW9uJztcbi8vIFJldHVybiB0cnVlIGlmIGJyb3dzZXIgaXMga25vd24gdG8gaGF2ZSBhIGJ1ZyB3aXRoIE1lZGlhIFF1ZXJpZXMsIHNwZWNpZmljYWxseSBDaHJvbWl1bSBvbiBMaW51eCBhbmQgS2l3aSBvbiBBbmRyb2lkXG4vLyBXZSBhc3N1bWUgdGhhdCBpZiB3ZSBhcmUgb24gQW5kcm9pZCwgdGhlbiB3ZSBhcmUgcnVubmluZyBpbiBLaXdpIHNpbmNlIGl0IGlzIHRoZSBvbmx5IG1vYmlsZSBicm93c2VyIHdlIGNhbiBpbnN0YWxsIERhcmsgUmVhZGVyIGluXG5leHBvcnQgY29uc3QgaXNNYXRjaE1lZGlhQ2hhbmdlRXZlbnRMaXN0ZW5lckJ1Z2d5ID0gIV9fVEVTVF9fICYmICFfX0ZJUkVGT1hfTVYyX18gJiYgIV9fVEhVTkRFUkJJUkRfXyAmJiAoX19DSFJPTUlVTV9NVjJfXyB8fCBfX0NIUk9NSVVNX01WM19fKSAmJiAoXG4gICAgKChpc05hdmlnYXRvckRlZmluZWQgJiYgbmF2aWdhdG9yLnVzZXJBZ2VudERhdGEpICYmIFsnTGludXgnLCAnQW5kcm9pZCddLmluY2x1ZGVzKG5hdmlnYXRvci51c2VyQWdlbnREYXRhLnBsYXRmb3JtKSlcbiAgICB8fCBwbGF0Zm9ybS5zdGFydHNXaXRoKCdsaW51eCcpKTtcbi8vIE5vdGU6IG1ha2Ugc3VyZSB0aGF0IHRoaXMgdmFsdWUgbWF0Y2hlcyBtYW5pZmVzdC5qc29uIGtleXNcbmV4cG9ydCBjb25zdCBpc05vblBlcnNpc3RlbnQgPSAhX19GSVJFRk9YX01WMl9fICYmICFfX1RIVU5ERVJCSVJEX18gJiYgKF9fQ0hST01JVU1fTVYzX18gfHwgaXNTYWZhcmkpO1xuXG5leHBvcnQgY29uc3QgY2hyb21pdW1WZXJzaW9uID0gKCgpID0+IHtcbiAgICBjb25zdCBtID0gdXNlckFnZW50Lm1hdGNoKC9jaHJvbSg/OmV8aXVtKSg/OlxcL3wgKShbXiBdKykvKTtcbiAgICBpZiAobSAmJiBtWzFdKSB7XG4gICAgICAgIHJldHVybiBtWzFdO1xuICAgIH1cbiAgICByZXR1cm4gJyc7XG59KSgpO1xuXG5leHBvcnQgY29uc3QgZmlyZWZveFZlcnNpb24gPSAoKCkgPT4ge1xuICAgIGNvbnN0IG0gPSB1c2VyQWdlbnQubWF0Y2goLyg/OmZpcmVmb3h8bGlicmV3b2xmKSg/OlxcL3wgKShbXiBdKykvKTtcbiAgICBpZiAobSAmJiBtWzFdKSB7XG4gICAgICAgIHJldHVybiBtWzFdO1xuICAgIH1cbiAgICByZXR1cm4gJyc7XG59KSgpO1xuXG5leHBvcnQgY29uc3QgaXNEZWZpbmVkU2VsZWN0b3JTdXBwb3J0ZWQgPSAoKCkgPT4ge1xuICAgIHRyeSB7XG4gICAgICAgIGRvY3VtZW50LnF1ZXJ5U2VsZWN0b3IoJzpkZWZpbmVkJyk7XG4gICAgICAgIHJldHVybiB0cnVlO1xuICAgIH0gY2F0Y2ggKGVycikge1xuICAgICAgICByZXR1cm4gZmFsc2U7XG4gICAgfVxufSkoKTtcblxuZXhwb3J0IGZ1bmN0aW9uIGNvbXBhcmVDaHJvbWVWZXJzaW9ucygkYTogc3RyaW5nLCAkYjogc3RyaW5nKTogLTEgfCAwIHwgMSB7XG4gICAgY29uc3QgYSA9ICRhLnNwbGl0KCcuJykubWFwKCh4KSA9PiBwYXJzZUludCh4KSk7XG4gICAgY29uc3QgYiA9ICRiLnNwbGl0KCcuJykubWFwKCh4KSA9PiBwYXJzZUludCh4KSk7XG4gICAgZm9yIChsZXQgaSA9IDA7IGkgPCBhLmxlbmd0aDsgaSsrKSB7XG4gICAgICAgIGlmIChhW2ldICE9PSBiW2ldKSB7XG4gICAgICAgICAgICByZXR1cm4gYVtpXSA8IGJbaV0gPyAtMSA6IDE7XG4gICAgICAgIH1cbiAgICB9XG4gICAgcmV0dXJuIDA7XG59XG5cbmV4cG9ydCBjb25zdCBpc1hNTEh0dHBSZXF1ZXN0U3VwcG9ydGVkID0gdHlwZW9mIFhNTEh0dHBSZXF1ZXN0ID09PSAnZnVuY3Rpb24nO1xuXG5leHBvcnQgY29uc3QgaXNGZXRjaFN1cHBvcnRlZCA9IHR5cGVvZiBmZXRjaCA9PT0gJ2Z1bmN0aW9uJztcblxuZXhwb3J0IGNvbnN0IGlzQ1NTQ29sb3JTY2hlbWVQcm9wU3VwcG9ydGVkID0gX19DSFJPTUlVTV9NVjNfXyB8fCAoKCkgPT4ge1xuICAgIHRyeSB7XG4gICAgICAgIGlmICh0eXBlb2YgZG9jdW1lbnQgPT09ICd1bmRlZmluZWQnKSB7XG4gICAgICAgICAgICByZXR1cm4gZmFsc2U7XG4gICAgICAgIH1cbiAgICAgICAgY29uc3QgZWwgPSBkb2N1bWVudC5jcmVhdGVFbGVtZW50KCdkaXYnKTtcbiAgICAgICAgaWYgKCFlbCB8fCB0eXBlb2YgZWwuc3R5bGUgIT09ICdvYmplY3QnKSB7XG4gICAgICAgICAgICByZXR1cm4gZmFsc2U7XG4gICAgICAgIH1cbiAgICAgICAgaWYgKHR5cGVvZiBlbC5zdHlsZS5jb2xvclNjaGVtZSA9PT0gJ3N0cmluZycpIHtcbiAgICAgICAgICAgIHJldHVybiB0cnVlO1xuICAgICAgICB9XG5cbiAgICAgICAgLy8gVE9ETzogcmVtb3ZlIHRoZSBmb2xsb3dpbmcgY29kZSBhZnRlciBlbmZvcmNpbmcgc3Ryb25nIENTUCBpbiBhbGwgYnVpbGRzXG4gICAgICAgIC8vIFRoaXMgZmVhdHVyZSBkZXRlY3Rpb24gbWV0aG9kIHJlcXVpcmVzIHdlYWsgb3IgbWlzc2luZyBDU1AgaW4gbWFuaWZlc3QuanNvblxuICAgICAgICBlbC5zZXRBdHRyaWJ1dGUoJ3N0eWxlJywgJ2NvbG9yLXNjaGVtZTogZGFyaycpO1xuICAgICAgICByZXR1cm4gZWwuc3R5bGUuY29sb3JTY2hlbWUgPT09ICdkYXJrJztcbiAgICB9IGNhdGNoIChlKSB7XG4gICAgICAgIHJldHVybiBmYWxzZTtcbiAgICB9XG59KSgpO1xuIiwiaW1wb3J0IHtpc01hdGNoTWVkaWFDaGFuZ2VFdmVudExpc3RlbmVyU3VwcG9ydGVkfSBmcm9tICcuL3BsYXRmb3JtJztcblxuZGVjbGFyZSBjb25zdCBfX1RFU1RfXzogYm9vbGVhbjtcbmxldCBvdmVycmlkZTogYm9vbGVhbiB8IG51bGwgPSBudWxsO1xuXG5sZXQgcXVlcnk6IE1lZGlhUXVlcnlMaXN0IHwgbnVsbCA9IG51bGw7XG5jb25zdCBvbkNoYW5nZTogKHttYXRjaGVzfToge21hdGNoZXM6IGJvb2xlYW59KSA9PiB2b2lkID0gKHttYXRjaGVzfSkgPT4gbGlzdGVuZXJzLmZvckVhY2goKGxpc3RlbmVyKSA9PiBsaXN0ZW5lcihtYXRjaGVzKSk7XG5jb25zdCBsaXN0ZW5lcnMgPSBuZXcgU2V0PChpc0Rhcms6IGJvb2xlYW4pID0+IHZvaWQ+KCk7XG5cbmV4cG9ydCBmdW5jdGlvbiBydW5Db2xvclNjaGVtZUNoYW5nZURldGVjdG9yKGNhbGxiYWNrOiAoaXNEYXJrOiBib29sZWFuKSA9PiB2b2lkKTogdm9pZCB7XG4gICAgbGlzdGVuZXJzLmFkZChjYWxsYmFjayk7XG4gICAgaWYgKHF1ZXJ5KSB7XG4gICAgICAgIHJldHVybjtcbiAgICB9XG4gICAgcXVlcnkgPSBtYXRjaE1lZGlhKCcocHJlZmVycy1jb2xvci1zY2hlbWU6IGRhcmspJyk7XG4gICAgaWYgKGlzTWF0Y2hNZWRpYUNoYW5nZUV2ZW50TGlzdGVuZXJTdXBwb3J0ZWQpIHtcbiAgICAgICAgLy8gTWVkaWFRdWVyeUxpc3QgY2hhbmdlIGV2ZW50IGlzIG5vdCBjYW5jZWxsYWJsZSBhbmQgZG9lcyBub3QgYnViYmxlXG4gICAgICAgIHF1ZXJ5LmFkZEV2ZW50TGlzdGVuZXIoJ2NoYW5nZScsIG9uQ2hhbmdlKTtcbiAgICB9IGVsc2Uge1xuICAgICAgICBxdWVyeS5hZGRMaXN0ZW5lcihvbkNoYW5nZSk7XG4gICAgfVxufVxuXG5leHBvcnQgZnVuY3Rpb24gc3RvcENvbG9yU2NoZW1lQ2hhbmdlRGV0ZWN0b3IoKTogdm9pZCB7XG4gICAgaWYgKCFxdWVyeSB8fCAhb25DaGFuZ2UpIHtcbiAgICAgICAgcmV0dXJuO1xuICAgIH1cbiAgICBpZiAoaXNNYXRjaE1lZGlhQ2hhbmdlRXZlbnRMaXN0ZW5lclN1cHBvcnRlZCkge1xuICAgICAgICBxdWVyeS5yZW1vdmVFdmVudExpc3RlbmVyKCdjaGFuZ2UnLCBvbkNoYW5nZSk7XG4gICAgfSBlbHNlIHtcbiAgICAgICAgcXVlcnkucmVtb3ZlTGlzdGVuZXIob25DaGFuZ2UpO1xuICAgIH1cbiAgICBsaXN0ZW5lcnMuY2xlYXIoKTtcbiAgICBxdWVyeSA9IG51bGw7XG59XG5cbmV4cG9ydCBmdW5jdGlvbiBlbXVsYXRlQ29sb3JTY2hlbWUoY29sb3JTY2hlbWU6ICdsaWdodCcgfCAnZGFyaycpOiB2b2lkIHtcbiAgICBpZiAoX19URVNUX18pIHtcbiAgICAgICAgY29uc3QgaXNEYXJrID0gY29sb3JTY2hlbWUgPT09ICdkYXJrJztcbiAgICAgICAgb3ZlcnJpZGUgPSBpc0Rhcms7XG4gICAgICAgIGxpc3RlbmVycy5mb3JFYWNoKChsKSA9PiBsKGlzRGFyaykpO1xuICAgIH1cbn1cblxuZXhwb3J0IGNvbnN0IGlzU3lzdGVtRGFya01vZGVFbmFibGVkID0gKCk6IGJvb2xlYW4gPT4gKF9fVEVTVF9fICYmIHR5cGVvZiBvdmVycmlkZSA9PT0gJ2Jvb2xlYW4nKSA/IG92ZXJyaWRlIDogKHF1ZXJ5IHx8IG1hdGNoTWVkaWEoJyhwcmVmZXJzLWNvbG9yLXNjaGVtZTogZGFyayknKSkubWF0Y2hlcztcbiIsImV4cG9ydCBlbnVtIE1lc3NhZ2VUeXBlVUl0b0JHIHtcbiAgICBHRVRfREFUQSA9ICd1aS1iZy1nZXQtZGF0YScsXG4gICAgR0VUX0RFVlRPT0xTX0RBVEEgPSAndWktYmctZ2V0LWRldnRvb2xzLWRhdGEnLFxuICAgIFNVQlNDUklCRV9UT19DSEFOR0VTID0gJ3VpLWJnLXN1YnNjcmliZS10by1jaGFuZ2VzJyxcbiAgICBVTlNVQlNDUklCRV9GUk9NX0NIQU5HRVMgPSAndWktYmctdW5zdWJzY3JpYmUtZnJvbS1jaGFuZ2VzJyxcbiAgICBDSEFOR0VfU0VUVElOR1MgPSAndWktYmctY2hhbmdlLXNldHRpbmdzJyxcbiAgICBTRVRfVEhFTUUgPSAndWktYmctc2V0LXRoZW1lJyxcbiAgICBUT0dHTEVfQUNUSVZFX1RBQiA9ICd1aS1iZy10b2dnbGUtYWN0aXZlLXRhYicsXG4gICAgTUFSS19ORVdTX0FTX1JFQUQgPSAndWktYmctbWFyay1uZXdzLWFzLXJlYWQnLFxuICAgIE1BUktfTkVXU19BU19ESVNQTEFZRUQgPSAndWktYmctbWFyay1uZXdzLWFzLWRpc3BsYXllZCcsXG4gICAgTE9BRF9DT05GSUcgPSAndWktYmctbG9hZC1jb25maWcnLFxuICAgIEFQUExZX0RFVl9EWU5BTUlDX1RIRU1FX0ZJWEVTID0gJ3VpLWJnLWFwcGx5LWRldi1keW5hbWljLXRoZW1lLWZpeGVzJyxcbiAgICBSRVNFVF9ERVZfRFlOQU1JQ19USEVNRV9GSVhFUyA9ICd1aS1iZy1yZXNldC1kZXYtZHluYW1pYy10aGVtZS1maXhlcycsXG4gICAgQVBQTFlfREVWX0lOVkVSU0lPTl9GSVhFUyA9ICd1aS1iZy1hcHBseS1kZXYtaW52ZXJzaW9uLWZpeGVzJyxcbiAgICBSRVNFVF9ERVZfSU5WRVJTSU9OX0ZJWEVTID0gJ3VpLWJnLXJlc2V0LWRldi1pbnZlcnNpb24tZml4ZXMnLFxuICAgIEFQUExZX0RFVl9TVEFUSUNfVEhFTUVTID0gJ3VpLWJnLWFwcGx5LWRldi1zdGF0aWMtdGhlbWVzJyxcbiAgICBSRVNFVF9ERVZfU1RBVElDX1RIRU1FUyA9ICd1aS1iZy1yZXNldC1kZXYtc3RhdGljLXRoZW1lcycsXG4gICAgU1RBUlRfQUNUSVZBVElPTiA9ICd1aS1iZy1zdGFydC1hY3RpdmF0aW9uJyxcbiAgICBSRVNFVF9BQ1RJVkFUSU9OID0gJ3VpLWJnLXJlc2V0LWFjdGl2YXRpb24nLFxuICAgIENPTE9SX1NDSEVNRV9DSEFOR0UgPSAndWktYmctY29sb3Itc2NoZW1lLWNoYW5nZScsXG4gICAgSElERV9ISUdITElHSFRTID0gJ3VpLWJnLWhpZGUtaGlnaGxpZ2h0cydcbn1cblxuZXhwb3J0IGVudW0gTWVzc2FnZVR5cGVCR3RvVUkge1xuICAgIENIQU5HRVMgPSAnYmctdWktY2hhbmdlcydcbn1cblxuZXhwb3J0IGVudW0gRGVidWdNZXNzYWdlVHlwZUJHdG9VSSB7XG4gICAgQ1NTX1VQREFURSA9ICdkZWJ1Zy1iZy11aS1jc3MtdXBkYXRlJyxcbiAgICBVUERBVEUgPSAnZGVidWctYmctdWktdXBkYXRlJ1xufVxuXG5leHBvcnQgZW51bSBNZXNzYWdlVHlwZUJHdG9DUyB7XG4gICAgQUREX0NTU19GSUxURVIgPSAnYmctY3MtYWRkLWNzcy1maWx0ZXInLFxuICAgIEFERF9EWU5BTUlDX1RIRU1FID0gJ2JnLWNzLWFkZC1keW5hbWljLXRoZW1lJyxcbiAgICBBRERfU1RBVElDX1RIRU1FID0gJ2JnLWNzLWFkZC1zdGF0aWMtdGhlbWUnLFxuICAgIEFERF9TVkdfRklMVEVSID0gJ2JnLWNzLWFkZC1zdmctZmlsdGVyJyxcbiAgICBDTEVBTl9VUCA9ICdiZy1jcy1jbGVhbi11cCcsXG4gICAgRkVUQ0hfUkVTUE9OU0UgPSAnYmctY3MtZmV0Y2gtcmVzcG9uc2UnLFxuICAgIFVOU1VQUE9SVEVEX1NFTkRFUiA9ICdiZy1jcy11bnN1cHBvcnRlZC1zZW5kZXInXG59XG5cbmV4cG9ydCBlbnVtIERlYnVnTWVzc2FnZVR5cGVCR3RvQ1Mge1xuICAgIFJFTE9BRCA9ICdkZWJ1Zy1iZy1jcy1yZWxvYWQnXG59XG5cbmV4cG9ydCBlbnVtIE1lc3NhZ2VUeXBlQ1N0b0JHIHtcbiAgICBDT0xPUl9TQ0hFTUVfQ0hBTkdFID0gJ2NzLWJnLWNvbG9yLXNjaGVtZS1jaGFuZ2UnLFxuICAgIERBUktfVEhFTUVfREVURUNURUQgPSAnY3MtYmctZGFyay10aGVtZS1kZXRlY3RlZCcsXG4gICAgREFSS19USEVNRV9OT1RfREVURUNURUQgPSAnY3MtYmctZGFyay10aGVtZS1ub3QtZGV0ZWN0ZWQnLFxuICAgIEZFVENIID0gJ2NzLWJnLWZldGNoJyxcbiAgICBET0NVTUVOVF9DT05ORUNUID0gJ2NzLWJnLWRvY3VtZW50LWNvbm5lY3QnLFxuICAgIERPQ1VNRU5UX0ZPUkdFVCA9ICdjcy1iZy1kb2N1bWVudC1mb3JnZXQnLFxuICAgIERPQ1VNRU5UX0ZSRUVaRSA9ICdjcy1iZy1kb2N1bWVudC1mcmVlemUnLFxuICAgIERPQ1VNRU5UX1JFU1VNRSA9ICdjcy1iZy1kb2N1bWVudC1yZXN1bWUnXG59XG5cbmV4cG9ydCBlbnVtIERlYnVnTWVzc2FnZVR5cGVDU3RvQkcge1xuICAgIExPRyA9ICdkZWJ1Zy1jcy1iZy1sb2cnXG59XG5cbmV4cG9ydCBlbnVtIE1lc3NhZ2VUeXBlQ1N0b1VJIHtcbiAgICBFWFBPUlRfQ1NTX1JFU1BPTlNFID0gJ2NzLXVpLWV4cG9ydC1jc3MtcmVzcG9uc2UnXG59XG5cbmV4cG9ydCBlbnVtIE1lc3NhZ2VUeXBlVUl0b0NTIHtcbiAgICBFWFBPUlRfQ1NTID0gJ3VpLWNzLWV4cG9ydC1jc3MnXG59XG4iLCIvKipcbiAqIFRoZSBmb2xsb3dpbmcgY29kZSBjb250YWlucyBhIHdvcmthcm91bmQgZm9yIGV4dGVuc2lvbnMgZGVzaWduZWQgdG8gcHJldmVudCBwYWdlIGZyb20ga25vd2luZyB3aGVuIGl0IGlzIGhpZGRlblxuICogR2l0SHViIGlzc3VlOiBodHRwczovL2dpdGh1Yi5jb20vZGFya3JlYWRlci9kYXJrcmVhZGVyL2lzc3Vlcy8xMDAwNFxuICogR2l0SHViIFBSOiBodHRwczovL2dpdGh1Yi5jb20vZGFya3JlYWRlci9kYXJrcmVhZGVyL3B1bGwvMTAwNDdcbiAqXG4gKiBEdWUgdG8gdGhlIGludGVudGlvbmFsIGJyZWFrYWdlIGludHJvZHVjZWQgYnkgdGhlc2UgZXh0ZW5zaW9ucywgdGhpcyB1dGlsaXR5IG1pZ2h0IGluY29ycmVjdGx5IHJlcG9ydCB0aGF0IGRvY3VtZW50XG4gKiBpcyB2aXNpYmxlIHdoaWxlIGl0IGlzIG5vdCwgYnV0IGl0IHdpbGwgbmV2ZXIgcmVwb3J0IGRvY3VtZW50IGFzIGhpZGRlbiB3aGlsZSBpdCBpcyB2aXNpYmxlLlxuICpcbiAqIFRoaXMgY29kZSBleHBsb2l0cyB0aGUgZmFjdCB0aGF0IG1vc3Qgc3VjaCBleHRlbnNpb25zIGJsb2NrIG9ubHkgYSBzdWJzZXQgb2YgUGFnZSBMaWZlY3ljbGUgQVBJLFxuICogd2hpY2ggbm90aWZpZXMgcGFnZSBvZiBiZWluZyBoaWRkZW4gYnV0IG5vdCBvZiBiZWluZyBzaG93biwgd2hpbGUgRGFyayBSZWFkZXIgcmVhbGx5IGNhcmVzIG9ubHkgYWJvdXRcbiAqIHBhZ2UgYmVpbmcgc2hvd24uXG4gKiBTcGVjaWZpY2FsbHk6XG4gKiAgLSBleHRlbnNpb25zIGJsb2NrIHZpc2liaWxpdHljaGFuZ2UgYW5kIGJsdXIgZXZlbnRcbiAqICAtIGV4dGVuc2lvbnMgZG8gbm90IGJsb2NrIGZvY3VzIGV2ZW50OyBicm93c2VycyBkZWxpdmVyIGZvY3VzIGV2ZW50IHdoZW4gdXNlciBzd2l0Y2hlcyB0b1xuICogICAgYSBwcmV2aW91c2x5IGhpZGRlbiB0YWIgb3IgcHJldmlvdXNseSBoaWRkZW4gd2luZG93IChhc3N1bWluZyBEZXZUb29scyBhcmUgY2xvc2VkIHNvIHdpbmRvdyBnZXRzIHRoZSBmb2N1cylcbiAqICAgIGlmIGRvY3VtZW50IGhhcyBmb2N1cywgdGhlbiB3ZSBjYW4gYXNzdW1lIHRoYXQgaXQgaXMgdmlzaWJsZVxuICogIC0gc29tZSBleHRlbnNpb25zIG92ZXJ3cml0ZSBkb2N1bWVudC5oaWRkZW4gYnV0IG5vdCBkb2N1bWVudC52aXNpYmlsaXR5U3RhdGVcbiAqICAtIEZpcmVmb3ggaGFzIGEgYnVnOiBpZiBleHRlbnNpb24gb3ZlcndyaXRlcyBkb2N1bWVudC5oaWRkZW4gYW5kIGRvY3VtZW50LnZpc2liaWxpdHlTdGF0ZSB2aWEgT2JqZWN0LmRlZmluZVByb3BlcnR5LFxuICogICAgdGhlbiBGaXJlZm94IHdpbGwgcmVzZXQgdGhlbSB0byB0cnVlIGFuZCAnaGlkZGVuJyB3aGVuIHRhYiBpcyBhY3RpdmF0ZWQsIGJ1dCBkb2N1bWVudC5oYXNGb2N1cygpIHdpbGwgYmUgdHJ1ZVxuICogIC0gU2FmYXJpIHN1cHBvcnRzIGRvY3VtZW50LnZpc2liaWxpdHlTdGF0ZSA9PT0gJ3ByZXJlbmRlcicgd2hpY2ggbWFrZXMgZG9jdW1lbnQuaGlkZGVuID09PSB0cnVlIGV2ZW4gd2hlbiBkb2N1bWVudFxuICogICAgaXMgdmlzaWJsZSB0byB0aGUgdXNlclxuICpcbiAqIE5vdGU6IFRoaXMgdXRpbGl0eSBzdXBwb3J0cyBhZGRpbmcgb25seSBvbmUgY2FsbGJhY2sgc2luY2UgY3VycmVudGx5IGNhbGxpbmcgY29kZSBzZXRzIG9ubHkgb25lIGxpc3RlbmVyIGFuZCBGaXJlZm94XG4gKiBoYXMgaXNzdWVzIG9wdGltaXppbmcgY29kZSB3aXRoIG11bHRpcGxlIGNhbGxiYWNrcyBzdG9yZWQgaW4gYXJyYXkgb3IgaW4gYSBzZXQuXG4gKi9cblxubGV0IGRvY3VtZW50VmlzaWJpbGl0eUxpc3RlbmVyOiAoKCkgPT4gdm9pZCkgfCBudWxsID0gbnVsbDtcblxubGV0IGRvY3VtZW50SXNWaXNpYmxlXyA9ICFkb2N1bWVudC5oaWRkZW47XG5cbi8vIFRPRE86IHVzZSBFdmVudExpc3RlbmVyT3B0aW9ucyBjbGFzcyBvbmNlIGl0IGlzIHVwZGF0ZWRcbmNvbnN0IGxpc3RlbmVyT3B0aW9uczogYW55ID0ge1xuICAgIGNhcHR1cmU6IHRydWUsXG4gICAgcGFzc2l2ZTogdHJ1ZSxcbn07XG5cbmZ1bmN0aW9uIHdhdGNoRm9yRG9jdW1lbnRWaXNpYmlsaXR5KCk6IHZvaWQge1xuICAgIGRvY3VtZW50LmFkZEV2ZW50TGlzdGVuZXIoJ3Zpc2liaWxpdHljaGFuZ2UnLCBkb2N1bWVudFZpc2liaWxpdHlMaXN0ZW5lciEsIGxpc3RlbmVyT3B0aW9ucyk7XG4gICAgd2luZG93LmFkZEV2ZW50TGlzdGVuZXIoJ3BhZ2VzaG93JywgZG9jdW1lbnRWaXNpYmlsaXR5TGlzdGVuZXIhLCBsaXN0ZW5lck9wdGlvbnMpO1xuICAgIHdpbmRvdy5hZGRFdmVudExpc3RlbmVyKCdmb2N1cycsIGRvY3VtZW50VmlzaWJpbGl0eUxpc3RlbmVyISwgbGlzdGVuZXJPcHRpb25zKTtcbn1cblxuZnVuY3Rpb24gc3RvcFdhdGNoaW5nRm9yRG9jdW1lbnRWaXNpYmlsaXR5KCk6IHZvaWQge1xuICAgIGRvY3VtZW50LnJlbW92ZUV2ZW50TGlzdGVuZXIoJ3Zpc2liaWxpdHljaGFuZ2UnLCBkb2N1bWVudFZpc2liaWxpdHlMaXN0ZW5lciEsIGxpc3RlbmVyT3B0aW9ucyk7XG4gICAgd2luZG93LnJlbW92ZUV2ZW50TGlzdGVuZXIoJ3BhZ2VzaG93JywgZG9jdW1lbnRWaXNpYmlsaXR5TGlzdGVuZXIhLCBsaXN0ZW5lck9wdGlvbnMpO1xuICAgIHdpbmRvdy5yZW1vdmVFdmVudExpc3RlbmVyKCdmb2N1cycsIGRvY3VtZW50VmlzaWJpbGl0eUxpc3RlbmVyISwgbGlzdGVuZXJPcHRpb25zKTtcbn1cblxuZXhwb3J0IGZ1bmN0aW9uIHNldERvY3VtZW50VmlzaWJpbGl0eUxpc3RlbmVyKGNhbGxiYWNrOiAoKSA9PiB2b2lkKTogdm9pZCB7XG4gICAgY29uc3QgYWxyZWFkeVdhdGNoaW5nID0gQm9vbGVhbihkb2N1bWVudFZpc2liaWxpdHlMaXN0ZW5lcik7XG4gICAgZG9jdW1lbnRWaXNpYmlsaXR5TGlzdGVuZXIgPSAoKSA9PiB7XG4gICAgICAgIGlmICghZG9jdW1lbnQuaGlkZGVuKSB7XG4gICAgICAgICAgICByZW1vdmVEb2N1bWVudFZpc2liaWxpdHlMaXN0ZW5lcigpO1xuICAgICAgICAgICAgY2FsbGJhY2soKTtcbiAgICAgICAgICAgIGRvY3VtZW50SXNWaXNpYmxlXyA9IHRydWU7XG4gICAgICAgIH1cbiAgICB9O1xuICAgIGlmICghYWxyZWFkeVdhdGNoaW5nKSB7XG4gICAgICAgIHdhdGNoRm9yRG9jdW1lbnRWaXNpYmlsaXR5KCk7XG4gICAgfVxufVxuXG5leHBvcnQgZnVuY3Rpb24gcmVtb3ZlRG9jdW1lbnRWaXNpYmlsaXR5TGlzdGVuZXIoKTogdm9pZCB7XG4gICAgc3RvcFdhdGNoaW5nRm9yRG9jdW1lbnRWaXNpYmlsaXR5KCk7XG4gICAgZG9jdW1lbnRWaXNpYmlsaXR5TGlzdGVuZXIgPSBudWxsO1xufVxuXG5leHBvcnQgZnVuY3Rpb24gZG9jdW1lbnRJc1Zpc2libGUoKTogYm9vbGVhbiB7XG4gICAgcmV0dXJuIGRvY3VtZW50SXNWaXNpYmxlXztcbn1cbiIsImltcG9ydCB0eXBlIHtNZXNzYWdlQkd0b0NTLCBNZXNzYWdlQ1N0b0JHfSBmcm9tICcuLi9kZWZpbml0aW9ucyc7XG5pbXBvcnQge2lzU3lzdGVtRGFya01vZGVFbmFibGVkLCBydW5Db2xvclNjaGVtZUNoYW5nZURldGVjdG9yLCBzdG9wQ29sb3JTY2hlbWVDaGFuZ2VEZXRlY3Rvcn0gZnJvbSAnLi4vdXRpbHMvbWVkaWEtcXVlcnknO1xuaW1wb3J0IHtNZXNzYWdlVHlwZUNTdG9CR30gZnJvbSAnLi4vdXRpbHMvbWVzc2FnZSc7XG5pbXBvcnQge3NldERvY3VtZW50VmlzaWJpbGl0eUxpc3RlbmVyLCBkb2N1bWVudElzVmlzaWJsZSwgcmVtb3ZlRG9jdW1lbnRWaXNpYmlsaXR5TGlzdGVuZXJ9IGZyb20gJy4uL3V0aWxzL3Zpc2liaWxpdHknO1xuXG5mdW5jdGlvbiBjbGVhbnVwKCkge1xuICAgIHN0b3BDb2xvclNjaGVtZUNoYW5nZURldGVjdG9yKCk7XG4gICAgcmVtb3ZlRG9jdW1lbnRWaXNpYmlsaXR5TGlzdGVuZXIoKTtcbn1cblxuZnVuY3Rpb24gc2VuZE1lc3NhZ2UobWVzc2FnZTogTWVzc2FnZUNTdG9CRyk6IHZvaWQge1xuICAgIGNvbnN0IHJlc3BvbnNlSGFuZGxlciA9IChyZXNwb25zZTogTWVzc2FnZUJHdG9DUyB8ICd1bnN1cHBvcnRlZFNlbmRlcicgfCB1bmRlZmluZWQpID0+IHtcbiAgICAgICAgLy8gVml2YWxkaSBidWcgd29ya2Fyb3VuZC4gU2VlIFRhYk1hbmFnZXIgZm9yIGRldGFpbHMuXG4gICAgICAgIGlmIChyZXNwb25zZSA9PT0gJ3Vuc3VwcG9ydGVkU2VuZGVyJykge1xuICAgICAgICAgICAgY2xlYW51cCgpO1xuICAgICAgICB9XG4gICAgfTtcblxuICAgIHRyeSB7XG4gICAgICAgIGNvbnN0IHByb21pc2UgPSBjaHJvbWUucnVudGltZS5zZW5kTWVzc2FnZTxNZXNzYWdlQ1N0b0JHLCBNZXNzYWdlQkd0b0NTIHwgJ3Vuc3VwcG9ydGVkU2VuZGVyJz4obWVzc2FnZSk7XG4gICAgICAgIHByb21pc2UudGhlbihyZXNwb25zZUhhbmRsZXIpLmNhdGNoKGNsZWFudXApO1xuICAgIH0gY2F0Y2ggKGVycm9yKSB7XG4gICAgICAgIC8qXG4gICAgICAgICAqIFdlIGdldCBoZXJlIGlmIEJhY2tncm91bmQgY29udGV4dCBpcyB1bnJlYWNoYWJsZSB3aGljaCBvY2N1cnMgd2hlbjpcbiAgICAgICAgICogIC0gZXh0ZW5zaW9uIHdhcyBkaXNhYmxlZFxuICAgICAgICAgKiAgLSBleHRlbnNpb24gd2FzIHVuaW5zdGFsbGVkXG4gICAgICAgICAqICAtIGV4dGVuc2lvbiB3YXMgdXBkYXRlZCBhbmQgdGhpcyBpcyB0aGUgb2xkIGluc3RhbmNlIG9mIGNvbnRlbnQgc2NyaXB0XG4gICAgICAgICAqXG4gICAgICAgICAqIEFueSBhc3luYyBvcGVyYXRpb25zIGNhbiBiZSBpZ25vcmVkIGhlcmUsIGJ1dCBzeW5jIG9uZXMgc2hvdWxkIHJ1biB0byBjb21wbGV0aW9uLlxuICAgICAgICAgKlxuICAgICAgICAgKiBSZWd1bGFyIG1lc3NhZ2UgcGFzc2luZyBlcnJvcnMgYXJlIHJldHVybmVkIHZpYSByZWplY3RlZCBwcm9taXNlIG9yIHJ1bnRpbWUubGFzdEVycm9yLlxuICAgICAgICAgKi9cbiAgICAgICAgaWYgKGVycm9yLm1lc3NhZ2UgPT09ICdFeHRlbnNpb24gY29udGV4dCBpbnZhbGlkYXRlZC4nKSB7XG4gICAgICAgICAgICBjb25zb2xlLmxvZygnRGFyayBSZWFkZXI6IGluc3RhbmNlIG9mIG9sZCBDUyBkZXRlY3RlZCwgY2xlYW5pbmcgdXAuJyk7XG4gICAgICAgICAgICBjbGVhbnVwKCk7XG4gICAgICAgIH0gZWxzZSB7XG4gICAgICAgICAgICBjb25zb2xlLmxvZygnRGFyayBSZWFkZXI6IHVuZXhwZWN0ZWQgZXJyb3IgZHVyaW5nIG1lc3NhZ2UgcGFzc2luZy4nKTtcbiAgICAgICAgfVxuICAgIH1cbn1cblxuZnVuY3Rpb24gbm90aWZ5T2ZDb2xvclNjaGVtZShpc0Rhcms6IGJvb2xlYW4pOiB2b2lkIHtcbiAgICBzZW5kTWVzc2FnZSh7dHlwZTogTWVzc2FnZVR5cGVDU3RvQkcuQ09MT1JfU0NIRU1FX0NIQU5HRSwgZGF0YToge2lzRGFya319KTtcbn1cblxuZnVuY3Rpb24gdXBkYXRlRXZlbnRMaXN0ZW5lcnMoKTogdm9pZCB7XG4gICAgbm90aWZ5T2ZDb2xvclNjaGVtZShpc1N5c3RlbURhcmtNb2RlRW5hYmxlZCgpKTtcbiAgICBpZiAoZG9jdW1lbnRJc1Zpc2libGUoKSkge1xuICAgICAgICBydW5Db2xvclNjaGVtZUNoYW5nZURldGVjdG9yKG5vdGlmeU9mQ29sb3JTY2hlbWUpO1xuICAgIH0gZWxzZSB7XG4gICAgICAgIHN0b3BDb2xvclNjaGVtZUNoYW5nZURldGVjdG9yKCk7XG4gICAgfVxufVxuXG5zZXREb2N1bWVudFZpc2liaWxpdHlMaXN0ZW5lcih1cGRhdGVFdmVudExpc3RlbmVycyk7XG51cGRhdGVFdmVudExpc3RlbmVycygpO1xuIl0sIm5hbWVzIjpbXSwibWFwcGluZ3MiOiI7OztJQXVCQSxNQUFNLGtCQUFrQixHQUFHLE9BQU8sU0FBUyxLQUFLLFdBQVc7SUFDM0QsTUFBTSxTQUFTLEdBQUcsa0JBQWtCLEdBQUcsQ0FBQyxTQUFTLENBQUMsYUFBYSxJQUFJLEtBQUssQ0FBQyxPQUFPLENBQUMsU0FBUyxDQUFDLGFBQWEsQ0FBQyxNQUFNLENBQUM7SUFDNUcsSUFBQSxTQUFTLENBQUMsYUFBYSxDQUFDLE1BQU0sQ0FBQyxHQUFHLENBQUMsQ0FBQyxLQUFLLEtBQUssQ0FBQSxFQUFHLEtBQUssQ0FBQyxLQUFLLENBQUMsV0FBVyxFQUFFLENBQUEsQ0FBQSxFQUFJLEtBQUssQ0FBQyxPQUFPLENBQUEsQ0FBRSxDQUFDLENBQUMsSUFBSSxDQUFDLEdBQUcsQ0FBQyxHQUFHLFNBQVMsQ0FBQyxTQUFTLENBQUMsV0FBVztVQUN4SSxnQkFBZ0I7SUFFdEIsTUFBTSxRQUFRLEdBQUcsa0JBQWtCLEdBQUcsQ0FBQyxTQUFTLENBQUMsYUFBYSxJQUFJLE9BQU8sU0FBUyxDQUFDLGFBQWEsQ0FBQyxRQUFRLEtBQUssUUFBUTtJQUNsSCxJQUFBLFNBQVMsQ0FBQyxhQUFhLENBQUMsUUFBUSxDQUFDLFdBQVcsRUFBRSxHQUFHLFNBQVMsQ0FBQyxRQUFRLENBQUMsV0FBVztVQUM3RSxlQUFlO0lBSzhDLENBQXlDLFNBQVMsQ0FBQyxRQUFRLENBQUMsU0FBUyxDQUFDO0lBQ3BFLENBQXlDLFNBQVMsQ0FBQyxRQUFRLENBQUMsV0FBVyxDQUFDO0lBQzVFLENBQXlDLENBQUMsU0FBUyxDQUFDLFFBQVEsQ0FBQyxLQUFLLENBQUMsSUFBSSxTQUFTLENBQUMsUUFBUSxDQUFDLE9BQU8sQ0FBQyxDQUFDO0lBQ3BHLENBQXlDLFNBQVMsQ0FBQyxRQUFRLENBQUMsS0FBSyxDQUFDO0lBRXpHLFFBQVEsQ0FBQyxVQUFVLENBQUMsS0FBSztJQUMzQixRQUFRLENBQUMsVUFBVSxDQUFDLEtBQUs7SUFDeEIsQ0FBQyxrQkFBa0IsSUFBSSxTQUFTLENBQUMsYUFBYSxJQUFJLFNBQVMsQ0FBQyxhQUFhLENBQUMsTUFBTSxJQUFJLFNBQVMsQ0FBQyxRQUFRLENBQUMsUUFBUSxDQUFDLEtBQUssS0FBd0MsQ0FBQztJQU90TDtJQUNBO0lBQ21KLENBQy9JLENBQUMsQ0FBQyxrQkFBa0IsSUFBSSxTQUFTLENBQUMsYUFBYSxLQUFLLENBQUMsT0FBTyxFQUFFLFNBQVMsQ0FBQyxDQUFDLFFBQVEsQ0FBQyxTQUFTLENBQUMsYUFBYSxDQUFDLFFBQVEsQ0FBQztJQUNoSCxPQUFBLFFBQVEsQ0FBQyxVQUFVLENBQUMsT0FBTyxDQUFDO0lBSUosQ0FBQyxNQUFLO1FBQ2pDLE1BQU0sQ0FBQyxHQUFHLFNBQVMsQ0FBQyxLQUFLLENBQUMsK0JBQStCLENBQUM7SUFDMUQsSUFBQSxJQUFJLENBQUMsSUFBSSxDQUFDLENBQUMsQ0FBQyxDQUFDLEVBQUU7SUFDWCxRQUFBLE9BQU8sQ0FBQyxDQUFDLENBQUMsQ0FBQztRQUNmO0lBQ0EsSUFBQSxPQUFPLEVBQUU7SUFDYixDQUFDO0lBRTZCLENBQUMsTUFBSztRQUNoQyxNQUFNLENBQUMsR0FBRyxTQUFTLENBQUMsS0FBSyxDQUFDLHNDQUFzQyxDQUFDO0lBQ2pFLElBQUEsSUFBSSxDQUFDLElBQUksQ0FBQyxDQUFDLENBQUMsQ0FBQyxFQUFFO0lBQ1gsUUFBQSxPQUFPLENBQUMsQ0FBQyxDQUFDLENBQUM7UUFDZjtJQUNBLElBQUEsT0FBTyxFQUFFO0lBQ2IsQ0FBQztJQUV5QyxDQUFDLE1BQUs7SUFDNUMsSUFBQSxJQUFJO0lBQ0EsUUFBQSxRQUFRLENBQUMsYUFBYSxDQUFDLFVBQVUsQ0FBQztJQUNsQyxRQUFBLE9BQU8sSUFBSTtRQUNmO1FBQUUsT0FBTyxHQUFHLEVBQUU7SUFDVixRQUFBLE9BQU8sS0FBSztRQUNoQjtJQUNKLENBQUM7O0lDM0VELElBQUksS0FBSyxHQUEwQixJQUFJO0lBQ3ZDLE1BQU0sUUFBUSxHQUE0QyxDQUFDLEVBQUMsT0FBTyxFQUFDLEtBQUssU0FBUyxDQUFDLE9BQU8sQ0FBQyxDQUFDLFFBQVEsS0FBSyxRQUFRLENBQUMsT0FBTyxDQUFDLENBQUM7SUFDM0gsTUFBTSxTQUFTLEdBQUcsSUFBSSxHQUFHLEVBQTZCO0lBRWhELFNBQVUsNEJBQTRCLENBQUMsUUFBbUMsRUFBQTtJQUM1RSxJQUFBLFNBQVMsQ0FBQyxHQUFHLENBQUMsUUFBUSxDQUFDO1FBQ3ZCLElBQUksS0FBSyxFQUFFO1lBQ1A7UUFDSjtJQUNBLElBQUEsS0FBSyxHQUFHLFVBQVUsQ0FBQyw4QkFBOEIsQ0FBQztRQUNKOztJQUUxQyxRQUFBLEtBQUssQ0FBQyxnQkFBZ0IsQ0FBQyxRQUFRLEVBQUUsUUFBUSxDQUFDO1FBQzlDO0lBR0o7YUFFZ0IsNkJBQTZCLEdBQUE7SUFDekMsSUFBQSxJQUFJLENBQUMsS0FBSyxJQUFJLENBQUMsUUFBUSxFQUFFO1lBQ3JCO1FBQ0o7UUFDOEM7SUFDMUMsUUFBQSxLQUFLLENBQUMsbUJBQW1CLENBQUMsUUFBUSxFQUFFLFFBQVEsQ0FBQztRQUNqRDtRQUdBLFNBQVMsQ0FBQyxLQUFLLEVBQUU7UUFDakIsS0FBSyxHQUFHLElBQUk7SUFDaEI7SUFVTyxNQUFNLHVCQUF1QixHQUFHLE1BQXdFLENBQUMsS0FBSyxJQUFJLFVBQVUsQ0FBQyw4QkFBOEIsQ0FBQyxFQUFFLE9BQU87O0lDNUM1SyxJQUFZLGlCQXFCWDtJQXJCRCxDQUFBLFVBQVksaUJBQWlCLEVBQUE7SUFDekIsSUFBQSxpQkFBQSxDQUFBLFVBQUEsQ0FBQSxHQUFBLGdCQUEyQjtJQUMzQixJQUFBLGlCQUFBLENBQUEsbUJBQUEsQ0FBQSxHQUFBLHlCQUE2QztJQUM3QyxJQUFBLGlCQUFBLENBQUEsc0JBQUEsQ0FBQSxHQUFBLDRCQUFtRDtJQUNuRCxJQUFBLGlCQUFBLENBQUEsMEJBQUEsQ0FBQSxHQUFBLGdDQUEyRDtJQUMzRCxJQUFBLGlCQUFBLENBQUEsaUJBQUEsQ0FBQSxHQUFBLHVCQUF5QztJQUN6QyxJQUFBLGlCQUFBLENBQUEsV0FBQSxDQUFBLEdBQUEsaUJBQTZCO0lBQzdCLElBQUEsaUJBQUEsQ0FBQSxtQkFBQSxDQUFBLEdBQUEseUJBQTZDO0lBQzdDLElBQUEsaUJBQUEsQ0FBQSxtQkFBQSxDQUFBLEdBQUEseUJBQTZDO0lBQzdDLElBQUEsaUJBQUEsQ0FBQSx3QkFBQSxDQUFBLEdBQUEsOEJBQXVEO0lBQ3ZELElBQUEsaUJBQUEsQ0FBQSxhQUFBLENBQUEsR0FBQSxtQkFBaUM7SUFDakMsSUFBQSxpQkFBQSxDQUFBLCtCQUFBLENBQUEsR0FBQSxxQ0FBcUU7SUFDckUsSUFBQSxpQkFBQSxDQUFBLCtCQUFBLENBQUEsR0FBQSxxQ0FBcUU7SUFDckUsSUFBQSxpQkFBQSxDQUFBLDJCQUFBLENBQUEsR0FBQSxpQ0FBNkQ7SUFDN0QsSUFBQSxpQkFBQSxDQUFBLDJCQUFBLENBQUEsR0FBQSxpQ0FBNkQ7SUFDN0QsSUFBQSxpQkFBQSxDQUFBLHlCQUFBLENBQUEsR0FBQSwrQkFBeUQ7SUFDekQsSUFBQSxpQkFBQSxDQUFBLHlCQUFBLENBQUEsR0FBQSwrQkFBeUQ7SUFDekQsSUFBQSxpQkFBQSxDQUFBLGtCQUFBLENBQUEsR0FBQSx3QkFBMkM7SUFDM0MsSUFBQSxpQkFBQSxDQUFBLGtCQUFBLENBQUEsR0FBQSx3QkFBMkM7SUFDM0MsSUFBQSxpQkFBQSxDQUFBLHFCQUFBLENBQUEsR0FBQSwyQkFBaUQ7SUFDakQsSUFBQSxpQkFBQSxDQUFBLGlCQUFBLENBQUEsR0FBQSx1QkFBeUM7SUFDN0MsQ0FBQyxFQXJCVyxpQkFBaUIsS0FBakIsaUJBQWlCLEdBQUEsRUFBQSxDQUFBLENBQUE7SUF1QjdCLElBQVksaUJBRVg7SUFGRCxDQUFBLFVBQVksaUJBQWlCLEVBQUE7SUFDekIsSUFBQSxpQkFBQSxDQUFBLFNBQUEsQ0FBQSxHQUFBLGVBQXlCO0lBQzdCLENBQUMsRUFGVyxpQkFBaUIsS0FBakIsaUJBQWlCLEdBQUEsRUFBQSxDQUFBLENBQUE7SUFJN0IsSUFBWSxzQkFHWDtJQUhELENBQUEsVUFBWSxzQkFBc0IsRUFBQTtJQUM5QixJQUFBLHNCQUFBLENBQUEsWUFBQSxDQUFBLEdBQUEsd0JBQXFDO0lBQ3JDLElBQUEsc0JBQUEsQ0FBQSxRQUFBLENBQUEsR0FBQSxvQkFBNkI7SUFDakMsQ0FBQyxFQUhXLHNCQUFzQixLQUF0QixzQkFBc0IsR0FBQSxFQUFBLENBQUEsQ0FBQTtJQUtsQyxJQUFZLGlCQVFYO0lBUkQsQ0FBQSxVQUFZLGlCQUFpQixFQUFBO0lBQ3pCLElBQUEsaUJBQUEsQ0FBQSxnQkFBQSxDQUFBLEdBQUEsc0JBQXVDO0lBQ3ZDLElBQUEsaUJBQUEsQ0FBQSxtQkFBQSxDQUFBLEdBQUEseUJBQTZDO0lBQzdDLElBQUEsaUJBQUEsQ0FBQSxrQkFBQSxDQUFBLEdBQUEsd0JBQTJDO0lBQzNDLElBQUEsaUJBQUEsQ0FBQSxnQkFBQSxDQUFBLEdBQUEsc0JBQXVDO0lBQ3ZDLElBQUEsaUJBQUEsQ0FBQSxVQUFBLENBQUEsR0FBQSxnQkFBMkI7SUFDM0IsSUFBQSxpQkFBQSxDQUFBLGdCQUFBLENBQUEsR0FBQSxzQkFBdUM7SUFDdkMsSUFBQSxpQkFBQSxDQUFBLG9CQUFBLENBQUEsR0FBQSwwQkFBK0M7SUFDbkQsQ0FBQyxFQVJXLGlCQUFpQixLQUFqQixpQkFBaUIsR0FBQSxFQUFBLENBQUEsQ0FBQTtJQVU3QixJQUFZLHNCQUVYO0lBRkQsQ0FBQSxVQUFZLHNCQUFzQixFQUFBO0lBQzlCLElBQUEsc0JBQUEsQ0FBQSxRQUFBLENBQUEsR0FBQSxvQkFBNkI7SUFDakMsQ0FBQyxFQUZXLHNCQUFzQixLQUF0QixzQkFBc0IsR0FBQSxFQUFBLENBQUEsQ0FBQTtJQUlsQyxJQUFZLGlCQVNYO0lBVEQsQ0FBQSxVQUFZLGlCQUFpQixFQUFBO0lBQ3pCLElBQUEsaUJBQUEsQ0FBQSxxQkFBQSxDQUFBLEdBQUEsMkJBQWlEO0lBQ2pELElBQUEsaUJBQUEsQ0FBQSxxQkFBQSxDQUFBLEdBQUEsMkJBQWlEO0lBQ2pELElBQUEsaUJBQUEsQ0FBQSx5QkFBQSxDQUFBLEdBQUEsK0JBQXlEO0lBQ3pELElBQUEsaUJBQUEsQ0FBQSxPQUFBLENBQUEsR0FBQSxhQUFxQjtJQUNyQixJQUFBLGlCQUFBLENBQUEsa0JBQUEsQ0FBQSxHQUFBLHdCQUEyQztJQUMzQyxJQUFBLGlCQUFBLENBQUEsaUJBQUEsQ0FBQSxHQUFBLHVCQUF5QztJQUN6QyxJQUFBLGlCQUFBLENBQUEsaUJBQUEsQ0FBQSxHQUFBLHVCQUF5QztJQUN6QyxJQUFBLGlCQUFBLENBQUEsaUJBQUEsQ0FBQSxHQUFBLHVCQUF5QztJQUM3QyxDQUFDLEVBVFcsaUJBQWlCLEtBQWpCLGlCQUFpQixHQUFBLEVBQUEsQ0FBQSxDQUFBO0lBVzdCLElBQVksc0JBRVg7SUFGRCxDQUFBLFVBQVksc0JBQXNCLEVBQUE7SUFDOUIsSUFBQSxzQkFBQSxDQUFBLEtBQUEsQ0FBQSxHQUFBLGlCQUF1QjtJQUMzQixDQUFDLEVBRlcsc0JBQXNCLEtBQXRCLHNCQUFzQixHQUFBLEVBQUEsQ0FBQSxDQUFBO0lBSWxDLElBQVksaUJBRVg7SUFGRCxDQUFBLFVBQVksaUJBQWlCLEVBQUE7SUFDekIsSUFBQSxpQkFBQSxDQUFBLHFCQUFBLENBQUEsR0FBQSwyQkFBaUQ7SUFDckQsQ0FBQyxFQUZXLGlCQUFpQixLQUFqQixpQkFBaUIsR0FBQSxFQUFBLENBQUEsQ0FBQTtJQUk3QixJQUFZLGlCQUVYO0lBRkQsQ0FBQSxVQUFZLGlCQUFpQixFQUFBO0lBQ3pCLElBQUEsaUJBQUEsQ0FBQSxZQUFBLENBQUEsR0FBQSxrQkFBK0I7SUFDbkMsQ0FBQyxFQUZXLGlCQUFpQixLQUFqQixpQkFBaUIsR0FBQSxFQUFBLENBQUEsQ0FBQTs7SUNqRTdCOzs7Ozs7Ozs7Ozs7Ozs7Ozs7Ozs7Ozs7SUF3Qkc7SUFFSCxJQUFJLDBCQUEwQixHQUF3QixJQUFJO0lBRTFELElBQUksa0JBQWtCLEdBQUcsQ0FBQyxRQUFRLENBQUMsTUFBTTtJQUV6QztJQUNBLE1BQU0sZUFBZSxHQUFRO0lBQ3pCLElBQUEsT0FBTyxFQUFFLElBQUk7SUFDYixJQUFBLE9BQU8sRUFBRSxJQUFJO0tBQ2hCO0lBRUQsU0FBUywwQkFBMEIsR0FBQTtRQUMvQixRQUFRLENBQUMsZ0JBQWdCLENBQUMsa0JBQWtCLEVBQUUsMEJBQTJCLEVBQUUsZUFBZSxDQUFDO1FBQzNGLE1BQU0sQ0FBQyxnQkFBZ0IsQ0FBQyxVQUFVLEVBQUUsMEJBQTJCLEVBQUUsZUFBZSxDQUFDO1FBQ2pGLE1BQU0sQ0FBQyxnQkFBZ0IsQ0FBQyxPQUFPLEVBQUUsMEJBQTJCLEVBQUUsZUFBZSxDQUFDO0lBQ2xGO0lBRUEsU0FBUyxpQ0FBaUMsR0FBQTtRQUN0QyxRQUFRLENBQUMsbUJBQW1CLENBQUMsa0JBQWtCLEVBQUUsMEJBQTJCLEVBQUUsZUFBZSxDQUFDO1FBQzlGLE1BQU0sQ0FBQyxtQkFBbUIsQ0FBQyxVQUFVLEVBQUUsMEJBQTJCLEVBQUUsZUFBZSxDQUFDO1FBQ3BGLE1BQU0sQ0FBQyxtQkFBbUIsQ0FBQyxPQUFPLEVBQUUsMEJBQTJCLEVBQUUsZUFBZSxDQUFDO0lBQ3JGO0lBRU0sU0FBVSw2QkFBNkIsQ0FBQyxRQUFvQixFQUFBO0lBQzlELElBQUEsTUFBTSxlQUFlLEdBQUcsT0FBTyxDQUFDLDBCQUEwQixDQUFDO1FBQzNELDBCQUEwQixHQUFHLE1BQUs7SUFDOUIsUUFBQSxJQUFJLENBQUMsUUFBUSxDQUFDLE1BQU0sRUFBRTtJQUNsQixZQUFBLGdDQUFnQyxFQUFFO0lBQ2xDLFlBQUEsUUFBUSxFQUFFO2dCQUNWLGtCQUFrQixHQUFHLElBQUk7WUFDN0I7SUFDSixJQUFBLENBQUM7UUFDRCxJQUFJLENBQUMsZUFBZSxFQUFFO0lBQ2xCLFFBQUEsMEJBQTBCLEVBQUU7UUFDaEM7SUFDSjthQUVnQixnQ0FBZ0MsR0FBQTtJQUM1QyxJQUFBLGlDQUFpQyxFQUFFO1FBQ25DLDBCQUEwQixHQUFHLElBQUk7SUFDckM7YUFFZ0IsaUJBQWlCLEdBQUE7SUFDN0IsSUFBQSxPQUFPLGtCQUFrQjtJQUM3Qjs7SUNoRUEsU0FBUyxPQUFPLEdBQUE7SUFDWixJQUFBLDZCQUE2QixFQUFFO0lBQy9CLElBQUEsZ0NBQWdDLEVBQUU7SUFDdEM7SUFFQSxTQUFTLFdBQVcsQ0FBQyxPQUFzQixFQUFBO0lBQ3ZDLElBQUEsTUFBTSxlQUFlLEdBQUcsQ0FBQyxRQUF5RCxLQUFJOztJQUVsRixRQUFBLElBQUksUUFBUSxLQUFLLG1CQUFtQixFQUFFO0lBQ2xDLFlBQUEsT0FBTyxFQUFFO1lBQ2I7SUFDSixJQUFBLENBQUM7SUFFRCxJQUFBLElBQUk7WUFDQSxNQUFNLE9BQU8sR0FBRyxNQUFNLENBQUMsT0FBTyxDQUFDLFdBQVcsQ0FBcUQsT0FBTyxDQUFDO1lBQ3ZHLE9BQU8sQ0FBQyxJQUFJLENBQUMsZUFBZSxDQUFDLENBQUMsS0FBSyxDQUFDLE9BQU8sQ0FBQztRQUNoRDtRQUFFLE9BQU8sS0FBSyxFQUFFO0lBQ1o7Ozs7Ozs7OztJQVNHO0lBQ0gsUUFBQSxJQUFJLEtBQUssQ0FBQyxPQUFPLEtBQUssZ0NBQWdDLEVBQUU7SUFDcEQsWUFBQSxPQUFPLENBQUMsR0FBRyxDQUFDLHdEQUF3RCxDQUFDO0lBQ3JFLFlBQUEsT0FBTyxFQUFFO1lBQ2I7aUJBQU87SUFDSCxZQUFBLE9BQU8sQ0FBQyxHQUFHLENBQUMsdURBQXVELENBQUM7WUFDeEU7UUFDSjtJQUNKO0lBRUEsU0FBUyxtQkFBbUIsQ0FBQyxNQUFlLEVBQUE7SUFDeEMsSUFBQSxXQUFXLENBQUMsRUFBQyxJQUFJLEVBQUUsaUJBQWlCLENBQUMsbUJBQW1CLEVBQUUsSUFBSSxFQUFFLEVBQUMsTUFBTSxFQUFDLEVBQUMsQ0FBQztJQUM5RTtJQUVBLFNBQVMsb0JBQW9CLEdBQUE7SUFDekIsSUFBQSxtQkFBbUIsQ0FBQyx1QkFBdUIsRUFBRSxDQUFDO1FBQzlDLElBQUksaUJBQWlCLEVBQUUsRUFBRTtZQUNyQiw0QkFBNEIsQ0FBQyxtQkFBbUIsQ0FBQztRQUNyRDthQUFPO0lBQ0gsUUFBQSw2QkFBNkIsRUFBRTtRQUNuQztJQUNKO0lBRUEsNkJBQTZCLENBQUMsb0JBQW9CLENBQUM7SUFDbkQsb0JBQW9CLEVBQUU7Ozs7OzsifQ==
