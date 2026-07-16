#include "xorg_mode.h"

short XGetModeRefresh(const XRRModeInfo *mode) {
  if (mode == NULL || mode->dotClock == 0 || mode->hTotal == 0 ||
      mode->vTotal == 0) {
    return 0;
  }

  double vtotal = mode->vTotal;
  if (mode->modeFlags & RR_DoubleScan) {
    vtotal *= 2.0;
  }
  if (mode->modeFlags & RR_Interlace) {
    vtotal /= 2.0;
  }

  double refresh = (double) mode->dotClock / ((double) mode->hTotal * vtotal);
  return (short) (refresh + 0.5);
}

static short XGetResourcesModeRefresh(Display *display,
                                      XRRScreenResources *resources,
                                      const NekoXRRModeOps *ops) {
  RRMode active_mode = None;
  int active_crtcs = 0;

  for (int i = 0; i < resources->ncrtc; i++) {
    XRRCrtcInfo *crtc =
      ops->get_crtc_info(display, resources, resources->crtcs[i]);
    if (crtc != NULL && crtc->mode != None) {
      active_mode = crtc->mode;
      active_crtcs++;
    }
    if (crtc != NULL) {
      ops->free_crtc_info(crtc);
    }
  }

  if (active_crtcs != 1) {
    return 0;
  }

  for (int i = 0; i < resources->nmode; i++) {
    if (resources->modes[i].id == active_mode) {
      return XGetModeRefresh(&resources->modes[i]);
    }
  }
  return 0;
}

short XGetPhysicalModeRefresh(Display *display, Window root,
                              const NekoXRRModeOps *ops) {
  if (ops == NULL || ops->get_current_resources == NULL ||
      ops->get_resources == NULL || ops->get_crtc_info == NULL ||
      ops->free_crtc_info == NULL || ops->free_resources == NULL) {
    return 0;
  }

  XRRScreenResources *resources = ops->get_current_resources(display, root);
  short refresh = 0;
  if (resources != NULL) {
    refresh = XGetResourcesModeRefresh(display, resources, ops);
    ops->free_resources(resources);
  }

  if (refresh > 0) {
    return refresh;
  }

  resources = ops->get_resources(display, root);
  if (resources != NULL) {
    refresh = XGetResourcesModeRefresh(display, resources, ops);
    ops->free_resources(resources);
  }
  return refresh;
}
