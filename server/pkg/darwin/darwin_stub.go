//go:build !darwin

package darwin

import (
	"github.com/m1k1o/neko/server/pkg/desktop"
	"github.com/m1k1o/neko/server/pkg/types"
)

// Stub implementation for non-macOS platforms
// The darwin package is not used on non-Darwin systems

// NewBackend stub - should not be called on non-macOS
func NewBackend() desktop.Backend {
	return nil
}

// GetCursorImage stub for non-macOS platforms
func GetCursorImage() *types.CursorImage {
	return nil
}
