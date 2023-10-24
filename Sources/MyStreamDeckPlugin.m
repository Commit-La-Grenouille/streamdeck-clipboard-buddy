//==============================================================================
/**
@file       MyStreamDeckPlugin.m

@brief      A Stream Deck plugin to provide a way to retain some clipboard data for re-use

@copyright  (c) 2022, Commit-La-Grenouille
			This source code is licensed under the GPLv3-style license found in the LICENSE file.

**/
//==============================================================================

#import "MyStreamDeckPlugin.h"

#import "ESDSDKDefines.h"
#import "ESDConnectionManager.h"
#import "ESDUtilities.h"
#import <AppKit/AppKit.h>

// REMEMBER THAT THIS STORE_ACT IS ALSO IN THE index_pi.js FILE
#define STORE_ACT  @"net.localhost.streamdeck.clipboard-buddy"
#define CLEAR_ACT  @"net.localhost.streamdeck.clipboard-buddy-clear"
#define SECUR_ACT  @"net.localhost.streamdeck.clipboard-buddy-secure"
#define NUKE_ACT   @"net.localhost.streamdeck.clipboard-buddy-nuke"
#define LINE_ACT   @"net.localhost.streamdeck.clipboard-buddy-line"

// REMEMBER THAT THESE DEFAULT VALUES ARE ALSO IN THE index_pi.js FILE
#define MIN_LONG_PRESS_DEFAULT  0.5
#define SECURE_PRESS_DEFAULT    1.0
#define CLEAR_PRESS_DEFAULT     2.0

// Size of the images
#define IMAGE_SIZE    144

// Text area boundaries within the post-it icons (top-left is START_X,MAX_Y)
#define SAFE_BORDER   7.0
#define START_X    SAFE_BORDER
#define START_Y    SAFE_BORDER
//#define MAX_X      IMAGE_SIZE - SAFE_BORDER
#define MAX_Y      IMAGE_SIZE - SAFE_BORDER
// Text in Andale Mono 14 about 16 chars (lowercase) to fit within the width of the post-it
#define LINE_LENGTH    16



// MARK: the static methods to help

//
// Utility function to get the fullpath of an resource in the bundle
//
static NSString * GetResourcePath(NSString *inFilename)
{
    NSString *outPath = nil;
    
    if([inFilename length] > 0)
    {
        NSString * bundlePath = [ESDUtilities pluginPath];
        if(bundlePath != nil)
        {
            outPath = [bundlePath stringByAppendingPathComponent:inFilename];
        }
    }
    
    return outPath;
}


//
// Utility function to create a CGContextRef
//
static CGContextRef CreateBitmapContext(CGSize inSize)
{
    CGFloat bitmapBytesPerRow = inSize.width * 4;
    CGFloat bitmapByteCount = (bitmapBytesPerRow * inSize.height);
    
    void *bitmapData = calloc(bitmapByteCount, 1);
    if(bitmapData == NULL)
    {
        return NULL;
    }
    
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(bitmapData, inSize.width, inSize.height, 8, bitmapBytesPerRow, colorSpace, kCGImageAlphaPremultipliedLast);
    if(context == NULL)
    {
        CGColorSpaceRelease(colorSpace);
        free(bitmapData);
        return NULL;
    }
    else
    {
        CGColorSpaceRelease(colorSpace);
        return context;
    }
}


//
// Utility method that takes the path of an image and a string and returns the bitmap result
//
static CGImageRef ComposeImage(NSString *inImagePath, NSString *overlayText, NSColor *textColor)
{
    CGImageRef completeImage = nil;
    
    NSImage* image = [[NSImage alloc] initWithContentsOfFile:inImagePath];
    if(image != nil)
    {
        // Find the best CGImageRef
        CGSize iconSize = CGSizeMake(IMAGE_SIZE, IMAGE_SIZE);
        NSRect theRect = NSMakeRect(0, 0, iconSize.width, iconSize.height);
        CGImageRef imageRef = [image CGImageForProposedRect:&theRect context:NULL hints:nil];
        if(imageRef != NULL)
        {
            // Create a CGContext
            CGContextRef context = CreateBitmapContext(iconSize);
            if(context != NULL)
            {
                // Draw the image
                CGContextDrawImage(context, theRect, imageRef);
                
                // Deal with the text if provided
                if (overlayText) {
                    //
                    // PART 1: transforming the basic string into a CoreText powerhouse
                    //
                    CGFloat fontSize = 14.0f;
                    // Choosing a monospaced font installed by default in macOS that deals well with small sizes
                    CTFontRef font = CTFontCreateWithName(CFSTR("Andale Mono"), fontSize, nil);
                    
                    // Making sure that we have a text color otherwise we default to yellow
                    if(textColor == nil) { textColor = NSColor.systemYellowColor; }
 
                    // Do not forget that the attributes are fed backward (VALUE OBJ, KEY)
                    NSDictionary* attributes = [NSDictionary dictionaryWithObjectsAndKeys:
                                                (__bridge id)font, kCTFontAttributeName,
                                                textColor, NSForegroundColorAttributeName,
                                                    nil];
                    CFRelease(font);


                    // Preparing the initial trackers for our text wrapping needs
                    CGFloat strLenRemain = overlayText.length;
                    CGFloat offset_y = 0.0;
                    
                    while (strLenRemain > 0) {
                        //
                        // PART 2: slicing the text into pieces that could fit our constraints
                        //
                        NSAttributedString* overlayAttrStr = [[NSAttributedString alloc] initWithString:[overlayText substringFromIndex:overlayText.length-strLenRemain] attributes:attributes];
                        //
                        // TODO: could be improved by only taking the actual slice of text we will display
                        //       for more accurate measurements on the ascent/descent...
                        //
                        CTLineRef line = CTLineCreateWithAttributedString((CFAttributedStringRef)overlayAttrStr);
                        
                        // Extracting some measurements of what remains of our line
                        CGFloat ascent, descent, leading;
                        CTLineGetTypographicBounds(line, &ascent, &descent, &leading);
                        
                        //
                        // PART 3: rendering the lines inside the image we loaded
                        //
                        CGFloat x = START_X;
                        CGFloat y = MAX_Y - offset_y - ascent;
                        CGContextSetTextPosition(context, x, y);
                        CTLineDraw(line, context);
                        CFRelease(line);
                        
                        // Now we can prepare the values for the next line we wrap
                        strLenRemain -= LINE_LENGTH;
                        offset_y += ascent + descent;
                        
                        // We also want to detect if we are going too low to avoid bleeding off our background post-it
                        if (MAX_Y - offset_y <= START_Y * 2) {
                            strLenRemain = 0;
                        }
                    }
                }
                
                // Generate the final image
                completeImage = CGBitmapContextCreateImage(context);
            }
            CFRelease(context);
        }
    }
    return completeImage;
}


//
// Utility method that transforms an image into a base64 encoded string
//
static NSString * CreateBase64EncodedString(CGImageRef completeImage)
{
    NSString *outBase64PNG = nil;
    
    if(completeImage != NULL)
    {
        // Export the image to PNG
        CFMutableDataRef pngData = CFDataCreateMutable(kCFAllocatorDefault, 0);
        if(pngData != NULL)
        {
            CGImageDestinationRef destinationRef = CGImageDestinationCreateWithData(pngData, kUTTypePNG, 1, NULL);
            if (destinationRef != NULL)
            {
                CGImageDestinationAddImage(destinationRef, completeImage, nil);
                if (CGImageDestinationFinalize(destinationRef))
                {
                    NSString *base64PNG = [(__bridge NSData *)pngData base64EncodedStringWithOptions:NSDataBase64EncodingEndLineWithCarriageReturn];
                    if([base64PNG length] > 0)
                    {
                        outBase64PNG = [NSString stringWithFormat:@"data:image/png;base64,%@\">", base64PNG];
                    }
                }
                
                CFRelease(destinationRef);
            }
            
            CFRelease(pngData);
        }
        
        CFRelease(completeImage);
    }

    return outBase64PNG;
}


//
// Simple static method to keep the code accessing the dict of text simpler to read (and to maintain)
//
static NSString * keyFromCoord(NSDictionary * esdData) {
    return [NSString stringWithFormat:@"%@#%@", esdData[@"row"], esdData[@"column"]];
}


//
// Having a window dialog to grab a proper label to display with secure clipboard data
//
static NSString * askUserForLabel(NSDateFormatter *df) {
    //
    // TODO: replace with code that prompt the user for an identification string to display
    //
    
    // In the meantime, we will make sure we display a safe-and-unique label
    NSDate *current = [[NSDate alloc] init];
    return [df stringFromDate:current];
}


//
// Utility function to init/reset the storage dict
//
static NSMutableDictionary * ResetDictContent(NSInteger thisDevHeight, NSInteger thisDevWidth) {

    // A basic dict for our row-column to string transformation
    NSMutableDictionary * tmpDict = [[NSMutableDictionary alloc] initWithCapacity:1];
    
    // The final dict with the default values inside
    NSMutableDictionary * rdyDict = [[NSMutableDictionary alloc] initWithCapacity: thisDevWidth*thisDevHeight];

    // We need to initialize the dict for text (max the whole size of the device)
    for (NSInteger row=0; row < thisDevWidth; row++) {
        for (NSInteger col=0; col < thisDevHeight; col++) {
            //
            // We need to fake the usual structure we get while running to use the common keyFromCoord() method
            // Unfortunately, a dict requires String or string-like elements so we have to do a formatting :(
            //
            tmpDict[@"row"] = [NSString stringWithFormat:@"%ld", row];
            tmpDict[@"column"] = [NSString stringWithFormat:@"%ld", col];
            
            rdyDict[ keyFromCoord(tmpDict) ] = keyFromCoord(tmpDict);
            // using the key as default value should make any code misbehavior visible
        }
    }
    return rdyDict;
}


//
// Utility function to properly clear a key (background + title)
//
static BOOL ClearKey(ESDConnectionManager *conMan, id thisContext, NSString *backgroundImage) {
    
    // Changing the background to convey we have purged the data
    [conMan setImage:backgroundImage withContext:thisContext withTarget:kESDSDKTarget_HardwareAndSoftware];
    
    // And clearing the text if it was a secure entry
    [conMan setTitle:@"" withContext:thisContext withTarget:kESDSDKTarget_HardwareAndSoftware];
    
    return true;
}


// MARK: - MyStreamDeckPlugin

@interface MyStreamDeckPlugin ()

// The empty post-it icon encoded in base64
@property (strong) NSString *base64PostitEmpty;
@property (strong) NSString *base64PostitSleepy;
@property (strong) NSString *base64PostitSleepyClearOnly;
@property (strong) NSString *base64PostitSleepySecureOnly;
@property (strong) NSString *base64PostitSecure;

// The text we want to hold (one entry per key)
@property (strong) NSMutableDictionary *tileText;
@property BOOL dictInitialized;
@property (strong) NSMutableDictionary *tileContext;
@property (strong) NSMutableDictionary *tileType;
@property (strong) NSDictionary *typeBaseImg;
// The context of each tile to simplify global actions (like the nuke)

// The global clipboard
@property NSPasteboard *pboard;

// The timestamp when a key is pressed & when it is released
@property (strong) NSDate *keyPressed;
@property (strong) NSDate *keyReleased;

// The system colors to diversify the text color on keys
@property (strong) NSArray *textColorMatrix;
@property (strong) NSColor *previousColor;

// For secure entries we store objects to reuse
@property (strong) NSDateFormatter *daFo;

// The information about the device we use to deal properly with the storage dict
@property NSInteger devHeight;
@property NSInteger devWidth;

// The properties to store the configuration for the actions
@property double MIN_LONG_PRESS;
@property double SECURE_PRESS;
@property double CLEAR_PRESS;

@end


@implementation MyStreamDeckPlugin



// MARK: - Setup the instance variables if needed

- (void)setupIfNeeded
{
    if (_base64PostitSleepy == nil) {
        _base64PostitSleepy = CreateBase64EncodedString(ComposeImage(GetResourcePath(@"icons/postit-unused@2x.png"), @"", nil));
    }
    if (_base64PostitSleepyClearOnly == nil) {
        _base64PostitSleepyClearOnly = CreateBase64EncodedString(ComposeImage(GetResourcePath(@"icons/postit-unused-clear@2x.png"), @"", nil));
    }
    if (_base64PostitSleepySecureOnly == nil) {
        _base64PostitSleepySecureOnly = CreateBase64EncodedString(ComposeImage(GetResourcePath(@"icons/postit-unused-secure@2x.png"), @"", nil));
    }
    
    // This dict will make the code simpler by selecting the right default background when a button gets cleaned (instead of having another if/else block)
    _typeBaseImg = @{
        STORE_ACT : _base64PostitSleepy,
        CLEAR_ACT : _base64PostitSleepyClearOnly,
        SECUR_ACT : _base64PostitSleepySecureOnly
    };
    
	if (_base64PostitEmpty == nil) {
		_base64PostitEmpty = CreateBase64EncodedString(ComposeImage(GetResourcePath(@"icons/postit-empty@2x.png"), @"", nil));
	}
    if (_base64PostitSecure == nil) {
        _base64PostitSecure = CreateBase64EncodedString(ComposeImage(GetResourcePath(@"icons/postit-secure@2x.png"), @"", nil));
    }

    // Preparing the matrix to diversify the color of key's text (almost enough for the 15 buttons)
    /*
     * Joy of OS X versions variations:
     *    => we are forced to use cyanColor as systemCyanColor required 12.0 or newer
     *    => we cannot use systemIndigoColor because it requires 10.15 or newer
     */
    if (_textColorMatrix == nil) {
        _textColorMatrix = @[
            NSColor.systemBlueColor,
            NSColor.systemBrownColor,
            NSColor.cyanColor,
            NSColor.systemGreenColor,
            NSColor.lightGrayColor,
            NSColor.magentaColor,
            NSColor.systemMintColor,
            NSColor.systemOrangeColor,
            NSColor.systemPinkColor,
            NSColor.systemPurpleColor,
            NSColor.systemRedColor,
            NSColor.systemTealColor,
            NSColor.systemYellowColor,
        ]; // note: alpha sorted on the color name ;)
    }

    // Defining we want to use the central clipboard
    _pboard = [NSPasteboard generalPasteboard];
    
    // Preparing the date formatter once and for all
    _daFo = [[NSDateFormatter alloc] init];
    [_daFo setDateFormat:@"dd.MM.YY\nHH:mm:ss"];

    // Making sure we have some default values in case the didReceiveGlobalSettings never comes
    _MIN_LONG_PRESS = MIN_LONG_PRESS_DEFAULT;
    _SECURE_PRESS = SECURE_PRESS_DEFAULT;
    _CLEAR_PRESS = CLEAR_PRESS_DEFAULT;
}



// MARK: - Events handler


- (void)keyDownForAction:(NSString *)action withContext:(id)context withPayload:(NSDictionary *)payload forDevice:(NSString *)deviceID
{
    // Useful only when dealing with STORE_ACT actions otherwise it would trigger a pasting on keyUpForAction
    if([action isEqualToString:STORE_ACT] || [action isEqualToString:CLEAR_ACT] || [action isEqualToString:SECUR_ACT]) {
        _keyPressed = [[NSDate alloc] init];
    }
    
    if([action isEqualToString:NUKE_ACT]) {
        
        // We check which key holds data and make sure it gets purged properly (visually)
        for(NSString * key in [_tileContext allKeys]) {
            ClearKey(_connectionManager, _tileContext[key], _typeBaseImg[key]);
            [_tileContext removeObjectForKey:key];
        }
        // At this point, everything should be visually clean and we must ensure the text storage is too ;)
        _tileText = [NSMutableDictionary dictionaryWithDictionary:ResetDictContent(_devHeight, _devWidth)];
        
        // ESD 6.4.0 is showing the status for so long it hinders the plugin usage flow
        //[_connectionManager showOKForContext:context];
    }
    
    if([action isEqualToString:LINE_ACT]) {
        // Let's make sure we do not suicide ourselves (the trash button should not be part of the clean-up action)
        NSString * notMe = keyFromCoord(payload[@"coordinates"]);
        
        // We must only clear the keys in the same line as this button !
        // So we need to check the line from the payload[@"coordinates"][@"row"]
        //     & use the device's width to iterate over the columns ;o) (good news: the struct should be sized like the device !)
        for(NSString * key in [_tileContext allKeys]) {
            if([key containsString:[NSString stringWithFormat:@"%@#", payload[@"coordinates"][@"row"]]] && key != notMe) {
                
                // Making sure the icon is clean (back to default/empty icon)
                ClearKey(_connectionManager, _tileContext[key], _typeBaseImg[key]);
                
                // Ensuring that there is no context on-hold for this particular key
                [_tileContext removeObjectForKey:key];
                
                // Purging any text related to this key
                _tileText[key] = key;
            }
            // else we do not care about the keys and should not touch them...
        }
    }
}


- (void)keyUpForAction:(NSString *)action withContext:(id)context withPayload:(NSDictionary *)payload forDevice:(NSString *)deviceID
{
    if([action isEqualToString:NUKE_ACT] || [action isEqualToString:LINE_ACT]) {
        // We should do nothing
        return;
    }

    _keyReleased = [[NSDate alloc] init];
    NSTimeInterval diff = [_keyReleased timeIntervalSinceDate:_keyPressed];
    
    // Logging the length of the key press for future reference
    [_connectionManager logMessage: [NSString stringWithFormat:@"[KEY UP] Key pressed for %20lf sec", diff]];
    
    /*
     * ALL THE STORAGE CASES
     */
    
    if (diff >= _MIN_LONG_PRESS) {
        
        // Grabbing the current data in the clipboard
        NSString * clipboardContent = [_pboard stringForType:NSStringPboardType];

        // Making sure we store the clipboard data into a separate entry specific to our button
        NSString * dictKey = keyFromCoord(payload[@"coordinates"]);
        _tileText[dictKey] = clipboardContent;
        _tileContext[dictKey] = context;
        
        // Picking also a pseudo-random color for the text we will display on the button
        NSColor *thisColor = _textColorMatrix[ arc4random_uniform(sizeof(_textColorMatrix)) ];
        while (thisColor == _previousColor) {
            thisColor = _textColorMatrix[ arc4random_uniform(sizeof(_textColorMatrix)) ];
        }
        _previousColor = thisColor;  // making sure we won't pick the same color next time (crude)
        

        // Showing the copy worked
        //[_connectionManager showOKForContext:context];
        // ESD 6.4.0 is showing the status for so long it hinders the plugin usage flow
        
        /*
         * CASE 2: we have a long press or we are using a secure-only button
         */
        if (
               ([action isEqualToString:STORE_ACT] && diff >= _SECURE_PRESS && diff < _CLEAR_PRESS)
            || ([action isEqualToString:SECUR_ACT] && diff < _SECURE_PRESS)
            ) {
            // Changing the background to convey we have sensitive data there
            [_connectionManager setImage:_base64PostitSecure withContext:context withTarget:kESDSDKTarget_HardwareAndSoftware];
            
            // TODO: Adding a safe title to avoid leaking sensitive data
            NSString * secureTitle = askUserForLabel(_daFo);
            [_connectionManager logMessage:[NSString stringWithFormat:@"We asked the user and got the label (%@)", secureTitle]];

            [_connectionManager setTitle:secureTitle withContext:context withTarget:kESDSDKTarget_HardwareAndSoftware];
        }
        /*
         * CASE 3: the long press has been long enough to trigger a clearing
         */
        
        // We are making sure that on single-type actions, the clear duration is shorter (no need to wait forever)
        else if (
                    ( [action isEqualToString:STORE_ACT] && diff >= _CLEAR_PRESS)
                 || (([action isEqualToString:CLEAR_ACT] || [action isEqualToString:SECUR_ACT]) && diff >= _SECURE_PRESS)
                 ) {
            // Purging the struct by resetting to the default value
            _tileText[dictKey] = dictKey;
            [_tileContext removeObjectForKey:dictKey];
            
            ClearKey(_connectionManager, context, _typeBaseImg[dictKey]);
        }
        /*
         * CASE 1: the press is short enough or the button is made for clear storage
         */
        else {
            // SAFETY: hopefully we will never reach within this conditional block but just in case we avoid storing in clear on a secure-only action
            if([action isEqualToString:SECUR_ACT]) {
                [_connectionManager logMessage:[NSString stringWithFormat:@"WARNING ! A secure action at coordinates (%@) reached the clear storage with a press duration of (%f)", dictKey, diff]];
                return;
            }

            NSString * textToDisplay = _tileText[ keyFromCoord(payload[@"coordinates"]) ];
            
            if (textToDisplay.length <= LINE_LENGTH) {
                // In this situation, we could render the text but it will look very small and the space mostly
                //    empty, so it is safer to display it as a title (with the title text being set small enough)
                [_connectionManager setImage:_base64PostitEmpty withContext:context withTarget:kESDSDKTarget_HardwareAndSoftware];
                
                [_connectionManager setTitle:textToDisplay withContext:context withTarget:kESDSDKTarget_HardwareAndSoftware];
                // When the SDK will allow, we should also set this as centered in the display and with
                //    a font size between 8 and 10...
                
            }
            else {
                // In case the button was used for a secure entry before, we must make sure we clear the title
                [_connectionManager setTitle:@"" withContext:context withTarget:kESDSDKTarget_HardwareAndSoftware];
                
                // Defining everything as image (background + text)
                NSString *backgroundWithText64 = CreateBase64EncodedString(
                                                                           ComposeImage(@"icons/postit-empty@2x.png", textToDisplay, thisColor));
                
                [_connectionManager setImage:backgroundWithText64 withContext:context withTarget:kESDSDKTarget_HardwareAndSoftware];
                
                // THE FOLLOWING WOULD HAVE BEEN A LOT SIMPLER IF ONLY THE SDK SUPPORTED TITLE WRAPPING...
                
                // Changing the background for something simpler to display text over
                //[_connectionManager setImage:_base64PostitEmpty withContext:context withTarget:kESDSDKTarget_HardwareAndSoftware];
                
                // Adding the text to the tile
                //[_connectionManager setTitle:_tileText[ keyFromCoord(payload[@"coordinates"]) ] withContext:context withTarget:kESDSDKTarget_HardwareAndSoftware];
            }
        }
    }
    /*
     * CASE 0: the press is short and we must paste what we have in storage
     */
    else {
        [_pboard clearContents];
        BOOL wasClipboardUpdated = [_pboard setString:_tileText[ keyFromCoord(payload[@"coordinates"]) ] forType:NSStringPboardType];
        
        // This logging message is less crucial and should not leak sensitive data (so staying generic)
        [_connectionManager logMessage:[NSString stringWithFormat:@"[KEY UP][SHORT PRESS] Text was reinjected back into the clipboard: %hd", wasClipboardUpdated]];

        if (wasClipboardUpdated) {
            //
            // This code is a big programmatic command+V
            //
            CGKeyCode key = ((CGKeyCode)9); // code for V in qwerty/azerty/qwertz
            
            /*
            // In order to keep the code compact (and the memory usage small), here is the dict of keyCodes for some layouts
            _keyCodeMapping = @{  // NSNumber plays better with NSDictionaries than CGKeyCode that is an unsigned int
                  @"turkish": @(8),  // code for V in Turkish F
                  @"default": @(9),  // code for V in qwerty/azerty/qwertz
                  @"dvorigh": @(43), // code for V in Dvorak right-handed
                  @"dvorak" : @(47)  // code for V in Dvorak (us/fr/...)
            };
            // Any exotic keyboard layout just need to be defined here with the 2 keycodes to be supported by the plugin
            */

            CGEventSourceRef source = CGEventSourceCreate(kCGEventSourceStateCombinedSessionState);

            CGEventRef keyDown = CGEventCreateKeyboardEvent(source, key, TRUE);
            CGEventSetFlags(keyDown, kCGEventFlagMaskCommand);
            CGEventRef keyUp = CGEventCreateKeyboardEvent(source, key, FALSE);

            CGEventPost(kCGAnnotatedSessionEventTap, keyDown);
            CGEventPost(kCGAnnotatedSessionEventTap, keyUp);

            CFRelease(keyUp);
            CFRelease(keyDown);
            CFRelease(source);
        }
        else {
            [_connectionManager showAlertForContext:context];
        }
    }
    
}

- (void)willAppearForAction:(NSString *)action withContext:(id)context withPayload:(NSDictionary *)payload forDevice:(NSString *)deviceID
{
	// Set up the instance variables if needed
	[self setupIfNeeded];

	// Add the context to the list of known contexts
	//[self.knownContexts addObject:context];
}

- (void)willDisappearForAction:(NSString *)action withContext:(id)context withPayload:(NSDictionary *)payload forDevice:(NSString *)deviceID
{
	// Remove the context from the list of known contexts
	//[self.knownContexts removeObject:context];
}

- (void)deviceDidConnect:(NSString *)deviceID withDeviceInfo:(NSDictionary *)deviceInfo
{
    // Relaying the dimensions of the current device as integers
    _devHeight= [deviceInfo[@"size"][@"columns"] integerValue];
    _devWidth = [deviceInfo[@"size"][@"rows"] integerValue];
    
    // Making sure we do not loose data if the computer is locked or goes to sleep ;)
    if( _dictInitialized ) {
        [_connectionManager logMessage:[NSString stringWithFormat:@"[DID-CONNECT] No need to re-intialize the internal text storage in order to avoid loosing existing data..."]];
    }
    else {
        // Preparing text dictionary (as we need the device's buttons info)
        _tileText = [NSMutableDictionary dictionaryWithDictionary:ResetDictContent(_devHeight, _devWidth)];
        _dictInitialized = TRUE;

        // Preparing also the context dictionary (without any content for now)
        _tileContext = [[NSMutableDictionary alloc] initWithCapacity: _devWidth*_devHeight];
        
        // Preparing also the button types registry
        _tileType = [[NSMutableDictionary alloc] initWithCapacity: _devWidth*_devHeight];
    }
}

- (void)deviceDidDisconnect:(NSString *)deviceID
{
	// Nothing to do
}

- (void)applicationDidLaunch:(NSDictionary *)applicationInfo
{
	// Nothing to do
}

- (void)applicationDidTerminate:(NSDictionary *)applicationInfo
{
	// Nothing to do
}

- (void) didReceiveGlobalSettings: (NSString *)action withPayload:(NSDictionary *)payload
{
    // WORK IN PROGRESS (NOT OPERATIONAL QUITE YET)
    
    // Reloading the config in memory because the user changed it in the ESD UI
    for (NSString *propKey in payload) {

        if ([propKey isEqualToString:@"simple"]) {
            _MIN_LONG_PRESS = [[payload objectForKey:propKey] doubleValue];
        }
        else if ([propKey isEqualToString:@"secure"]) {
            _SECURE_PRESS = [[payload objectForKey:propKey] doubleValue];
        }
        else if ([propKey isEqualToString:@"clear"]) {
            _CLEAR_PRESS = [[payload objectForKey:propKey] doubleValue];
        }
        else {
            [_connectionManager logMessage:[NSString stringWithFormat:@"[DID-RECEIVE-GLOBAL] Unknown property (%@) with value (%@)", propKey, payload[propKey]]];
        }
    }
}

@end
