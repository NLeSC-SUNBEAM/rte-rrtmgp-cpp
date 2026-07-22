#include <cstdint>
#include <cstdio>

#if defined(RTE_RRTMGP_GPU_MEMPOOL_NATIVE) && !defined(RTE_USE_KMM)
static bool native_mempool_initialized = false;

void prepare_gpu_mempool()
{
    if (native_mempool_initialized)
        return;

    printf("Setting up GPU native mempool.\n");
    cudaMemPool_t mempool;
    cudaDeviceGetDefaultMemPool(&mempool, 0);
    auto threshold = UINT64_MAX;
    cudaMemPoolSetAttribute(mempool, cudaMemPoolAttrReleaseThreshold, &threshold);
    native_mempool_initialized = true;
}
#elif defined(RTE_RRTMGP_GPU_MEMPOOL_NATIVE) && defined(RTE_USE_KMM)
#include "kmm/core/backends.hpp"

static bool native_mempool_initialized = false;

void prepare_gpu_mempool()
{
    if (native_mempool_initialized)
        return;

    printf("Setting up GPU native mempool.\n");
    gpu_mem_pool_t mempool;
    gpu_device_get_default_mem_pool(&mempool, 0);
    auto threshold = UINT64_MAX;
    gpu_mem_pool_set_attribute(mempool, g_mem_pool_attr_release_threshold, &threshold);
    native_mempool_initialized = true;
}
#endif
