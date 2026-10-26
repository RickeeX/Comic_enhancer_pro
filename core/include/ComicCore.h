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
    float crop;       /* 0...2: symmetric fraction per edge */
    int32_t grayscale;
    int32_t levels;    /* 0 (continuous) or 2..256, implies grayscale */
    int32_t auto_levels;
    int32_t rotation;  /* 0,1,2,3 clockwise quarter turns */
    int32_t page;      /* 0 whole, 1 left, 2 right */
    int32_t threads;   /* 0 automatic (capped at 8) */
} CEOptions;
CEOptions ce_defaults(void);
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
