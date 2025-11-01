//go:build darwin

package xorg

import (
	"time"

	"github.com/m1k1o/neko/server/pkg/desktop"
	"github.com/m1k1o/neko/server/pkg/types"
)

// Stub implementation for macOS - this package is not used on Darwin
// The actual backend is provided by pkg/darwin instead

func NewBackend() desktop.Backend {
	// Return nil - should not be called on macOS
	return nil
}

func CheckKeys(duration time.Duration) {
	// Stub for macOS
}

func GetCursorImage() *types.CursorImage {
	// Return nil cursor image for macOS
	return nil
}