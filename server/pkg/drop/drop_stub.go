//go:build darwin

package drop

import (
	"github.com/kataras/go-events"
)

var Emmiter events.EventEmmiter

func init() {
	Emmiter = events.New()
}

func ListenersCount() int {
	return 0
}

func AddListener() {
	// Stub for macOS
}

func RemoveListener() {
	// Stub for macOS
}

func OpenWindow(files []string) {
	// Stub for macOS - drag and drop not implemented
}

func CloseWindow() {
	// Stub for macOS
}