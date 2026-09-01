#import "HazeJNIBridge.h"

#include <pthread.h>
#include <stdlib.h>
#include <string.h>

static pthread_mutex_t HazeBridgeLock = PTHREAD_MUTEX_INITIALIZER;
static float *HazeLatestVertices = NULL;
static size_t HazeLatestFloatCount = 0;
static int HazeLatestStrideFloats = 0;
static uint64_t HazeLatestGeneration = 0;
static double HazeLatestChecksum = 0.0;

static double HazeCalculateChecksum(const float *vertices, size_t floatCount) {
    double checksum = 0.0;
    for (size_t index = 0; index < floatCount; index++) {
        checksum += (double)vertices[index];
    }
    return checksum;
}

uint64_t HazeBridgeSubmitPackedVertices(
    const float *vertices,
    size_t floatCount,
    int strideFloats
) {
    if (vertices == NULL || floatCount == 0 || strideFloats < 3) {
        return 0;
    }

    if ((floatCount % (size_t)strideFloats) != 0) {
        return 0;
    }

    if (floatCount > (SIZE_MAX / sizeof(float))) {
        return 0;
    }

    float *copy = malloc(floatCount * sizeof(float));
    if (copy == NULL) {
        return 0;
    }

    memcpy(copy, vertices, floatCount * sizeof(float));
    double checksum = HazeCalculateChecksum(copy, floatCount);

    pthread_mutex_lock(&HazeBridgeLock);
    free(HazeLatestVertices);
    HazeLatestVertices = copy;
    HazeLatestFloatCount = floatCount;
    HazeLatestStrideFloats = strideFloats;
    HazeLatestChecksum = checksum;
    HazeLatestGeneration++;
    uint64_t generation = HazeLatestGeneration;
    pthread_mutex_unlock(&HazeBridgeLock);

    return generation;
}

HazeBridgeStats HazeBridgeGetStats(void) {
    pthread_mutex_lock(&HazeBridgeLock);

    HazeBridgeStats stats = {
        .generation = HazeLatestGeneration,
        .floatCount = HazeLatestFloatCount,
        .vertexCount = HazeLatestStrideFloats > 0
            ? HazeLatestFloatCount / (size_t)HazeLatestStrideFloats
            : 0,
        .strideFloats = HazeLatestStrideFloats,
        .checksum = HazeLatestChecksum
    };

    pthread_mutex_unlock(&HazeBridgeLock);
    return stats;
}

float *HazeBridgeCopyLatestVertices(HazeBridgeStats *outStats) {
    if (outStats != NULL) {
        *outStats = (HazeBridgeStats){0};
    }

    pthread_mutex_lock(&HazeBridgeLock);

    if (HazeLatestVertices == NULL
            || HazeLatestFloatCount == 0
            || HazeLatestFloatCount > (SIZE_MAX / sizeof(float))) {
        pthread_mutex_unlock(&HazeBridgeLock);
        return NULL;
    }

    size_t byteCount = HazeLatestFloatCount * sizeof(float);
    float *snapshot = malloc(byteCount);
    if (snapshot == NULL) {
        pthread_mutex_unlock(&HazeBridgeLock);
        return NULL;
    }

    memcpy(snapshot, HazeLatestVertices, byteCount);

    if (outStats != NULL) {
        *outStats = (HazeBridgeStats){
            .generation = HazeLatestGeneration,
            .floatCount = HazeLatestFloatCount,
            .vertexCount = HazeLatestStrideFloats > 0
                ? HazeLatestFloatCount / (size_t)HazeLatestStrideFloats
                : 0,
            .strideFloats = HazeLatestStrideFloats,
            .checksum = HazeLatestChecksum
        };
    }

    pthread_mutex_unlock(&HazeBridgeLock);
    return snapshot;
}

void HazeBridgeFreeCopiedVertices(float *vertices) {
    free(vertices);
}

void HazeBridgeReset(void) {
    pthread_mutex_lock(&HazeBridgeLock);
    free(HazeLatestVertices);
    HazeLatestVertices = NULL;
    HazeLatestFloatCount = 0;
    HazeLatestStrideFloats = 0;
    HazeLatestGeneration = 0;
    HazeLatestChecksum = 0.0;
    pthread_mutex_unlock(&HazeBridgeLock);
}

#define HAZE_JNI_EXPORT JNIEXPORT __attribute__((used))

HAZE_JNI_EXPORT jlong JNICALL
Java_dev_haze_metal_NativeBridge_nativeSubmitVertices(
    JNIEnv *environment,
    jclass bridgeClass,
    jfloatArray vertices,
    jint strideFloats
) {
    (void)bridgeClass;

    if (environment == NULL || vertices == NULL) {
        return (jlong)-1;
    }

    jsize floatCount = (*environment)->GetArrayLength(environment, vertices);
    if (floatCount <= 0 || strideFloats < 3 || (floatCount % strideFloats) != 0) {
        return (jlong)-2;
    }

    float *temporary = malloc((size_t)floatCount * sizeof(float));
    if (temporary == NULL) {
        return (jlong)-3;
    }

    (*environment)->GetFloatArrayRegion(
        environment,
        vertices,
        0,
        floatCount,
        temporary
    );

    if ((*environment)->ExceptionCheck(environment)) {
        free(temporary);
        return (jlong)-4;
    }

    uint64_t generation = HazeBridgeSubmitPackedVertices(
        temporary,
        (size_t)floatCount,
        (int)strideFloats
    );

    free(temporary);
    return generation == 0 ? (jlong)-5 : (jlong)generation;
}

HAZE_JNI_EXPORT jlong JNICALL
Java_dev_haze_metal_NativeBridge_nativeGeneration(
    JNIEnv *environment,
    jclass bridgeClass
) {
    (void)environment;
    (void)bridgeClass;
    return (jlong)HazeBridgeGetStats().generation;
}

HAZE_JNI_EXPORT jint JNICALL
Java_dev_haze_metal_NativeBridge_nativeFloatCount(
    JNIEnv *environment,
    jclass bridgeClass
) {
    (void)environment;
    (void)bridgeClass;
    return (jint)HazeBridgeGetStats().floatCount;
}

HAZE_JNI_EXPORT jint JNICALL
Java_dev_haze_metal_NativeBridge_nativeVertexCount(
    JNIEnv *environment,
    jclass bridgeClass
) {
    (void)environment;
    (void)bridgeClass;
    return (jint)HazeBridgeGetStats().vertexCount;
}

HAZE_JNI_EXPORT jdouble JNICALL
Java_dev_haze_metal_NativeBridge_nativeChecksum(
    JNIEnv *environment,
    jclass bridgeClass
) {
    (void)environment;
    (void)bridgeClass;
    return (jdouble)HazeBridgeGetStats().checksum;
}

HAZE_JNI_EXPORT void JNICALL
Java_dev_haze_metal_NativeBridge_nativeReset(
    JNIEnv *environment,
    jclass bridgeClass
) {
    (void)environment;
    (void)bridgeClass;
    HazeBridgeReset();
}
