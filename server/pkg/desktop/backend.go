package desktop

import (
	"image"

	"github.com/m1k1o/neko/server/pkg/types"
)

// Backend defines the interface for platform-specific desktop operations
type Backend interface {
	// Initialize the backend
	Init(display string) error
	// Cleanup resources
	Shutdown()

	// Screen operations
	GetScreenSize() types.ScreenSize
	SetScreenSize(size types.ScreenSize) (types.ScreenSize, error)
	GetScreenConfigurations() map[int]ScreenConfiguration
	TakeScreenshot() (image.Image, error)

	// Mouse operations
	Move(x, y int)
	GetCursorPosition() (int, int)
	Scroll(deltaX, deltaY int, controlKey bool)
	ButtonDown(code uint32) error
	ButtonUp(code uint32) error

	// Keyboard operations
	KeyDown(code uint32) error
	KeyUp(code uint32) error
	ResetKeys()
	SetKeyboardModifier(mod uint8, active bool)
	GetKeyboardModifiers() uint8
	KeyPress(codes ...uint32) error

	// Clipboard operations
	SetClipboard(text string)
	GetClipboard() (string, error)
}

// ScreenConfiguration represents a display configuration
type ScreenConfiguration struct {
	Width  int
	Height int
	Rates  map[int]int16
}

// Button codes for mouse events
const (
	ButtonLeft   uint32 = 1
	ButtonMiddle uint32 = 2
	ButtonRight  uint32 = 3
	ButtonScrollUp   uint32 = 4
	ButtonScrollDown uint32 = 5
)

// Modifier keys
const (
	ModShift    uint8 = 1 << iota
	ModCapsLock
	ModControl
	ModAlt
	ModNumLock
	ModMeta
	ModSuper
	ModAltGr
)