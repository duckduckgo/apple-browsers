#import <Foundation/Foundation.h>
#import "WKWebExtensionControllerDelegate.h"
#import "WKWebExtensionDataType.h"
#import "WKWebExtensionTab.h"
#import "WKWebExtensionWindow.h"

@class WKWebExtension;
@class WKWebExtensionContext;
@class WKWebExtensionControllerConfiguration;
@class WKWebExtensionDataRecord;

API_AVAILABLE(macos(15.3))
@interface WKWebExtensionController : NSObject

- (instancetype)init NS_DESIGNATED_INITIALIZER;
- (instancetype)initWithConfiguration:(WKWebExtensionControllerConfiguration *)configuration NS_DESIGNATED_INITIALIZER;

@property (nonatomic, weak) id <WKWebExtensionControllerDelegate> delegate;
@property (nonatomic, readonly, copy) WKWebExtensionControllerConfiguration *configuration;

- (BOOL)loadExtensionContext:(WKWebExtensionContext *)extensionContext error:(NSError **)error NS_SWIFT_NAME(load(_:));
- (BOOL)unloadExtensionContext:(WKWebExtensionContext *)extensionContext error:(NSError **)error NS_SWIFT_NAME(unload(_:));

- (nullable WKWebExtensionContext *)extensionContextForExtension:(WKWebExtension *)extension NS_SWIFT_NAME(extensionContext(for:));
- (nullable WKWebExtensionContext *)extensionContextForURL:(NSURL *)URL NS_SWIFT_NAME(extensionContext(for:));

@property (nonatomic, readonly, copy) NSSet<WKWebExtension *> *extensions;
@property (nonatomic, readonly, copy) NSSet<WKWebExtensionContext *> *extensionContexts;
@property (class, nonatomic, readonly, copy) NSSet<WKWebExtensionDataType> *allExtensionDataTypes;

- (void)fetchDataRecordsOfTypes:(NSSet<WKWebExtensionDataType> *)dataTypes completionHandler:(void (^)(NSArray<WKWebExtensionDataRecord *> *))completionHandler NS_SWIFT_NAME(fetchDataRecords(ofTypes:completionHandler:)) WK_SWIFT_ASYNC_NAME(dataRecords(ofTypes:));

- (void)fetchDataRecordOfTypes:(NSSet<WKWebExtensionDataType> *)dataTypes forExtensionContext:(WKWebExtensionContext *)extensionContext completionHandler:(void (^)(WKWebExtensionDataRecord * _Nullable))completionHandler NS_SWIFT_NAME(fetchDataRecord(ofTypes:for:completionHandler:)) WK_SWIFT_ASYNC_NAME(dataRecord(ofTypes:for:));

- (void)removeDataOfTypes:(NSSet<WKWebExtensionDataType> *)dataTypes fromDataRecords:(NSArray<WKWebExtensionDataRecord *> *)dataRecords completionHandler:(void (^)(void))completionHandler NS_SWIFT_NAME(removeData(ofTypes:from:completionHandler:));

- (void)didOpenWindow:(id <WKWebExtensionWindow>)newWindow NS_SWIFT_NAME(didOpenWindow(_:));
- (void)didCloseWindow:(id <WKWebExtensionWindow>)closedWindow NS_SWIFT_NAME(didCloseWindow(_:));
- (void)didFocusWindow:(nullable id <WKWebExtensionWindow>)focusedWindow NS_SWIFT_NAME(didFocusWindow(_:));

- (void)didOpenTab:(id <WKWebExtensionTab>)newTab NS_SWIFT_NAME(didOpenTab(_:));
- (void)didCloseTab:(id <WKWebExtensionTab>)closedTab windowIsClosing:(BOOL)windowIsClosing NS_SWIFT_NAME(didCloseTab(_:windowIsClosing:));
- (void)didActivateTab:(id<WKWebExtensionTab>)activatedTab previousActiveTab:(nullable id<WKWebExtensionTab>)previousTab NS_SWIFT_NAME(didActivateTab(_:previousActiveTab:));
- (void)didSelectTabs:(NSSet<id <WKWebExtensionTab>> *)selectedTabs NS_SWIFT_NAME(didSelectTabs(_:));
- (void)didDeselectTabs:(NSSet<id <WKWebExtensionTab>> *)deselectedTabs NS_SWIFT_NAME(didDeselectTabs(_:));
- (void)didMoveTab:(id <WKWebExtensionTab>)movedTab fromIndex:(NSUInteger)index inWindow:(nullable id <WKWebExtensionWindow>)oldWindow NS_SWIFT_NAME(didMoveTab(_:from:in:));
- (void)didReplaceTab:(id <WKWebExtensionTab>)oldTab withTab:(id <WKWebExtensionTab>)newTab NS_SWIFT_NAME(didReplaceTab(_:with:));
- (void)didChangeTabProperties:(WKWebExtensionTabChangedProperties)properties forTab:(id <WKWebExtensionTab>)changedTab NS_SWIFT_NAME(didChangeTabProperties(_:for:));

@end
