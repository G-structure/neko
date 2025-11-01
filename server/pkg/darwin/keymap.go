// +build darwin

package darwin

// convertKeycode converts X11 keysyms to macOS key strings for RobotGo
func convertKeycode(code uint32) string {
	// This maps common X11 keysyms to RobotGo key strings
	// X11 keysyms are defined in server/pkg/xorg/keysymdef.go
	keymap := map[uint32]string{
		// Letters
		0x0061: "a", 0x0041: "a", // a, A
		0x0062: "b", 0x0042: "b", // b, B
		0x0063: "c", 0x0043: "c", // c, C
		0x0064: "d", 0x0044: "d", // d, D
		0x0065: "e", 0x0045: "e", // e, E
		0x0066: "f", 0x0046: "f", // f, F
		0x0067: "g", 0x0047: "g", // g, G
		0x0068: "h", 0x0048: "h", // h, H
		0x0069: "i", 0x0049: "i", // i, I
		0x006a: "j", 0x004a: "j", // j, J
		0x006b: "k", 0x004b: "k", // k, K
		0x006c: "l", 0x004c: "l", // l, L
		0x006d: "m", 0x004d: "m", // m, M
		0x006e: "n", 0x004e: "n", // n, N
		0x006f: "o", 0x004f: "o", // o, O
		0x0070: "p", 0x0050: "p", // p, P
		0x0071: "q", 0x0051: "q", // q, Q
		0x0072: "r", 0x0052: "r", // r, R
		0x0073: "s", 0x0053: "s", // s, S
		0x0074: "t", 0x0054: "t", // t, T
		0x0075: "u", 0x0055: "u", // u, U
		0x0076: "v", 0x0056: "v", // v, V
		0x0077: "w", 0x0057: "w", // w, W
		0x0078: "x", 0x0058: "x", // x, X
		0x0079: "y", 0x0059: "y", // y, Y
		0x007a: "z", 0x005a: "z", // z, Z

		// Numbers
		0x0030: "0", 0x0029: "0", // 0, )
		0x0031: "1", 0x0021: "1", // 1, !
		0x0032: "2", 0x0040: "2", // 2, @
		0x0033: "3", 0x0023: "3", // 3, #
		0x0034: "4", 0x0024: "4", // 4, $
		0x0035: "5", 0x0025: "5", // 5, %
		0x0036: "6", 0x005e: "6", // 6, ^
		0x0037: "7", 0x0026: "7", // 7, &
		0x0038: "8", 0x002a: "8", // 8, *
		0x0039: "9", 0x0028: "9", // 9, (

		// Function keys
		0xff08: "backspace",    // XK_BackSpace
		0xff09: "tab",          // XK_Tab
		0xff0d: "enter",        // XK_Return
		0xff13: "pause",        // XK_Pause
		0xff14: "scrolllock",   // XK_Scroll_Lock
		0xff1b: "escape",       // XK_Escape
		0xffff: "delete",       // XK_Delete
		0xff50: "home",         // XK_Home
		0xff51: "left",         // XK_Left
		0xff52: "up",           // XK_Up
		0xff53: "right",        // XK_Right
		0xff54: "down",         // XK_Down
		0xff55: "pageup",       // XK_Page_Up
		0xff56: "pagedown",     // XK_Page_Down
		0xff57: "end",          // XK_End
		0xff63: "insert",       // XK_Insert

		// F keys
		0xffbe: "f1",  // XK_F1
		0xffbf: "f2",  // XK_F2
		0xffc0: "f3",  // XK_F3
		0xffc1: "f4",  // XK_F4
		0xffc2: "f5",  // XK_F5
		0xffc3: "f6",  // XK_F6
		0xffc4: "f7",  // XK_F7
		0xffc5: "f8",  // XK_F8
		0xffc6: "f9",  // XK_F9
		0xffc7: "f10", // XK_F10
		0xffc8: "f11", // XK_F11
		0xffc9: "f12", // XK_F12

		// Modifiers
		0xffe1: "shift",   // XK_Shift_L
		0xffe2: "rshift",  // XK_Shift_R
		0xffe3: "ctrl",    // XK_Control_L
		0xffe4: "rctrl",   // XK_Control_R
		0xffe5: "capslock", // XK_Caps_Lock
		0xffe7: "lcmd",    // XK_Meta_L (Command on Mac)
		0xffe8: "rcmd",    // XK_Meta_R
		0xffe9: "alt",     // XK_Alt_L
		0xffea: "ralt",    // XK_Alt_R
		0xffeb: "cmd",     // XK_Super_L (Command on Mac)
		0xffec: "rcmd",    // XK_Super_R

		// Punctuation and symbols
		0x0020: "space",      // space
		0x0027: "'",          // apostrophe
		0x002c: ",",          // comma
		0x002d: "-",          // minus
		0x002e: ".",          // period
		0x002f: "/",          // slash
		0x003b: ";",          // semicolon
		0x003d: "=",          // equal
		0x005b: "[",          // bracketleft
		0x005c: "\\",         // backslash
		0x005d: "]",          // bracketright
		0x0060: "`",          // grave

		// Keypad
		0xff80: " ",           // XK_KP_Space
		0xff8d: "num_enter",   // XK_KP_Enter
		0xff95: "num_home",    // XK_KP_Home
		0xff96: "num_left",    // XK_KP_Left
		0xff97: "num_up",      // XK_KP_Up
		0xff98: "num_right",   // XK_KP_Right
		0xff99: "num_down",    // XK_KP_Down
		0xff9a: "num_pgup",    // XK_KP_Page_Up
		0xff9b: "num_pgdn",    // XK_KP_Page_Down
		0xff9c: "num_end",     // XK_KP_End
		0xff9e: "num_ins",     // XK_KP_Insert
		0xff9f: "num_del",     // XK_KP_Delete
		0xffaa: "num*",        // XK_KP_Multiply
		0xffab: "num+",        // XK_KP_Add
		0xffad: "num-",        // XK_KP_Subtract
		0xffae: "num.",        // XK_KP_Decimal
		0xffaf: "num/",        // XK_KP_Divide

		// Keypad numbers
		0xffb0: "num0", // XK_KP_0
		0xffb1: "num1", // XK_KP_1
		0xffb2: "num2", // XK_KP_2
		0xffb3: "num3", // XK_KP_3
		0xffb4: "num4", // XK_KP_4
		0xffb5: "num5", // XK_KP_5
		0xffb6: "num6", // XK_KP_6
		0xffb7: "num7", // XK_KP_7
		0xffb8: "num8", // XK_KP_8
		0xffb9: "num9", // XK_KP_9

		// Media keys
		0x1008ff11: "audio_vol_down",  // XF86AudioLowerVolume
		0x1008ff12: "audio_vol_mute",  // XF86AudioMute
		0x1008ff13: "audio_vol_up",    // XF86AudioRaiseVolume
		0x1008ff14: "audio_play",       // XF86AudioPlay
		0x1008ff15: "audio_stop",       // XF86AudioStop
		0x1008ff16: "audio_prev",       // XF86AudioPrev
		0x1008ff17: "audio_next",       // XF86AudioNext
	}

	if key, ok := keymap[code]; ok {
		return key
	}

	return ""
}