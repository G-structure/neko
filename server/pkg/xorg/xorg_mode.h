#ifndef NEKO_XORG_MODE_H
#define NEKO_XORG_MODE_H

#include <X11/extensions/Xrandr.h>

typedef struct {
  XRRScreenResources *(*get_current_resources)(Display *, Window);
  XRRScreenResources *(*get_resources)(Display *, Window);
  XRRCrtcInfo *(*get_crtc_info)(Display *, XRRScreenResources *, RRCrtc);
  void (*free_crtc_info)(XRRCrtcInfo *);
  void (*free_resources)(XRRScreenResources *);
} NekoXRRModeOps;

short XGetModeRefresh(const XRRModeInfo *mode);
short XGetPhysicalModeRefresh(Display *display, Window root,
                              const NekoXRRModeOps *ops);

#endif
