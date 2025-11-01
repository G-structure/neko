package desktop

import (
	"image"
	"os/exec"
	"regexp"
	"runtime"
	"time"

	"github.com/m1k1o/neko/server/pkg/darwin"
	"github.com/m1k1o/neko/server/pkg/desktop"
	"github.com/m1k1o/neko/server/pkg/types"
	"github.com/m1k1o/neko/server/pkg/xorg"
)

// Move moves the mouse cursor
func (manager *DesktopManagerCtx) Move(x, y int) {
	manager.backend.Move(x, y)
}

// GetCursorPosition returns the current cursor position
func (manager *DesktopManagerCtx) GetCursorPosition() (int, int) {
	return manager.backend.GetCursorPosition()
}

// Scroll performs a scroll action
func (manager *DesktopManagerCtx) Scroll(deltaX, deltaY int, controlKey bool) {
	manager.backend.Scroll(deltaX, deltaY, controlKey)
}

// ButtonDown presses a mouse button
func (manager *DesktopManagerCtx) ButtonDown(code uint32) error {
	return manager.backend.ButtonDown(code)
}

// KeyDown presses a keyboard key
func (manager *DesktopManagerCtx) KeyDown(code uint32) error {
	return manager.backend.KeyDown(code)
}

// ButtonUp releases a mouse button
func (manager *DesktopManagerCtx) ButtonUp(code uint32) error {
	return manager.backend.ButtonUp(code)
}

// KeyUp releases a keyboard key
func (manager *DesktopManagerCtx) KeyUp(code uint32) error {
	return manager.backend.KeyUp(code)
}

// ButtonPress performs a button press (down only, with key reset)
func (manager *DesktopManagerCtx) ButtonPress(code uint32) error {
	manager.backend.ResetKeys()
	defer manager.backend.ResetKeys()

	return manager.backend.ButtonDown(code)
}

// KeyPress simulates key presses
func (manager *DesktopManagerCtx) KeyPress(codes ...uint32) error {
	manager.backend.ResetKeys()
	defer manager.backend.ResetKeys()

	for _, code := range codes {
		if err := manager.backend.KeyDown(code); err != nil {
			return err
		}
	}

	if len(codes) > 1 {
		time.Sleep(10 * time.Millisecond)
	}

	return nil
}

// ResetKeys releases all pressed keys
func (manager *DesktopManagerCtx) ResetKeys() {
	manager.backend.ResetKeys()
}

// ScreenConfigurations returns available screen configurations
func (manager *DesktopManagerCtx) ScreenConfigurations() []types.ScreenSize {
	configs := manager.backend.GetScreenConfigurations()

	var sizes []types.ScreenSize
	for _, config := range configs {
		for _, rate := range config.Rates {
			// Filter out all irrelevant rates
			if rate > 60 || (rate > 30 && rate%10 != 0) {
				continue
			}

			sizes = append(sizes, types.ScreenSize{
				Width:  config.Width,
				Height: config.Height,
				Rate:   rate,
			})
		}
	}

	return sizes
}

// SetScreenSize sets the screen resolution
func (manager *DesktopManagerCtx) SetScreenSize(screenSize types.ScreenSize) (types.ScreenSize, error) {
	mu.Lock()
	manager.emmiter.Emit("before_screen_size_change")

	defer func() {
		manager.emmiter.Emit("after_screen_size_change")
		mu.Unlock()
	}()

	screenSize, err := manager.backend.SetScreenSize(screenSize)
	if err == nil {
		// Cache the new screen size
		manager.screenSize = screenSize
	}

	return screenSize, err
}

// GetScreenSize returns the current screen size
func (manager *DesktopManagerCtx) GetScreenSize() types.ScreenSize {
	return manager.backend.GetScreenSize()
}

// SetKeyboardMap sets the keyboard layout
func (manager *DesktopManagerCtx) SetKeyboardMap(kbd types.KeyboardMap) error {
	// TODO: Implement in backend for cross-platform support
	if runtime.GOOS != "linux" {
		return nil // Not supported on non-Linux
	}

	// Use setxkbmap command on Linux
	cmd := exec.Command("setxkbmap", "-layout", kbd.Layout, "-variant", kbd.Variant)
	_, err := cmd.Output()
	return err
}

// GetKeyboardMap returns the current keyboard layout
func (manager *DesktopManagerCtx) GetKeyboardMap() (*types.KeyboardMap, error) {
	// TODO: Implement in backend for cross-platform support
	if runtime.GOOS != "linux" {
		return &types.KeyboardMap{}, nil // Return empty on non-Linux
	}

	// Use setxkbmap command on Linux
	cmd := exec.Command("setxkbmap", "-query")
	res, err := cmd.Output()
	if err != nil {
		return nil, err
	}

	kbd := types.KeyboardMap{}

	re := regexp.MustCompile(`layout:\s+(.*)\n`)
	arr := re.FindStringSubmatch(string(res))
	if len(arr) > 1 {
		kbd.Layout = arr[1]
	}

	re = regexp.MustCompile(`variant:\s+(.*)\n`)
	arr = re.FindStringSubmatch(string(res))
	if len(arr) > 1 {
		kbd.Variant = arr[1]
	}

	return &kbd, nil
}

// SetKeyboardModifiers sets keyboard modifiers
func (manager *DesktopManagerCtx) SetKeyboardModifiers(mod types.KeyboardModifiers) {
	if mod.Shift != nil {
		manager.backend.SetKeyboardModifier(desktop.ModShift, *mod.Shift)
	}

	if mod.CapsLock != nil {
		manager.backend.SetKeyboardModifier(desktop.ModCapsLock, *mod.CapsLock)
	}

	if mod.Control != nil {
		manager.backend.SetKeyboardModifier(desktop.ModControl, *mod.Control)
	}

	if mod.Alt != nil {
		manager.backend.SetKeyboardModifier(desktop.ModAlt, *mod.Alt)
	}

	if mod.NumLock != nil {
		manager.backend.SetKeyboardModifier(desktop.ModNumLock, *mod.NumLock)
	}

	if mod.Meta != nil {
		manager.backend.SetKeyboardModifier(desktop.ModMeta, *mod.Meta)
	}

	if mod.Super != nil {
		manager.backend.SetKeyboardModifier(desktop.ModSuper, *mod.Super)
	}

	if mod.AltGr != nil {
		manager.backend.SetKeyboardModifier(desktop.ModAltGr, *mod.AltGr)
	}
}

// GetKeyboardModifiers returns the current keyboard modifiers
func (manager *DesktopManagerCtx) GetKeyboardModifiers() types.KeyboardModifiers {
	mods := manager.backend.GetKeyboardModifiers()

	isset := func(mod uint8) *bool {
		x := mods&mod != 0
		return &x
	}

	return types.KeyboardModifiers{
		Shift:    isset(desktop.ModShift),
		CapsLock: isset(desktop.ModCapsLock),
		Control:  isset(desktop.ModControl),
		Alt:      isset(desktop.ModAlt),
		NumLock:  isset(desktop.ModNumLock),
		Meta:     isset(desktop.ModMeta),
		Super:    isset(desktop.ModSuper),
		AltGr:    isset(desktop.ModAltGr),
	}
}

// GetCursorImage returns the current cursor image
func (manager *DesktopManagerCtx) GetCursorImage() *types.CursorImage {
	switch runtime.GOOS {
	case "linux":
		// Use xorg function for Linux
		return xorg.GetCursorImage()
	case "darwin":
		// Use darwin function for macOS
		return darwin.GetCursorImage()
	default:
		return nil
	}
}

// GetScreenshotImage captures a screenshot
func (manager *DesktopManagerCtx) GetScreenshotImage() *image.RGBA {
	img, err := manager.backend.TakeScreenshot()
	if err != nil {
		manager.logger.Err(err).Msg("failed to take screenshot")
		return nil
	}

	// Convert to RGBA if needed
	if rgba, ok := img.(*image.RGBA); ok {
		return rgba
	}

	// Convert to RGBA
	bounds := img.Bounds()
	rgba := image.NewRGBA(bounds)
	for y := bounds.Min.Y; y < bounds.Max.Y; y++ {
		for x := bounds.Min.X; x < bounds.Max.X; x++ {
			rgba.Set(x, y, img.At(x, y))
		}
	}

	return rgba
}