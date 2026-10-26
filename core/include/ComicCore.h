#ifndef COMIC_CORE_H
#define COMIC_CORE_H
#include <stdint.h>
#include <stddef.h>
#ifdef __cplusplus
extern "C" {
#endif
/* Packed, opaque sRGB RGBA8. Input and output must not alias. */
typedef struct {
    float brightness; /* -1..1 additive */
    float contrast;   /* 0..3, pivot .5 */
    float gamma;      /* .2..3, exponent: >1 darkens */
    float white_point; /* .2..1 */
    float sharpen;    /* 0..2 */
    float blur;       /* 0..1 */
    float scale;      /* .1..2 */
    float crop;       /* 0..0.2: symmetric fraction per edge */
    int32_t grayscale;
    int32_t levels;    /* 0 (continuous) or 2..256, implies grayscale */
    int32_t auto_levels;
    int32_t rotation;  /* 0,1,2,3 clockwise quarter turns */
    int32_t page;      /* 0 whole, 1 left, 2 right */
    int32_t threads;   /* 0 automatic (capped at 8) */
    int32_t binarization; /* 0 off, 1 fixed, 2 Otsu, 3 Sauvola */
    float threshold;     /* fixed 0..255 */
    int32_t adaptive_radius; /* 1..100 pixels */
    float sauvola_k;     /* 0..1 */
    int32_t cleanup;     /* 0 off, 1 isolated pixels, 2 majority, 3 opening, 4 closing */
    int32_t cleanup_passes; /* 1..3 */
    int32_t dither;      /* 0 none, 1 Bayer 4x4, 2 serpentine Floyd-Steinberg */
    int32_t blur_method; /* 0 Gaussian, 1 box, 2 median, 3 bilateral */
    int32_t filter_radius; /* 1..3 */
    float edge_sigma;    /* bilateral range sigma 1..100 */
    int32_t sharpen_method; /* 0 unsharp mask, 1 four-neighbor Laplacian */
    float sharpen_threshold; /* 0..255, ignore weaker differences */
    int32_t deskew;      /* 0 off, 1 horizontal text, 2 vertical text */
    float deskew_limit;  /* automatic search +/- 1..10 degrees */
    float angle;         /* manual clockwise -15..15 degrees, added after auto */
} CEOptions;
CEOptions ce_defaults(void);
/* Estimate a correction angle; blank/low-confidence pages return zero.
   Returns 0 on success; same argument/resource errors as ce_dimensions. */
int ce_estimate_skew(const uint8_t *src, uint32_t width, uint32_t height,
                     int32_t vertical, float limit, float *degrees);
/* Returns 0 on success; -1 invalid args, -2 dimensions/resource limit,
   -3 insufficient destination capacity, -4 allocation failure. Max 40 MP. */
int ce_dimensions(uint32_t width, uint32_t height, const CEOptions *options,
                  uint32_t *out_width, uint32_t *out_height);
int ce_process(const uint8_t *src, uint32_t width, uint32_t height,
               const CEOptions *options, uint8_t *dst, size_t capacity);
#ifdef __cplusplus
}
#endif
#endif
