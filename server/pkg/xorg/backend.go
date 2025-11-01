// +build linux

package xorg

import (
	"fmt"
	"image"

	"github.com/m1k1o/neko/server/pkg/desktop"
	"github.com/m1k1o/neko/server/pkg/types"
)

// XorgBackend implements the desktop.Backend interface for Linux/X11
type XorgBackend struct {
	display    string
	screenSize types.ScreenSize
}

// NewBackend creates a new X11 desktop backend
func NewBackend() desktop.Backend {
	return &XorgBackend{}
}

// Init initializes the X11 backend
func (x *XorgBackend) Init(display string) error {
	x.display = display

	if DisplayOpen(display) {
		return fmt.Errorf("unable to open X11 display: %s", display)
	}

	// Get screen configurations
	GetScreenConfigurations()

	return nil
}

// Shutdown cleans up X11 resources
func (x *XorgBackend) Shutdown() {
	DisplayClose()
}

// GetScreenSize returns the current screen size
func (x *XorgBackend) GetScreenSize() types.ScreenSize {
	// This should call the appropriate xorg function to get screen size
	// For now, return cached value
	return x.screenSize
}

// SetScreenSize sets the screen resolution
func (x *XorgBackend) SetScreenSize(size types.ScreenSize) (types.ScreenSize, error) {
	actualSize, err := ChangeScreenSize(size)
	if err == nil {
		x.screenSize = actualSize
	}
	return actualSize, err
}

// GetScreenConfigurations returns available screen configurations
func (x *XorgBackend) GetScreenConfigurations() map[int]desktop.ScreenConfiguration {
	configs := make(map[int]desktop.ScreenConfiguration)

	// Convert from xorg.ScreenConfiguration to desktop.ScreenConfiguration
	for id, config := range ScreenConfigurations {
		configs[id] = desktop.ScreenConfiguration{
			Width:  config.Width,
			Height: config.Height,
			Rates:  config.Rates,
		}
	}

	return configs
}

// TakeScreenshot captures the current screen
func (x *XorgBackend) TakeScreenshot() (image.Image, error) {
	// Get screenshot using existing xorg functions
	img := GetScreenshotImage()
	if img == nil {
		return nil, fmt.Errorf("failed to capture screenshot")
	}
	return img, nil
}

// Move moves the mouse cursor
func (x *XorgBackend) Move(xPos, yPos int) {
	Move(xPos, yPos)
}

// GetCursorPosition returns the current cursor position
func (x *XorgBackend) GetCursorPosition() (int, int) {
	return GetCursorPosition()
}

// Scroll performs a scroll action
func (x *XorgBackend) Scroll(deltaX, deltaY int, controlKey bool) {
	Scroll(deltaX, deltaY, controlKey)
}

// ButtonDown presses a mouse button
func (x *XorgBackend) ButtonDown(code uint32) error {
	return ButtonDown(code)
}

// ButtonUp releases a mouse button
func (x *XorgBackend) ButtonUp(code uint32) error {
	return ButtonUp(code)
}

// KeyDown presses a keyboard key
func (x *XorgBackend) KeyDown(code uint32) error {
	return KeyDown(code)
}

// KeyUp releases a keyboard key
func (x *XorgBackend) KeyUp(code uint32) error {
	return KeyUp(code)
}

// ResetKeys releases all pressed keys
func (x *XorgBackend) ResetKeys() {
	ResetKeys()
}

// SetKeyboardModifier sets the state of a keyboard modifier
func (x *XorgBackend) SetKeyboardModifier(mod uint8, active bool) {
	// Map desktop.Mod* constants to X11 modifiers
	var x11Mod KbdMod
	switch mod {
	case desktop.ModShift:
		x11Mod = KbdModShift
	case desktop.ModCapsLock:
		x11Mod = KbdModCapsLock
	case desktop.ModControl:
		x11Mod = KbdModControl
	case desktop.ModAlt:
		x11Mod = KbdModAlt
	case desktop.ModNumLock:
		x11Mod = KbdModNumLock
	case desktop.ModMeta:
		x11Mod = KbdModMeta
	case desktop.ModSuper:
		x11Mod = KbdModSuper
	case desktop.ModAltGr:
		x11Mod = KbdModAltGr
	default:
		return
	}

	SetKeyboardModifier(x11Mod, active)
}

// GetKeyboardModifiers returns the current keyboard modifiers
func (x *XorgBackend) GetKeyboardModifiers() uint8 {
	x11Mods := GetKeyboardModifiers()

	// Convert X11 modifiers to desktop.Mod* constants
	var mods uint8
	if x11Mods&KbdModShift != 0 {
		mods |= desktop.ModShift
	}
	if x11Mods&KbdModCapsLock != 0 {
		mods |= desktop.ModCapsLock
	}
	if x11Mods&KbdModControl != 0 {
		mods |= desktop.ModControl
	}
	if x11Mods&KbdModAlt != 0 {
		mods |= desktop.ModAlt
	}
	if x11Mods&KbdModNumLock != 0 {
		mods |= desktop.ModNumLock
	}
	if x11Mods&KbdModMeta != 0 {
		mods |= desktop.ModMeta
	}
	if x11Mods&KbdModSuper != 0 {
		mods |= desktop.ModSuper
	}
	if x11Mods&KbdModAltGr != 0 {
		mods |= desktop.ModAltGr
	}

	return mods
}

// KeyPress simulates a key press (down and up)
func (x *XorgBackend) KeyPress(codes ...uint32) error {
	for _, code := range codes {
		if err := KeyDown(code); err != nil {
			return err
		}
		if err := KeyUp(code); err != nil {
			return err
		}
	}
	return nil
}

// SetClipboard sets the clipboard content
// Note: The actual clipboard handling is done at a higher level using xclip
func (x *XorgBackend) SetClipboard(text string) {
	// This is handled by the desktop manager using xclip
	// No-op at this level
}

// GetClipboard returns the clipboard content
// Note: The actual clipboard handling is done at a higher level using xclip
func (x *XorgBackend) GetClipboard() (string, error) {
	// This is handled by the desktop manager using xclip
	// Return empty string for now
	return "", nil
}