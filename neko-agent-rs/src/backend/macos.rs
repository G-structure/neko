use super::DesktopBackend;
use crate::types::{KeyboardModifiers, MouseButton, ScreenSize};
use anyhow::{anyhow, Result};
use core_graphics::display::{CGDisplay, CGMainDisplayID};
use core_graphics::event::{CGEvent, CGEventTapLocation, CGEventType, CGMouseButton, EventField};
use core_graphics::event_source::{CGEventSource, CGEventSourceStateID};
use parking_lot::Mutex;
use std::collections::HashMap;

/// macOS implementation of the desktop backend
pub struct MacOSBackend {
    screen_size: Mutex<ScreenSize>,
    pressed_buttons: Mutex<HashMap<MouseButton, bool>>,
    pressed_keys: Mutex<HashMap<u32, bool>>,
    modifiers: Mutex<KeyboardModifiers>,
}

impl MacOSBackend {
    pub fn new() -> Self {
        Self {
            screen_size: Mutex::new(ScreenSize::new(1920, 1080, 60)),
            pressed_buttons: Mutex::new(HashMap::new()),
            pressed_keys: Mutex::new(HashMap::new()),
            modifiers: Mutex::new(KeyboardModifiers::default()),
        }
    }

    /// Check if the app has required permissions
    fn check_permissions() -> Result<()> {
        // macOS requires:
        // 1. Screen Recording permission (for screen capture)
        // 2. Accessibility permission (for input control)

        // Note: These permissions must be granted in System Settings
        // We can't programmatically check them easily, but we'll try to use the APIs
        // and let macOS prompt the user if needed

        Ok(())
    }
}

impl DesktopBackend for MacOSBackend {
    fn init(&mut self, _display: Option<String>) -> Result<()> {
        // Check permissions (will fail gracefully)
        Self::check_permissions()?;

        // Get the main display
        let display_id = unsafe { CGMainDisplayID() };
        let display = CGDisplay::new(display_id);

        let width = display.pixels_wide() as u32;
        let height = display.pixels_high() as u32;

        // macOS doesn't easily expose refresh rate, default to 60Hz
        let rate = 60;

        *self.screen_size.lock() = ScreenSize::new(width, height, rate);

        Ok(())
    }

    fn shutdown(&mut self) {
        // Reset all keys and buttons
        self.reset_keys();
    }

    fn get_screen_size(&self) -> ScreenSize {
        *self.screen_size.lock()
    }

    fn take_screenshot(&self) -> Result<Vec<u8>> {
        // This would use CGDisplayCreateImage
        // For now, return empty - GStreamer will handle actual capture
        Ok(Vec::new())
    }

    fn move_mouse(&mut self, x: i32, y: i32) {
        let source = CGEventSource::new(CGEventSourceStateID::HIDSystemState)
            .expect("Failed to create event source");

        let event = CGEvent::new_mouse_event(
            source.clone(),
            CGEventType::MouseMoved,
            (x as f64, y as f64).into(),
            CGMouseButton::Left,
        ).expect("Failed to create mouse move event");

        event.post(CGEventTapLocation::HID);
    }

    fn get_cursor_position(&self) -> (i32, i32) {
        if let Ok(event) = CGEvent::new(CGEventSource::new(CGEventSourceStateID::HIDSystemState).unwrap()) {
            let loc = event.location();
            (loc.x as i32, loc.y as i32)
        } else {
            (0, 0)
        }
    }

    fn scroll(&mut self, delta_x: i32, delta_y: i32, _control_key: bool) {
        let source = CGEventSource::new(CGEventSourceStateID::HIDSystemState)
            .expect("Failed to create event source");

        // Create scroll event
        // Note: macOS uses pixel deltas for scrolling
        let event = CGEvent::new_scroll_event(
            source,
            core_graphics::event::ScrollEventUnit::Pixel,
            2, // wheel count
            delta_y,
            delta_x,
            0,
        ).expect("Failed to create scroll event");

        event.post(CGEventTapLocation::HID);
    }

    fn button_down(&mut self, button: MouseButton) -> Result<()> {
        let mut pressed = self.pressed_buttons.lock();

        if pressed.get(&button).copied().unwrap_or(false) {
            return Err(anyhow!("Button {:?} already pressed", button));
        }

        let source = CGEventSource::new(CGEventSourceStateID::HIDSystemState)
            .map_err(|_| anyhow!("Failed to create event source"))?;

        let (event_type, cg_button) = match button {
            MouseButton::Left => (CGEventType::LeftMouseDown, CGMouseButton::Left),
            MouseButton::Middle => (CGEventType::OtherMouseDown, CGMouseButton::Center),
            MouseButton::Right => (CGEventType::RightMouseDown, CGMouseButton::Right),
            _ => return Err(anyhow!("Unsupported button: {:?}", button)),
        };

        let (x, y) = self.get_cursor_position();
        let event = CGEvent::new_mouse_event(
            source,
            event_type,
            (x as f64, y as f64).into(),
            cg_button,
        ).map_err(|_| anyhow!("Failed to create button down event"))?;

        event.post(CGEventTapLocation::HID);
        pressed.insert(button, true);

        Ok(())
    }

    fn button_up(&mut self, button: MouseButton) -> Result<()> {
        let mut pressed = self.pressed_buttons.lock();

        if !pressed.get(&button).copied().unwrap_or(false) {
            return Err(anyhow!("Button {:?} not pressed", button));
        }

        let source = CGEventSource::new(CGEventSourceStateID::HIDSystemState)
            .map_err(|_| anyhow!("Failed to create event source"))?;

        let (event_type, cg_button) = match button {
            MouseButton::Left => (CGEventType::LeftMouseUp, CGMouseButton::Left),
            MouseButton::Middle => (CGEventType::OtherMouseUp, CGMouseButton::Center),
            MouseButton::Right => (CGEventType::RightMouseUp, CGMouseButton::Right),
            _ => return Err(anyhow!("Unsupported button: {:?}", button)),
        };

        let (x, y) = self.get_cursor_position();
        let event = CGEvent::new_mouse_event(
            source,
            event_type,
            (x as f64, y as f64).into(),
            cg_button,
        ).map_err(|_| anyhow!("Failed to create button up event"))?;

        event.post(CGEventTapLocation::HID);
        pressed.remove(&button);

        Ok(())
    }

    fn key_down(&mut self, keycode: u32) -> Result<()> {
        let mut pressed = self.pressed_keys.lock();

        if pressed.get(&keycode).copied().unwrap_or(false) {
            return Err(anyhow!("Key {} already pressed", keycode));
        }

        let source = CGEventSource::new(CGEventSourceStateID::HIDSystemState)
            .map_err(|_| anyhow!("Failed to create event source"))?;

        // Convert X11/Linux keycode to macOS virtual keycode
        // This is a simplified mapping - full implementation would need a complete keymap
        let macos_keycode = convert_keycode_to_macos(keycode);

        let event = CGEvent::new_keyboard_event(source, macos_keycode as u16, true)
            .map_err(|_| anyhow!("Failed to create key down event"))?;

        event.post(CGEventTapLocation::HID);
        pressed.insert(keycode, true);

        Ok(())
    }

    fn key_up(&mut self, keycode: u32) -> Result<()> {
        let mut pressed = self.pressed_keys.lock();

        if !pressed.get(&keycode).copied().unwrap_or(false) {
            return Err(anyhow!("Key {} not pressed", keycode));
        }

        let source = CGEventSource::new(CGEventSourceStateID::HIDSystemState)
            .map_err(|_| anyhow!("Failed to create event source"))?;

        let macos_keycode = convert_keycode_to_macos(keycode);

        let event = CGEvent::new_keyboard_event(source, macos_keycode as u16, false)
            .map_err(|_| anyhow!("Failed to create key up event"))?;

        event.post(CGEventTapLocation::HID);
        pressed.remove(&keycode);

        Ok(())
    }

    fn reset_keys(&mut self) {
        let mut pressed_keys = self.pressed_keys.lock();
        let mut pressed_buttons = self.pressed_buttons.lock();

        // Release all keys
        if let Ok(source) = CGEventSource::new(CGEventSourceStateID::HIDSystemState) {
            for keycode in pressed_keys.keys() {
                let macos_keycode = convert_keycode_to_macos(*keycode);
                if let Ok(event) = CGEvent::new_keyboard_event(source.clone(), macos_keycode as u16, false) {
                    event.post(CGEventTapLocation::HID);
                }
            }
        }

        pressed_keys.clear();
        pressed_buttons.clear();
        *self.modifiers.lock() = KeyboardModifiers::default();
    }

    fn set_keyboard_modifiers(&mut self, modifiers: KeyboardModifiers) {
        *self.modifiers.lock() = modifiers;

        // Set modifier flags in events
        // This would need to be applied to the next keyboard event
    }

    fn get_keyboard_modifiers(&self) -> KeyboardModifiers {
        *self.modifiers.lock()
    }

    fn set_clipboard(&mut self, text: &str) -> Result<()> {
        // Use cocoa/AppKit for clipboard access
        #[cfg(target_os = "macos")]
        {
            use cocoa::appkit::NSPasteboard;
            use cocoa::base::{id, nil};
            use cocoa::foundation::{NSArray, NSString};
            use objc::runtime::Object;

            unsafe {
                let pasteboard: id = NSPasteboard::generalPasteboard(nil);
                pasteboard.clearContents();

                let ns_string = NSString::alloc(nil).init_str(text);
                let objects = NSArray::arrayWithObject(nil, ns_string);
                pasteboard.writeObjects(objects);
            }
        }

        Ok(())
    }

    fn get_clipboard(&self) -> Result<String> {
        #[cfg(target_os = "macos")]
        {
            use cocoa::appkit::NSPasteboard;
            use cocoa::base::{id, nil};
            use cocoa::foundation::NSString;
            use objc::*;

            unsafe {
                let pasteboard: id = NSPasteboard::generalPasteboard(nil);
                let contents: id = msg_send![pasteboard, stringForType:1]; // NSPasteboardTypeString

                if contents == nil {
                    return Ok(String::new());
                }

                let string = NSString::UTF8String(contents as id);
                let c_str = std::ffi::CStr::from_ptr(string);
                Ok(c_str.to_string_lossy().into_owned())
            }
        }

        #[cfg(not(target_os = "macos"))]
        Ok(String::new())
    }
}

/// Convert X11/Linux keycode to macOS virtual keycode
/// This is a simplified mapping - a complete implementation would need full keymap
fn convert_keycode_to_macos(keycode: u32) -> u32 {
    // Common keys mapping (X11 keycode -> macOS virtual keycode)
    match keycode {
        // Letters a-z (X11: 38-61 -> macOS: 0-25)
        38..=61 => keycode - 38,
        // Numbers 0-9
        10..=19 => {
            if keycode == 19 { 29 } // 0
            else { keycode - 10 + 18 } // 1-9
        }
        // Return/Enter
        36 => 36,
        // Escape
        9 => 53,
        // Space
        65 => 49,
        // Tab
        23 => 48,
        // Backspace
        22 => 51,
        // Default: pass through (will likely not work correctly)
        _ => keycode,
    }
}
