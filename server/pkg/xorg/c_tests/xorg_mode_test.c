#include "xorg_mode.h"

#include <stdio.h>
#include <stdlib.h>

enum {
  MODE_60 = 60,
  CRTC_CURRENT_A = 101,
  CRTC_CURRENT_B = 102,
  CRTC_FULL = 201,
};

static int current_resource_calls;
static int full_resource_calls;
static int crtc_info_calls;
static int crtc_info_frees;
static int resource_frees;

static RRCrtc current_crtc_ids[] = {CRTC_CURRENT_A, CRTC_CURRENT_B};
static RRCrtc full_crtc_ids[] = {CRTC_FULL};
static XRRModeInfo modes[] = {{
  .id = MODE_60,
  .dotClock = 148500000,
  .hTotal = 2200,
  .vTotal = 1125,
}};
static XRRScreenResources current_resources = {
  .ncrtc = 1,
  .crtcs = current_crtc_ids,
  .nmode = 1,
  .modes = modes,
};
static XRRScreenResources full_resources = {
  .ncrtc = 1,
  .crtcs = full_crtc_ids,
  .nmode = 1,
  .modes = modes,
};
static XRRCrtcInfo current_crtc_a = {.mode = MODE_60};
static XRRCrtcInfo current_crtc_b = {.mode = MODE_60};
static XRRCrtcInfo full_crtc = {.mode = MODE_60};

static XRRScreenResources *fake_get_current_resources(Display *display,
                                                      Window root) {
  (void) display;
  (void) root;
  current_resource_calls++;
  return &current_resources;
}

static XRRScreenResources *fake_get_resources(Display *display, Window root) {
  (void) display;
  (void) root;
  full_resource_calls++;
  return &full_resources;
}

static XRRCrtcInfo *fake_get_crtc_info(Display *display,
                                       XRRScreenResources *resources,
                                       RRCrtc crtc) {
  (void) display;
  (void) resources;
  crtc_info_calls++;
  switch (crtc) {
    case CRTC_CURRENT_A:
      return &current_crtc_a;
    case CRTC_CURRENT_B:
      return &current_crtc_b;
    case CRTC_FULL:
      return &full_crtc;
    default:
      return NULL;
  }
}

static void fake_free_crtc_info(XRRCrtcInfo *crtc) {
  (void) crtc;
  crtc_info_frees++;
}

static void fake_free_resources(XRRScreenResources *resources) {
  (void) resources;
  resource_frees++;
}

static const NekoXRRModeOps fake_ops = {
  .get_current_resources = fake_get_current_resources,
  .get_resources = fake_get_resources,
  .get_crtc_info = fake_get_crtc_info,
  .free_crtc_info = fake_free_crtc_info,
  .free_resources = fake_free_resources,
};

static void reset_resolver(void) {
  current_resource_calls = 0;
  full_resource_calls = 0;
  crtc_info_calls = 0;
  crtc_info_frees = 0;
  resource_frees = 0;
  current_resources.ncrtc = 1;
}

static void expect_count(const char *name, int actual, int expected) {
  if (actual != expected) {
    fprintf(stderr, "%s = %d, expected %d\n", name, actual, expected);
    exit(EXIT_FAILURE);
  }
}

static void expect_refresh(const char *name, const XRRModeInfo *mode,
                           short expected) {
  short actual = XGetModeRefresh(mode);
  if (actual != expected) {
    fprintf(stderr, "%s refresh = %d, expected %d\n", name, actual, expected);
    exit(EXIT_FAILURE);
  }
}

int main(void) {
  XRRModeInfo normal = {
    .dotClock = 148500000,
    .hTotal = 2200,
    .vTotal = 1125,
  };
  expect_refresh("normal", &normal, 60);

  XRRModeInfo doublescan = {
    .dotClock = 65000000,
    .hTotal = 1000,
    .vTotal = 500,
    .modeFlags = RR_DoubleScan,
  };
  expect_refresh("doublescan", &doublescan, 65);

  XRRModeInfo interlaced = {
    .dotClock = 74250000,
    .hTotal = 2200,
    .vTotal = 1125,
    .modeFlags = RR_Interlace,
  };
  expect_refresh("interlaced", &interlaced, 60);

  XRRModeInfo missing_clock = normal;
  missing_clock.dotClock = 0;
  expect_refresh("missing clock", &missing_clock, 0);

  XRRModeInfo missing_htotal = normal;
  missing_htotal.hTotal = 0;
  expect_refresh("missing htotal", &missing_htotal, 0);

  XRRModeInfo missing_vtotal = normal;
  missing_vtotal.vTotal = 0;
  expect_refresh("missing vtotal", &missing_vtotal, 0);
  expect_refresh("missing mode", NULL, 0);

  reset_resolver();
  expect_count("current refresh",
               XGetPhysicalModeRefresh(NULL, None, &fake_ops), 60);
  expect_count("current resource calls", current_resource_calls, 1);
  expect_count("full resource calls", full_resource_calls, 0);
  expect_count("current CRTC info calls", crtc_info_calls, 1);
  expect_count("current CRTC info frees", crtc_info_frees, 1);
  expect_count("current resource frees", resource_frees, 1);

  /* Multiple active CRTCs are ambiguous, so retry with the full resources. */
  reset_resolver();
  current_resources.ncrtc = 2;
  expect_count("fallback refresh",
               XGetPhysicalModeRefresh(NULL, None, &fake_ops), 60);
  expect_count("fallback current resource calls", current_resource_calls, 1);
  expect_count("fallback full resource calls", full_resource_calls, 1);
  expect_count("fallback CRTC info calls", crtc_info_calls, 3);
  expect_count("fallback CRTC info frees", crtc_info_frees, 3);
  expect_count("fallback resource frees", resource_frees, 2);

  return EXIT_SUCCESS;
}
