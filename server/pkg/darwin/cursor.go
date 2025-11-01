// +build darwin

package darwin

/*
#cgo CFLAGS: -x objective-c
#cgo LDFLAGS: -framework Cocoa -framework CoreGraphics

#import <Cocoa/Cocoa.h>

typedef struct {
    uint16_t width;
    uint16_t height;
    uint16_t xhot;
    uint16_t yhot;
    uint64_t serial;
    void *pixels;  // RGBA data
} CursorImageData;

CursorImageData* getCursorImageData() {
    @autoreleasepool {
        // Get current system cursor
        NSCursor *cursor = [NSCursor currentSystemCursor];
        if (!cursor) return NULL;

        NSImage *image = cursor.image;
        NSPoint hotspot = cursor.hotSpot;

        // Convert to CGImage
        CGImageRef cgImage = [image CGImageForProposedRect:nil
                                                   context:nil
                                                     hints:nil];
        if (!cgImage) return NULL;

        size_t width = CGImageGetWidth(cgImage);
        size_t height = CGImageGetHeight(cgImage);
        size_t bytesPerRow = width * 4;

        // Allocate RGBA buffer
        void *bitmapData = malloc(bytesPerRow * height);

        // Create RGBA bitmap context
        CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
        CGContextRef context = CGBitmapContextCreate(
            bitmapData,
            width,
            height,
            8,
            bytesPerRow,
            colorSpace,
            kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big
        );

        // Draw cursor image
        CGContextDrawImage(context, CGRectMake(0, 0, width, height), cgImage);

        // Create result
        CursorImageData *result = malloc(sizeof(CursorImageData));
        result->width = (uint16_t)width;
        result->height = (uint16_t)height;
        result->xhot = (uint16_t)hotspot.x;
        result->yhot = (uint16_t)hotspot.y;
        result->serial = 0;  // Could use a counter in the future
        result->pixels = bitmapData;

        // Clean up
        CGContextRelease(context);
        CGColorSpaceRelease(colorSpace);

        return result;
    }
}

void freeCursorImageData(CursorImageData *img) {
    if (img) {
        if (img->pixels) free(img->pixels);
        free(img);
    }
}
*/
import "C"
import (
	"image"

	"github.com/m1k1o/neko/server/pkg/types"
)

// GetCursorImage captures the current macOS cursor using NSCursor API
// This is a package-level function for consistency with the xorg package
func GetCursorImage() *types.CursorImage {
	data := C.getCursorImageData()
	if data == nil {
		return nil
	}
	defer C.freeCursorImageData(data)

	width := int(data.width)
	height := int(data.height)

	// Create RGBA image
	img := image.NewRGBA(image.Rect(0, 0, width, height))

	// Copy pixel data from C to Go
	pixelData := (*[1 << 30]byte)(data.pixels)[:width*height*4 : width*height*4]
	copy(img.Pix, pixelData)

	return &types.CursorImage{
		Width:  uint16(width),
		Height: uint16(height),
		Xhot:   uint16(data.xhot),
		Yhot:   uint16(data.yhot),
		Serial: uint64(data.serial),
		Image:  img,
	}
}
