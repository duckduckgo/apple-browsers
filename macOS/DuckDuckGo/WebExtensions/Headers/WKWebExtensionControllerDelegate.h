#import "WKWebExtensionControllerConfiguration.h"
#import "WKWebExtensionMessagePort.h"
#import "WKWebExtensionWindowConfiguration.h"

API_AVAILABLE(macos(15.3))
@protocol WKWebExtensionControllerDelegate <NSObject>
@optional

- (NSArray<id <WKWebExtensionWindow>> *)webExtensionController:(WKWebExtensionController *)controller openWindowsForExtensionContext:(WKWebExtensionContext *)extensionContext;

- (nullable id <WKWebExtensionWindow>)webExtensionController:(WKWebExtensionController *)controller focusedWindowForExtensionContext:(WKWebExtensionContext *)extensionContext;

- (void)webExtensionController:(WKWebExtensionController *)controller openNewWindowUsingConfiguration:(WKWebExtensionWindowConfiguration *)configuration forExtensionContext:(WKWebExtensionContext *)extensionContext completionHandler:(void (^)(id <WKWebExtensionWindow> _Nullable newWindow, NSError * _Nullable error))completionHandler;

- (void)webExtensionController:(WKWebExtensionController *)controller openNewTabUsingConfiguration:(WKWebExtensionTabConfiguration *)configuration forExtensionContext:(WKWebExtensionContext *)extensionContext completionHandler:(void (^)(id <WKWebExtensionTab> _Nullable newTab, NSError * _Nullable error))completionHandler;

- (void)webExtensionController:(WKWebExtensionController *)controller openOptionsPageForExtensionContext:(WKWebExtensionContext *)extensionContext completionHandler:(void (^)(NSError * _Nullable error))completionHandler;

- (void)webExtensionController:(WKWebExtensionController *)controller promptForPermissions:(NSSet<WKWebExtensionPermission> *)permissions inTab:(nullable id <WKWebExtensionTab>)tab forExtensionContext:(WKWebExtensionContext *)extensionContext completionHandler:(void (^)(NSSet<WKWebExtensionPermission> *allowedPermissions, NSDate * _Nullable expirationDate))completionHandler;

- (void)webExtensionController:(WKWebExtensionController *)controller promptForPermissionToAccessURLs:(NSSet<NSURL *> *)urls inTab:(nullable id <WKWebExtensionTab>)tab forExtensionContext:(WKWebExtensionContext *)extensionContext completionHandler:(void (^)(NSSet<NSURL *> *allowedURLs, NSDate * _Nullable expirationDate))completionHandler;

- (void)webExtensionController:(WKWebExtensionController *)controller promptForPermissionMatchPatterns:(NSSet<WKWebExtensionMatchPattern *> *)matchPatterns inTab:(nullable id <WKWebExtensionTab>)tab forExtensionContext:(WKWebExtensionContext *)extensionContext completionHandler:(void (^)(NSSet<WKWebExtensionMatchPattern *> *allowedMatchPatterns, NSDate * _Nullable expirationDate))completionHandler;

- (void)webExtensionController:(WKWebExtensionController *)controller presentPopupForAction:(WKWebExtensionAction *)action forExtensionContext:(WKWebExtensionContext *)context completionHandler:(void (^)(NSError * _Nullable error))completionHandler;

- (void)webExtensionController:(WKWebExtensionController *)controller sendMessage:(id)message toApplicationWithIdentifier:(nullable NSString *)applicationIdentifier forExtensionContext:(WKWebExtensionContext *)extensionContext replyHandler:(void (^)(id _Nullable replyMessage, NSError * _Nullable error))replyHandler;

- (void)webExtensionController:(WKWebExtensionController *)controller connectUsingMessagePort:(WKWebExtensionMessagePort *)port forExtensionContext:(WKWebExtensionContext *)extensionContext completionHandler:(void (^)(NSError * _Nullable error))completionHandler;

@end
