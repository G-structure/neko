use serde::{Deserialize, Serialize};
use std::time::SystemTime;

/// Screen size and refresh rate
#[derive(Debug, Clone, Copy, Serialize, Deserialize)]
pub struct ScreenSize {
    pub width: u32,
    pub height: u32,
    pub rate: u16,
}

impl ScreenSize {
    pub fn new(width: u32, height: u32, rate: u16) -> Self {
        Self {
            width,
            height,
            rate,
        }
    }
}

impl std::fmt::Display for ScreenSize {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "{}x{}@{}", self.width, self.height, self.rate)
    }
}

/// Mouse button codes
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum MouseButton {
    Left = 1,
    Middle = 2,
    Right = 3,
    ScrollUp = 4,
    ScrollDown = 5,
}

/// Keyboard modifiers
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct KeyboardModifiers {
    pub shift: bool,
    pub control: bool,
    pub alt: bool,
    pub super_key: bool,
}

impl Default for KeyboardModifiers {
    fn default() -> Self {
        Self {
            shift: false,
            control: false,
            alt: false,
            super_key: false,
        }
    }
}

/// Session state
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SessionState {
    pub is_connected: bool,
    pub is_watching: bool,
    pub connected_since: Option<SystemTime>,
    pub watching_since: Option<SystemTime>,
}

impl Default for SessionState {
    fn default() -> Self {
        Self {
            is_connected: false,
            is_watching: false,
            connected_since: None,
            watching_since: None,
        }
    }
}

/// Member profile
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MemberProfile {
    pub name: String,
    pub is_admin: bool,
    pub can_login: bool,
    pub can_connect: bool,
    pub can_watch: bool,
    pub can_host: bool,
    pub can_access_clipboard: bool,
}

impl Default for MemberProfile {
    fn default() -> Self {
        Self {
            name: "Agent".to_string(),
            is_admin: true,
            can_login: true,
            can_connect: true,
            can_watch: true,
            can_host: true,
            can_access_clipboard: true,
        }
    }
}

/// Session settings
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Settings {
    pub private_mode: bool,
    pub locked_logins: bool,
    pub locked_controls: bool,
    pub control_protection: bool,
    pub implicit_hosting: bool,
    pub inactive_cursors: bool,
    pub merciful_reconnect: bool,
    pub heartbeat_interval: u32,
}

impl Default for Settings {
    fn default() -> Self {
        Self {
            private_mode: false,
            locked_logins: true,
            locked_controls: false,
            control_protection: false,
            implicit_hosting: true,
            inactive_cursors: false,
            merciful_reconnect: true,
            heartbeat_interval: 10,
        }
    }
}

/// Cursor position
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Cursor {
    pub x: i32,
    pub y: i32,
}

/// Stats for the agent
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Stats {
    pub has_host: bool,
    pub host_id: String,
    pub server_started_at: SystemTime,
    pub total_users: u32,
    pub total_admins: u32,
}
