#import <Foundation/Foundation.h>
#import <Cocoa/Cocoa.h>


CGImageRef ComposeImage(NSString *inImagePath, NSString *overlayText, NSColor *textColor);
NSString * CreateBase64EncodedString(CGImageRef completeImage);
