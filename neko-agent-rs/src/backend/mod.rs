use crate::types::{KeyboardModifiers, MouseButton, ScreenSize};
use anyhow::Result;

#[cfg(target_os = "macos")]
pub mod macos;

#[cfg(target_os = "macos")]
pub use macos::MacOSBackend as PlatformBackend;

/// Desktop backend trait - defines platform-specific operations
pub trait DesktopBackend: Send + Sync {
    /// Initialize the backend
    fn init(&mut self, display: Option<String>) -> Result<()>;

    /// Cleanup resources
    fn shutdown(&mut self);

    // Screen operations
    fn get_screen_size(&self) -> ScreenSize;
    fn take_screenshot(&self) -> Result<Vec<u8>>;

    // Mouse operations
    fn move_mouse(&mut self, x: i32, y: i32);
    fn get_cursor_position(&self) -> (i32, i32);
    fn scroll(&mut self, delta_x: i32, delta_y: i32, control_key: bool);
    fn button_down(&mut self, button: MouseButton) -> Result<()>;
    fn button_up(&mut self, button: MouseButton) -> Result<()>;

    // Keyboard operations
    fn key_down(&mut self, keycode: u32) -> Result<()>;
    fn key_up(&mut self, keycode: u32) -> Result<()>;
    fn reset_keys(&mut self);
    fn set_keyboard_modifiers(&mut self, modifiers: KeyboardModifiers);
    fn get_keyboard_modifiers(&self) -> KeyboardModifiers;

    // Clipboard operations
    fn set_clipboard(&mut self, text: &str) -> Result<()>;
    fn get_clipboard(&self) -> Result<String>;
}
