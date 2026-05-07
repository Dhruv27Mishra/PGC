/*
 * pthread_barrier_compat.h
 *
 * Apple's libpthread does not ship pthread_barrier_t. This header provides a
 * minimal POSIX-compatible implementation so the CPU sources build unchanged
 * on macOS in addition to glibc-based Linux. The fallback is condition-variable
 * based and is only used when the platform is detected to lack barriers.
 *
 * This file has no effect on Linux: it simply forwards to the system header.
 */

#ifndef PGC_PTHREAD_BARRIER_COMPAT_H
#define PGC_PTHREAD_BARRIER_COMPAT_H

#include <pthread.h>

#if defined(__APPLE__) || (!defined(_POSIX_BARRIERS) || _POSIX_BARRIERS <= 0)

#ifdef __cplusplus
extern "C" {
#endif

typedef int pthread_barrierattr_t;

typedef struct {
    pthread_mutex_t mutex;
    pthread_cond_t  cond;
    unsigned int    count;
    unsigned int    tripCount;
} pthread_barrier_t;

static inline int pthread_barrier_init(pthread_barrier_t *barrier,
                                       const pthread_barrierattr_t *attr,
                                       unsigned int count) {
    (void)attr;
    if (count == 0) return -1;
    if (pthread_mutex_init(&barrier->mutex, 0) != 0) return -1;
    if (pthread_cond_init(&barrier->cond, 0) != 0) {
        pthread_mutex_destroy(&barrier->mutex);
        return -1;
    }
    barrier->tripCount = count;
    barrier->count     = 0;
    return 0;
}

static inline int pthread_barrier_destroy(pthread_barrier_t *barrier) {
    pthread_cond_destroy(&barrier->cond);
    pthread_mutex_destroy(&barrier->mutex);
    return 0;
}

static inline int pthread_barrier_wait(pthread_barrier_t *barrier) {
    pthread_mutex_lock(&barrier->mutex);
    ++barrier->count;
    if (barrier->count >= barrier->tripCount) {
        barrier->count = 0;
        pthread_cond_broadcast(&barrier->cond);
        pthread_mutex_unlock(&barrier->mutex);
        return 1;
    } else {
        pthread_cond_wait(&barrier->cond, &(barrier->mutex));
        pthread_mutex_unlock(&barrier->mutex);
        return 0;
    }
}

#ifdef __cplusplus
} /* extern "C" */
#endif

#endif /* __APPLE__ */

#endif /* PGC_PTHREAD_BARRIER_COMPAT_H */
