#import <Foundation/Foundation.h>

@class WKSnapshotConfiguration;
@class WKWebView;
@class WKWebExtensionContext;
@class WKWebExtensionTabConfiguration;
@protocol WKWebExtensionWindow;

@class NSImage;

typedef NS_OPTIONS(NSUInteger, WKWebExtensionTabChangedProperties) {
    WKWebExtensionTabChangedPropertiesNone         = 0,
    WKWebExtensionTabChangedPropertiesLoading      = 1 << 1,
    WKWebExtensionTabChangedPropertiesMuted        = 1 << 2,
    WKWebExtensionTabChangedPropertiesPinned       = 1 << 3,
    WKWebExtensionTabChangedPropertiesPlayingAudio = 1 << 4,
    WKWebExtensionTabChangedPropertiesReaderMode   = 1 << 5,
    WKWebExtensionTabChangedPropertiesSize         = 1 << 6,
    WKWebExtensionTabChangedPropertiesTitle        = 1 << 7,
    WKWebExtensionTabChangedPropertiesURL          = 1 << 8,
    WKWebExtensionTabChangedPropertiesZoomFactor   = 1 << 9,
} NS_SWIFT_NAME(WKWebExtension.TabChangedProperties) API_AVAILABLE(macos(15.3));

API_AVAILABLE(macos(15.3)) WK_SWIFT_UI_ACTOR
@protocol WKWebExtensionTab <NSObject>
@optional

- (nullable id <WKWebExtensionWindow>)windowForWebExtensionContext:(WKWebExtensionContext *)context NS_SWIFT_NAME(window(for:));
- (NSUInteger)indexInWindowForWebExtensionContext:(WKWebExtensionContext *)context NS_SWIFT_NAME(indexInWindow(for:));
- (nullable id <WKWebExtensionTab>)parentTabForWebExtensionContext:(WKWebExtensionContext *)context NS_SWIFT_NAME(parentTab(for:));
- (void)setParentTab:(nullable id <WKWebExtensionTab>)parentTab forWebExtensionContext:(WKWebExtensionContext *)context completionHandler:(void (^)(NSError * _Nullable error))completionHandler NS_SWIFT_NAME(setParentTab(_:for:completionHandler:));
- (nullable WKWebView *)webViewForWebExtensionContext:(WKWebExtensionContext *)context NS_SWIFT_NAME(webView(for:));
- (nullable NSString *)titleForWebExtensionContext:(WKWebExtensionContext *)context NS_SWIFT_NAME(title(for:));
- (BOOL)isPinnedForWebExtensionContext:(WKWebExtensionContext *)context NS_SWIFT_NAME(isPinned(for:));
- (void)setPinned:(BOOL)pinned forWebExtensionContext:(WKWebExtensionContext *)context completionHandler:(void (^)(NSError * _Nullable error))completionHandler NS_SWIFT_NAME(setPinned(_:for:completionHandler:));
- (BOOL)isReaderModeAvailableForWebExtensionContext:(WKWebExtensionContext *)context NS_SWIFT_NAME(isReaderModeAvailable(for:));
- (BOOL)isReaderModeActiveForWebExtensionContext:(WKWebExtensionContext *)context NS_SWIFT_NAME(isReaderModeActive(for:));
- (void)setReaderModeActive:(BOOL)active forWebExtensionContext:(WKWebExtensionContext *)context completionHandler:(void (^)(NSError * _Nullable error))completionHandler NS_SWIFT_NAME(setReaderModeActive(_:for:completionHandler:));
- (BOOL)isPlayingAudioForWebExtensionContext:(WKWebExtensionContext *)context NS_SWIFT_NAME(isPlayingAudio(for:));
- (BOOL)isMutedForWebExtensionContext:(WKWebExtensionContext *)context NS_SWIFT_NAME(isMuted(for:));
- (void)setMuted:(BOOL)muted forWebExtensionContext:(WKWebExtensionContext *)context completionHandler:(void (^)(NSError * _Nullable error))completionHandler NS_SWIFT_NAME(setMuted(_:for:completionHandler:));
- (CGSize)sizeForWebExtensionContext:(WKWebExtensionContext *)context NS_SWIFT_NAME(size(for:));
- (double)zoomFactorForWebExtensionContext:(WKWebExtensionContext *)context NS_SWIFT_NAME(zoomFactor(for:));
- (void)setZoomFactor:(double)zoomFactor forWebExtensionContext:(WKWebExtensionContext *)context completionHandler:(void (^)(NSError * _Nullable error))completionHandler NS_SWIFT_NAME(setZoomFactor(_:for:completionHandler:));
- (nullable NSURL *)urlForWebExtensionContext:(WKWebExtensionContext *)context NS_SWIFT_NAME(url(for:));
- (nullable NSURL *)pendingURLForWebExtensionContext:(WKWebExtensionContext *)context NS_SWIFT_NAME(pendingURL(for:));
- (BOOL)isLoadingCompleteForWebExtensionContext:(WKWebExtensionContext *)context NS_SWIFT_NAME(isLoadingComplete(for:));
- (void)detectWebpageLocaleForWebExtensionContext:(WKWebExtensionContext *)context completionHandler:(void (^)(NSLocale * _Nullable locale, NSError * _Nullable error))completionHandler NS_SWIFT_NAME(detectWebpageLocale(for:completionHandler:));
- (void)takeSnapshotUsingConfiguration:(WKSnapshotConfiguration *)configuration forWebExtensionContext:(WKWebExtensionContext *)context completionHandler:(void (^)(NSImage * _Nullable webpageImage, NSError * _Nullable error))completionHandler NS_SWIFT_NAME(takeSnapshot(using:for:completionHandler:)) WK_SWIFT_ASYNC_NAME(snapshot(using:for:));
- (void)loadURL:(NSURL *)url forWebExtensionContext:(WKWebExtensionContext *)context completionHandler:(void (^)(NSError * _Nullable error))completionHandler NS_SWIFT_NAME(loadURL(_:for:completionHandler:));
- (void)reloadFromOrigin:(BOOL)fromOrigin forWebExtensionContext:(WKWebExtensionContext *)context completionHandler:(void (^)(NSError * _Nullable error))completionHandler NS_SWIFT_NAME(reload(fromOrigin:for:completionHandler:));
- (void)goBackForWebExtensionContext:(WKWebExtensionContext *)context completionHandler:(void (^)(NSError * _Nullable error))completionHandler NS_SWIFT_NAME(goBack(for:completionHandler:));
- (void)goForwardForWebExtensionContext:(WKWebExtensionContext *)context completionHandler:(void (^)(NSError * _Nullable error))completionHandler NS_SWIFT_NAME(goForward(for:completionHandler:));
- (void)activateForWebExtensionContext:(WKWebExtensionContext *)context completionHandler:(void (^)(NSError * _Nullable error))completionHandler NS_SWIFT_NAME(activate(for:completionHandler:));
- (BOOL)isSelectedForWebExtensionContext:(WKWebExtensionContext *)context NS_SWIFT_NAME(isSelected(for:));
- (void)setSelected:(BOOL)selected forWebExtensionContext:(WKWebExtensionContext *)context completionHandler:(void (^)(NSError * _Nullable error))completionHandler NS_SWIFT_NAME(setSelected(_:for:completionHandler:));
- (void)duplicateUsingConfiguration:(WKWebExtensionTabConfiguration *)configuration forWebExtensionContext:(WKWebExtensionContext *)context completionHandler:(void (^)(id <WKWebExtensionTab> _Nullable duplicatedTab, NSError * _Nullable error))completionHandler NS_SWIFT_NAME(duplicate(using:for:completionHandler:));
- (void)closeForWebExtensionContext:(WKWebExtensionContext *)context completionHandler:(void (^)(NSError * _Nullable error))completionHandler NS_SWIFT_NAME(close(for:completionHandler:));
- (BOOL)shouldGrantPermissionsOnUserGestureForWebExtensionContext:(WKWebExtensionContext *)context NS_SWIFT_NAME(shouldGrantPermissionsOnUserGesture(for:));

@end
