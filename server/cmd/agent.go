package cmd

import (
	"fmt"
	"os"
	"os/signal"

	"github.com/rs/zerolog"
	"github.com/rs/zerolog/log"
	"github.com/spf13/cobra"

	"github.com/m1k1o/neko/server/internal/agent"
	"github.com/m1k1o/neko/server/internal/capture"
	"github.com/m1k1o/neko/server/internal/config"
	"github.com/m1k1o/neko/server/internal/desktop"
	"github.com/m1k1o/neko/server/internal/http"
	"github.com/m1k1o/neko/server/internal/webrtc"
	"github.com/m1k1o/neko/server/internal/websocket"
	"github.com/m1k1o/neko/server/pkg/utils"
)

func init() {
	agentCmd := agentServe{}

	command := &cobra.Command{
		Use:   "agent",
		Short: "serve minimal neko agent (single-user, no auth)",
		Long:  `serve minimal neko agent for desktop streaming without multi-user features`,
		PreRun: agentCmd.PreRun,
		Run:   agentCmd.Run,
	}

	if err := agentCmd.Init(command); err != nil {
		log.Panic().Err(err).Msg("unable to initialize agent configuration")
	}

	root.AddCommand(command)
}

type agentServe struct {
	logger zerolog.Logger
	token  string

	configs struct {
		Desktop config.Desktop
		Capture config.Capture
		WebRTC  config.WebRTC
		Server  config.Server
	}

	managers struct {
		desktop   *desktop.DesktopManagerCtx
		capture   *capture.CaptureManagerCtx
		webRTC    *webrtc.WebRTCManagerCtx
		session   *agent.SingleSessionManager
		webSocket *websocket.WebSocketManagerCtx
		api       *agent.ApiManagerCtx
		http      *http.HttpManagerCtx
	}
}

func (c *agentServe) Init(cmd *cobra.Command) error {
	// Add agent-specific flag for token
	cmd.Flags().String("token", "", "authentication token for agent connection")

	// Initialize configurations
	if err := c.configs.Desktop.Init(cmd); err != nil {
		return err
	}
	if err := c.configs.Capture.Init(cmd); err != nil {
		return err
	}
	if err := c.configs.WebRTC.Init(cmd); err != nil {
		return err
	}
	if err := c.configs.Server.Init(cmd); err != nil {
		return err
	}

	return nil
}

func (c *agentServe) PreRun(cmd *cobra.Command, args []string) {
	c.logger = log.With().Str("service", "neko-agent").Logger()

	// Get or generate token
	token, _ := cmd.Flags().GetString("token")
	if token == "" {
		// Generate a random token if not provided
		token, _ = utils.NewUID(32)
	}
	c.token = token

	// Set configurations
	c.configs.Desktop.Set()
	c.configs.Capture.Set()
	c.configs.WebRTC.Set()
	c.configs.Server.Set()

	// Override some settings for agent mode
	// Ensure we have a display (auto-detect if not set)
	if c.configs.Desktop.Display == "" {
		display := os.Getenv("DISPLAY")
		if display == "" {
			display = ":0"
		}
		c.configs.Desktop.Display = display
		c.logger.Info().Str("display", display).Msg("auto-detected display")
	}

	// Ensure capture display matches desktop
	if c.configs.Capture.Display == "" {
		c.configs.Capture.Display = c.configs.Desktop.Display
	}
}

func (c *agentServe) Start(cmd *cobra.Command) {
	// Create minimal session manager with single session
	c.managers.session = agent.NewSingleSessionManager(c.token)

	// Important: Print connection info prominently
	fmt.Println()
	fmt.Println("=====================================")
	fmt.Println("Neko Agent Started")
	fmt.Println("=====================================")
	fmt.Printf("Connect with token: %s\n", c.token)
	fmt.Printf("WebSocket URL: ws://%s%s/api/ws\n", c.configs.Server.Bind, c.configs.Server.PathPrefix)
	fmt.Printf("Display: %s\n", c.configs.Desktop.Display)
	fmt.Println("=====================================")
	fmt.Println()

	// Log the same info
	c.logger.Info().
		Str("token", c.token).
		Str("bind", c.configs.Server.Bind).
		Str("display", c.configs.Desktop.Display).
		Msg("agent session ready")

	// Create and start desktop manager
	c.managers.desktop = desktop.New(
		&c.configs.Desktop,
	)
	c.managers.desktop.Start()

	// Create and start capture manager
	c.managers.capture = capture.New(
		c.managers.desktop,
		&c.configs.Capture,
	)
	c.managers.capture.Start()

	// Create and start WebRTC manager
	c.managers.webRTC = webrtc.New(
		c.managers.desktop,
		c.managers.capture,
		&c.configs.WebRTC,
	)
	c.managers.webRTC.Start()

	// Create and start WebSocket manager
	c.managers.webSocket = websocket.New(
		c.managers.session,
		c.managers.desktop,
		c.managers.capture,
		c.managers.webRTC,
	)
	c.managers.webSocket.Start()

	// Create minimal API manager
	c.managers.api = agent.NewApiManager(
		c.managers.session,
		c.managers.desktop,
		c.managers.capture,
	)

	// Create and start HTTP manager
	c.managers.http = http.New(
		c.managers.webSocket,
		c.managers.api,
		&c.configs.Server,
	)
	c.managers.http.Start()
}

func (c *agentServe) Shutdown() {
	var err error

	err = c.managers.http.Shutdown()
	c.logger.Err(err).Msg("http manager shutdown")

	err = c.managers.webSocket.Shutdown()
	c.logger.Err(err).Msg("websocket manager shutdown")

	err = c.managers.webRTC.Shutdown()
	c.logger.Err(err).Msg("webrtc manager shutdown")

	err = c.managers.capture.Shutdown()
	c.logger.Err(err).Msg("capture manager shutdown")

	err = c.managers.desktop.Shutdown()
	c.logger.Err(err).Msg("desktop manager shutdown")
}

func (c *agentServe) Run(cmd *cobra.Command, args []string) {
	c.logger.Info().Msg("starting neko agent")
	c.Start(cmd)
	c.logger.Info().Msg("neko agent ready")

	// Wait for interrupt signal
	quit := make(chan os.Signal, 1)
	signal.Notify(quit, os.Interrupt)
	sig := <-quit

	c.logger.Warn().Msgf("received %s, attempting graceful shutdown", sig)
	c.Shutdown()
	c.logger.Info().Msg("shutdown complete")
}