#import <Foundation/Foundation.h>

API_AVAILABLE(macos(15.3))
NSErrorDomain const WKWebExtensionMessagePortErrorDomain;

typedef NS_ERROR_ENUM(WKWebExtensionMessagePortErrorDomain, WKWebExtensionMessagePortError) {
    WKWebExtensionMessagePortErrorUnknown = 1,
    WKWebExtensionMessagePortErrorNotConnected,
    WKWebExtensionMessagePortErrorMessageInvalid,
} API_AVAILABLE(macos(15.3));

API_AVAILABLE(macos(15.3))
@interface WKWebExtensionMessagePort : NSObject

+ (instancetype)new NS_UNAVAILABLE;
- (instancetype)init NS_UNAVAILABLE;

@property (nonatomic, readonly, nullable) NSString *applicationIdentifier;
@property (nonatomic, copy, nullable) void (^messageHandler)(id _Nullable message, NSError * _Nullable error);
@property (nonatomic, copy, nullable) void (^disconnectHandler)(NSError * _Nullable error);
@property (nonatomic, readonly, getter=isDisconnected) BOOL disconnected;

- (void)sendMessage:(nullable id)message completionHandler:(void (^ _Nullable)(NSError * _Nullable error))completionHandler;
- (void)disconnect;
- (void)disconnectWithError:(nullable NSError *)error;

@end
