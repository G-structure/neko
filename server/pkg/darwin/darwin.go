// +build darwin

package darwin

import (
	"errors"
	"fmt"
	"image"
	"sync"
	"time"

	"github.com/go-vgo/robotgo"
	"github.com/m1k1o/neko/server/pkg/desktop"
	"github.com/m1k1o/neko/server/pkg/types"
)

// DarwinBackend implements the desktop.Backend interface for macOS
type DarwinBackend struct {
	mu               sync.Mutex
	display          string
	screenSize       types.ScreenSize
	debounceButton   map[uint32]time.Time
	debounceKey      map[uint32]time.Time
	keyboardModifiers uint8
}

// NewBackend creates a new macOS desktop backend
func NewBackend() desktop.Backend {
	return &DarwinBackend{
		debounceButton: make(map[uint32]time.Time),
		debounceKey:    make(map[uint32]time.Time),
	}
}

// Init initializes the macOS backend
func (d *DarwinBackend) Init(display string) error {
	d.display = display

	// Check for required permissions
	if err := checkPermissions(); err != nil {
		return fmt.Errorf("permission check failed: %w", err)
	}

	// Get initial screen size
	width, height := robotgo.GetScreenSize()
	d.screenSize = types.ScreenSize{
		Width:  width,
		Height: height,
		Rate:   60, // Default to 60Hz, macOS doesn't easily expose refresh rate
	}

	return nil
}

// Shutdown cleans up resources
func (d *DarwinBackend) Shutdown() {
	// Cleanup any resources if needed
}

// GetScreenSize returns the current screen size
func (d *DarwinBackend) GetScreenSize() types.ScreenSize {
	d.mu.Lock()
	defer d.mu.Unlock()

	width, height := robotgo.GetScreenSize()
	d.screenSize.Width = width
	d.screenSize.Height = height
	return d.screenSize
}

// SetScreenSize sets the screen size (not supported on macOS)
func (d *DarwinBackend) SetScreenSize(size types.ScreenSize) (types.ScreenSize, error) {
	// macOS doesn't allow programmatic screen resolution changes
	// Return current size
	return d.GetScreenSize(), errors.New("changing screen resolution not supported on macOS")
}

// GetScreenConfigurations returns available screen configurations
func (d *DarwinBackend) GetScreenConfigurations() map[int]desktop.ScreenConfiguration {
	configs := make(map[int]desktop.ScreenConfiguration)

	// Get current configuration
	width, height := robotgo.GetScreenSize()
	configs[0] = desktop.ScreenConfiguration{
		Width:  width,
		Height: height,
		Rates:  map[int]int16{60: 60}, // Default to 60Hz
	}

	return configs
}

// TakeScreenshot captures the current screen
func (d *DarwinBackend) TakeScreenshot() (image.Image, error) {
	bitmap := robotgo.CaptureScreen()
	if bitmap == nil {
		return nil, errors.New("failed to capture screen")
	}
	defer robotgo.FreeBitmap(bitmap)

	// Convert bitmap to image.Image
	img := robotgo.ToImage(bitmap)
	return img, nil
}

// Move moves the mouse cursor to the specified position
func (d *DarwinBackend) Move(x, y int) {
	d.mu.Lock()
	defer d.mu.Unlock()

	robotgo.Move(x, y)
}

// GetCursorPosition returns the current cursor position
func (d *DarwinBackend) GetCursorPosition() (int, int) {
	d.mu.Lock()
	defer d.mu.Unlock()

	x, y := robotgo.GetMousePos()
	return x, y
}

// Scroll performs a scroll action
func (d *DarwinBackend) Scroll(deltaX, deltaY int, controlKey bool) {
	d.mu.Lock()
	defer d.mu.Unlock()

	if controlKey {
		// Hold control key during scroll (for zoom)
		robotgo.KeyToggle("ctrl", "down")
		defer robotgo.KeyToggle("ctrl", "up")
	}

	if deltaY != 0 {
		// Vertical scroll
		robotgo.Scroll(0, deltaY)
	}

	if deltaX != 0 {
		// Horizontal scroll
		robotgo.ScrollSmooth(deltaX, 0)
	}
}

// ButtonDown presses a mouse button
func (d *DarwinBackend) ButtonDown(code uint32) error {
	d.mu.Lock()
	defer d.mu.Unlock()

	if _, ok := d.debounceButton[code]; ok {
		return fmt.Errorf("button %d already pressed", code)
	}

	d.debounceButton[code] = time.Now()

	switch code {
	case desktop.ButtonLeft:
		robotgo.Toggle("left", "down")
	case desktop.ButtonMiddle:
		robotgo.Toggle("center", "down")
	case desktop.ButtonRight:
		robotgo.Toggle("right", "down")
	default:
		return fmt.Errorf("unknown button code: %d", code)
	}

	return nil
}

// ButtonUp releases a mouse button
func (d *DarwinBackend) ButtonUp(code uint32) error {
	d.mu.Lock()
	defer d.mu.Unlock()

	if _, ok := d.debounceButton[code]; !ok {
		return fmt.Errorf("button %d not pressed", code)
	}

	delete(d.debounceButton, code)

	switch code {
	case desktop.ButtonLeft:
		robotgo.Toggle("left", "up")
	case desktop.ButtonMiddle:
		robotgo.Toggle("center", "up")
	case desktop.ButtonRight:
		robotgo.Toggle("right", "up")
	default:
		return fmt.Errorf("unknown button code: %d", code)
	}

	return nil
}

// KeyDown presses a keyboard key
func (d *DarwinBackend) KeyDown(code uint32) error {
	d.mu.Lock()
	defer d.mu.Unlock()

	if _, ok := d.debounceKey[code]; ok {
		return fmt.Errorf("key %d already pressed", code)
	}

	d.debounceKey[code] = time.Now()

	// Convert X11 keycode to macOS key
	key := convertKeycode(code)
	if key == "" {
		return fmt.Errorf("unknown keycode: %d", code)
	}

	robotgo.KeyToggle(key, "down")
	return nil
}

// KeyUp releases a keyboard key
func (d *DarwinBackend) KeyUp(code uint32) error {
	d.mu.Lock()
	defer d.mu.Unlock()

	if _, ok := d.debounceKey[code]; !ok {
		return fmt.Errorf("key %d not pressed", code)
	}

	delete(d.debounceKey, code)

	// Convert X11 keycode to macOS key
	key := convertKeycode(code)
	if key == "" {
		return fmt.Errorf("unknown keycode: %d", code)
	}

	robotgo.KeyToggle(key, "up")
	return nil
}

// ResetKeys releases all pressed keys
func (d *DarwinBackend) ResetKeys() {
	d.mu.Lock()
	defer d.mu.Unlock()

	// Release all pressed keys
	for code := range d.debounceKey {
		key := convertKeycode(code)
		if key != "" {
			robotgo.KeyToggle(key, "up")
		}
	}

	// Clear debounce maps
	d.debounceKey = make(map[uint32]time.Time)
	d.debounceButton = make(map[uint32]time.Time)

	// Reset modifiers
	d.keyboardModifiers = 0
}

// SetKeyboardModifier sets the state of a keyboard modifier
func (d *DarwinBackend) SetKeyboardModifier(mod uint8, active bool) {
	d.mu.Lock()
	defer d.mu.Unlock()

	var key string
	switch mod {
	case desktop.ModShift:
		key = "shift"
	case desktop.ModControl:
		key = "ctrl"
	case desktop.ModAlt:
		key = "alt"
	case desktop.ModSuper:
		key = "cmd"
	default:
		return
	}

	if active {
		robotgo.KeyToggle(key, "down")
		d.keyboardModifiers |= mod
	} else {
		robotgo.KeyToggle(key, "up")
		d.keyboardModifiers &^= mod
	}
}

// GetKeyboardModifiers returns the current keyboard modifiers
func (d *DarwinBackend) GetKeyboardModifiers() uint8 {
	d.mu.Lock()
	defer d.mu.Unlock()
	return d.keyboardModifiers
}

// KeyPress simulates a key press (down and up)
func (d *DarwinBackend) KeyPress(codes ...uint32) error {
	for _, code := range codes {
		key := convertKeycode(code)
		if key == "" {
			return fmt.Errorf("unknown keycode: %d", code)
		}
		robotgo.KeyTap(key)
	}
	return nil
}

// SetClipboard sets the clipboard content
func (d *DarwinBackend) SetClipboard(text string) {
	robotgo.WriteAll(text)
}

// GetClipboard returns the clipboard content
func (d *DarwinBackend) GetClipboard() (string, error) {
	text, err := robotgo.ReadAll()
	if err != nil {
		return "", err
	}
	return text, nil
}

// checkPermissions checks if the app has required permissions
func checkPermissions() error {
	// This is a placeholder - actual implementation would check:
	// 1. Screen Recording permission
	// 2. Accessibility permission
	// These checks require Objective-C/Swift bridging

	// For now, we'll just return a warning
	// The actual permission check will happen when trying to use the features
	return nil
}