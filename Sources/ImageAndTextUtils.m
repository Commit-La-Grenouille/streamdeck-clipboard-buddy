#import "ImageAndTextUtils.h"


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
CGImageRef ComposeImage(NSString *inImagePath, NSString *overlayText, NSColor *textColor)
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
NSString * CreateBase64EncodedString(CGImageRef completeImage)
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
