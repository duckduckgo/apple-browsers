#import "WKWebExtensionControllerDelegate.h"

API_AVAILABLE(macos(15.3))
@protocol WKWebExtensionControllerDelegatePrivate <WKWebExtensionControllerDelegate>
@optional

- (void)_webExtensionController:(WKWebExtensionController *)controller recordTestAssertionResult:(BOOL)result withMessage:(NSString *)message andSourceURL:(NSString *)sourceURL lineNumber:(unsigned)lineNumber;

- (void)_webExtensionController:(WKWebExtensionController *)controller recordTestEqualityResult:(BOOL)result expectedValue:(NSString *)expectedValue actualValue:(NSString *)actualValue withMessage:(NSString *)message andSourceURL:(NSString *)sourceURL lineNumber:(unsigned)lineNumber;

- (void)_webExtensionController:(WKWebExtensionController *)controller recordTestMessage:(NSString *)message andSourceURL:(NSString *)sourceURL lineNumber:(unsigned)lineNumber;

- (void)_webExtensionController:(WKWebExtensionController *)controller recordTestYieldedWithMessage:(NSString *)message andSourceURL:(NSString *)sourceURL lineNumber:(unsigned)lineNumber;

- (void)_webExtensionController:(WKWebExtensionController *)controller recordTestFinishedWithResult:(BOOL)result message:(NSString *)message andSourceURL:(NSString *)sourceURL lineNumber:(unsigned)lineNumber;

- (void)_webExtensionController:(WKWebExtensionController *)controller didCreateBackgroundWebView:(WKWebView *)webView forExtensionContext:(WKWebExtensionContext *)context;

- (void)_webExtensionController:(WKWebExtensionController *)controller presentSidebar:(WKWebExtensionSidebar *)sidebar forExtensionContext:(WKWebExtensionContext *)context completionHandler:(void (^)(NSError * _Nullable error))completionHandler;

- (void)_webExtensionController:(WKWebExtensionController *)controller closeSidebar:(WKWebExtensionSidebar *)sidebar forExtensionContext:(WKWebExtensionContext *)context completionHandler:(void (^)(NSError * _Nullable error))completionHandler;

- (void)_webExtensionController:(WKWebExtensionController *)controller didUpdateSidebar:(WKWebExtensionSidebar *)sidebar forExtensionContext:(WKWebExtensionContext *)context;

@end
