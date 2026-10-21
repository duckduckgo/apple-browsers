#import <Cocoa/Cocoa.h>
@interface Delegate : NSObject <NSApplicationDelegate>
@property(strong) NSWindow *window;
@end
@implementation Delegate
- (void)applicationDidFinishLaunching:(NSNotification *)note {
 self.window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0,0,500,300) styleMask:NSWindowStyleMaskTitled|NSWindowStyleMaskClosable backing:NSBackingStoreBuffered defer:NO];
 self.window.title = @"UI Automation Gate";
 NSTextField *label = [NSTextField labelWithString:@"Automation is running"];
 label.identifier = @"gate-label"; label.frame = NSMakeRect(20,130,400,40);
 [self.window.contentView addSubview:label];
 [self.window center]; [self.window makeKeyAndOrderFront:nil];
 [NSApp activateIgnoringOtherApps:YES];
}
@end
int main(int argc,const char **argv) { @autoreleasepool { NSApplication *app=[NSApplication sharedApplication]; Delegate *d=[Delegate new]; app.delegate=d; [app setActivationPolicy:NSApplicationActivationPolicyRegular]; [app run]; } return 0; }
