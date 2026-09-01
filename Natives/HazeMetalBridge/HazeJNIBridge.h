#pragma once

#include <stddef.h>
#include <stdint.h>

#include <jni.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
    uint64_t generation;
    size_t floatCount;
    size_t vertexCount;
    int strideFloats;
    double checksum;
} HazeBridgeStats;

uint64_t HazeBridgeSubmitPackedVertices(
    const float *vertices,
    size_t floatCount,
    int strideFloats
);

HazeBridgeStats HazeBridgeGetStats(void);
float *HazeBridgeCopyLatestVertices(HazeBridgeStats *outStats);
void HazeBridgeFreeCopiedVertices(float *vertices);
void HazeBridgeReset(void);

#ifdef __cplusplus
}
#endif
