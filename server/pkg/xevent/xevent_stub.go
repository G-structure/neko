//go:build darwin

package xevent

import "github.com/kataras/go-events"

var Emmiter events.EventEmmiter
var Unminimize bool = false
var FileChooserDialog bool = false

func init() {
	Emmiter = events.New()
}

func Start() {
	// Stub for macOS
}

func ButtonPress(code uint32) {
	// Stub for macOS
}

func KeyPress(code uint32) {
	// Stub for macOS
}

func SetupErrorHandler() {
	// Stub for macOS
}

func EventLoop(display string) {
	// Stub for macOS - no X11 event loop needed
}