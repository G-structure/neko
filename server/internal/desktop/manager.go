package desktop

import (
	"os/exec"
	"runtime"
	"sync"
	"sync/atomic"
	"time"

	"github.com/kataras/go-events"
	"github.com/rs/zerolog"
	"github.com/rs/zerolog/log"

	"github.com/m1k1o/neko/server/internal/config"
	"github.com/m1k1o/neko/server/pkg/darwin"
	"github.com/m1k1o/neko/server/pkg/desktop"
	"github.com/m1k1o/neko/server/pkg/types"
	"github.com/m1k1o/neko/server/pkg/xevent"
	"github.com/m1k1o/neko/server/pkg/xinput"
	"github.com/m1k1o/neko/server/pkg/xorg"
)

var mu = sync.Mutex{}

type DesktopManagerCtx struct {
	logger     zerolog.Logger
	wg         sync.WaitGroup
	shutdown   chan struct{}
	emmiter    events.EventEmmiter
	config     *config.Desktop
	screenSize types.ScreenSize // cached screen size

	// Platform-specific backend
	backend    desktop.Backend

	// Linux-specific (will be nil on macOS)
	input      xinput.Driver

	// Clipboard process holding the most recent clipboard data.
	// It must remain running to allow pasting clipboard data.
	// The last command is kept running until it is replaced or shutdown.
	clipboardCommand atomic.Pointer[exec.Cmd]
}

func New(config *config.Desktop) *DesktopManagerCtx {
	// Create platform-specific backend
	var backend desktop.Backend
	var input xinput.Driver

	switch runtime.GOOS {
	case "darwin":
		backend = darwin.NewBackend()
	case "linux":
		backend = xorg.NewBackend()

		// Linux-specific input driver
		if config.UseInputDriver {
			input = xinput.NewDriver(config.InputSocket)
		} else {
			input = xinput.NewDummy()
		}
	default:
		log.Panic().Str("os", runtime.GOOS).Msg("unsupported operating system")
	}

	return &DesktopManagerCtx{
		logger:     log.With().Str("module", "desktop").Logger(),
		shutdown:   make(chan struct{}),
		emmiter:    events.New(),
		config:     config,
		screenSize: config.ScreenSize,
		backend:    backend,
		input:      input,
	}
}

func (manager *DesktopManagerCtx) Start() {
	// Initialize backend
	if err := manager.backend.Init(manager.config.Display); err != nil {
		manager.logger.Panic().Err(err).Msg("unable to initialize desktop backend")
	}

	// Linux-specific initialization
	if runtime.GOOS == "linux" {
		// X11 can throw errors below, and the default error handler exits
		xevent.SetupErrorHandler()

		// Get screen configurations
		manager.backend.GetScreenConfigurations()

		// Set initial screen size
		screenSize, err := manager.backend.SetScreenSize(manager.config.ScreenSize)
		if err != nil {
			manager.logger.Err(err).
				Str("screen_size", screenSize.String()).
				Msgf("unable to set initial screen size")
		} else {
			// cache screen size
			manager.screenSize = screenSize
			manager.logger.Info().
				Str("screen_size", screenSize.String()).
				Msgf("setting initial screen size")
		}

		// Connect input driver
		if manager.input != nil {
			err = manager.input.Connect()
			if err != nil {
				// TODO: fail silently to dummy driver?
				manager.logger.Panic().Err(err).Msg("unable to connect to input driver")
			}
		}

		// Set up event listeners
		xevent.Unminimize = manager.config.Unminimize
		xevent.FileChooserDialog = manager.config.FileChooserDialog
		go xevent.EventLoop(manager.config.Display)

		// In case it was opened
		if manager.config.FileChooserDialog {
			go manager.CloseFileChooserDialog()
		}

		manager.OnEventError(func(error_code uint8, message string, request_code uint8, minor_code uint8) {
			manager.logger.Warn().
				Uint8("error_code", error_code).
				Str("message", message).
				Uint8("request_code", request_code).
				Uint8("minor_code", minor_code).
				Msg("X event error occured")
		})
	} else if runtime.GOOS == "darwin" {
		// macOS-specific initialization
		// Get current screen size (can't change it on macOS)
		manager.screenSize = manager.backend.GetScreenSize()
		manager.logger.Info().
			Str("screen_size", manager.screenSize.String()).
			Msg("detected screen size")
	}

	// Start debounce goroutine
	manager.wg.Add(1)
	go func() {
		defer manager.wg.Done()

		ticker := time.NewTicker(1 * time.Second)
		defer ticker.Stop()

		const debounceDuration = 10 * time.Second

		for {
			select {
			case <-manager.shutdown:
				return
			case <-ticker.C:
				// Reset stuck keys
				if runtime.GOOS == "linux" {
					// Use xorg.CheckKeys for Linux
					xorg.CheckKeys(debounceDuration)
					if manager.input != nil {
						manager.input.Debounce(debounceDuration)
					}
				}
				// macOS doesn't need key debouncing as RobotGo handles it
			}
		}
	}()
}

func (manager *DesktopManagerCtx) OnBeforeScreenSizeChange(listener func()) {
	manager.emmiter.On("before_screen_size_change", func(payload ...any) {
		listener()
	})
}

func (manager *DesktopManagerCtx) OnAfterScreenSizeChange(listener func()) {
	manager.emmiter.On("after_screen_size_change", func(payload ...any) {
		listener()
	})
}

func (manager *DesktopManagerCtx) Shutdown() error {
	manager.logger.Info().Msgf("shutdown")

	close(manager.shutdown)

	manager.replaceClipboardCommand(nil)
	manager.wg.Wait()

	// Shutdown backend
	manager.backend.Shutdown()

	return nil
}

// Add more methods that delegate to the backend...