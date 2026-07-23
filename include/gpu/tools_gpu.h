#ifndef TOOLS_GPU_H
#define TOOLS_GPU_H

#if defined(RTE_RRTMGP_GPU_MEMPOOL_OWN)
#include "mem_pool_gpu.h"
#endif
#include <cstdio>

#if defined(__CUDACC__) && !defined(RTE_USE_KMM)

#define cuda_safe_call(err) Tools_gpu::__cuda_safe_call(err, __FILE__, __LINE__)
#define cuda_check_error()  Tools_gpu::__cuda_check_error(__FILE__, __LINE__)
#define cuda_check_memory() Tools_gpu::__cuda_check_memory(__FILE__, __LINE__)

void prepare_gpu_mempool();

namespace Tools_gpu
{
    /* CUDA error checking.
       In debug mode, GPUCHECKS is defined and all kernel calls are checked with cudaCheckError().
       All CUDA api calls are always checked with cudaSafeCall() */

    // Wrapper to check for errors in CUDA api calls (e.g. cudaMalloc)
    inline void __cuda_safe_call(cudaError err, const char *file, const int line)
    {
        if (cudaSuccess != err)
        {
            printf("cudaSafeCall() failed at %s:%i : %s\n", file, line, cudaGetErrorString(err));
            throw 1;
        }
    }

    // Function to check for errors in CUDA kernels. Call directly after kernel.
    inline void __cuda_check_error(const char *file, const int line)
    {
        #ifdef GPUCHECKS
        cudaError err = cudaGetLastError();
        if (cudaSuccess != err)
        {
            printf("cudaCheckError() failed at %s:%i : %s\n", file, line, cudaGetErrorString( err ) );
            throw 1;
        }

        err = cudaDeviceSynchronize();
        if (cudaSuccess != err)
        {
            printf("cudaCheckError() with sync failed at %s:%i : %s\n", file, line, cudaGetErrorString( err ) );
            throw 1;
        }
        #endif
    }

    // Check the memory usage.
    inline void __cuda_check_memory(const char *file, const int line)
    {
        #ifdef GPUCHECKS
        size_t free_byte, total_byte ;

        cudaError err = cudaMemGetInfo( &free_byte, &total_byte ) ;

        if ( cudaSuccess != err ){

            printf("Error: cudaMemGetInfo fails, %s \n", cudaGetErrorString(err) );
            throw 1;

        }

        double used_db = (double)total_byte - (double)free_byte ;

        printf("GPU memory usage at %s:%i: %f MB\n", file, line, used_db/(1024.0*1024.0));
        #endif
    }

    template<typename T>
    T* allocate_gpu(int length)
    {
        T* data_ptr = nullptr;

        #if defined(RTE_RRTMGP_GPU_MEMPOOL_NATIVE)
        prepare_gpu_mempool();
        cuda_safe_call(cudaMallocAsync((void **) &data_ptr, length*sizeof(T), 0));
        #elif defined(RTE_RRTMGP_GPU_MEMPOOL_OWN)
        data_ptr = (T*)(Memory_pool_gpu::get_instance().acquire(length*sizeof(T)));
        #else
        cuda_safe_call(cudaMalloc((void **) &data_ptr, length*sizeof(T)));
        #endif
        return data_ptr;
    }

    template<typename T>
    void free_gpu(T*& data_ptr)
    {
        #if defined(RTE_RRTMGP_GPU_MEMPOOL_NATIVE)
        cuda_safe_call(cudaFreeAsync(data_ptr, 0));
        #elif defined(RTE_RRTMGP_GPU_MEMPOOL_OWN)
        Memory_pool_gpu::get_instance().release((void*)data_ptr);
        #else
        cuda_safe_call(cudaFree(data_ptr));
        #endif
        data_ptr = nullptr;
    }

    inline dim3 calc_grid_size(const dim3 block, const dim3 total)
    {
        const int grid_x = total.x/block.x + (total.x%block.x > 0);
        const int grid_y = total.y/block.y + (total.y%block.y > 0);
        const int grid_z = total.z/block.z + (total.z%block.z > 0);

        return dim3(grid_x, grid_y, grid_z);
    }
}
#elif (defined(__CUDACC__) || defined(__HIPCC__)) && defined(RTE_USE_KMM)
#include "kmm/core/backends.hpp"
using kmm::gpu_error_t;

#define gpu_safe_call(err) Tools_gpu::__gpu_safe_call(err, __FILE__, __LINE__)
#define gpu_check_error()  Tools_gpu::__gpu_check_error(__FILE__, __LINE__)
#define gpu_check_memory() Tools_gpu::__gpu_check_memory(__FILE__, __LINE__)

void prepare_gpu_mempool();

namespace Tools_gpu
{
    /* GPU error checking.
       In debug mode, GPUCHECKS is defined and all kernel calls are checked with cudaCheckError().
       All GPU api calls are always checked with gpu_safe_call() */

    // Wrapper to check for errors in GPU api calls
    inline void __gpu_safe_call(gpu_error_t err, const char *file, const int line)
    {
        if (GPU_SUCCESS != err)
        {
            printf("gpu_safe_call() failed at %s:%i : %s\n", file, line, gpu_get_error_string(err));
            throw 1;
        }
    }

    // Function to check for errors in GPU kernels. Call directly after kernel.
    inline void __gpu_check_error(const char *file, const int line)
    {
        #ifdef GPUCHECKS
        gpu_error_t err = gpu_get_last_error();
        if (GPU_SUCCESS != err)
        {
            printf("gpu_check_error() failed at %s:%i : %s\n", file, line, gpu_get_error_string(err));
            throw 1;
        }

        err = gpu_device_synchronize();
        if (GPU_SUCCESS != err)
        {
            printf("gpu_check_error() with sync failed at %s:%i : %s\n", file, line, gpu_get_error_string(err));
            throw 1;
        }
        #endif
    }

    // Check the memory usage.
    inline void __gpu_check_memory(const char *file, const int line)
    {
        #ifdef GPUCHECKS
        size_t free_byte, total_byte ;

        gpu_error_t err = gpu_mem_get_info( &free_byte, &total_byte ) ;

        if (GPU_SUCCESS != err){

            printf("Error: gpu_mem_get_info fails, %s \n", gpu_get_error_string(err) );
            throw 1;

        }

        double used_db = (double)total_byte - (double)free_byte ;

        printf("GPU memory usage at %s:%i: %f MB\n", file, line, used_db/(1024.0*1024.0));
        #endif
    }

    template<typename T>
    T* allocate_gpu(int length)
    {
        T* data_ptr = nullptr;

        #if defined(RTE_RRTMGP_GPU_MEMPOOL_NATIVE)
        prepare_gpu_mempool();
        gpu_safe_call(gpu_malloc_async((void **) &data_ptr, length*sizeof(T), 0));
        #else
        gpu_safe_call(gpu_malloc((void **) &data_ptr, length*sizeof(T)));
        #endif
        return data_ptr;
    }

    template<typename T>
    void free_gpu(T*& data_ptr)
    {
        #if defined(RTE_RRTMGP_GPU_MEMPOOL_NATIVE)
        gpu_safe_call(gpu_free_async(data_ptr, 0));
        #else
        gpu_safe_call(gpu_free(data_ptr));
        #endif
        data_ptr = nullptr;
    }

    inline dim3 calc_grid_size(const dim3 block, const dim3 total)
    {
        const int grid_x = total.x/block.x + (total.x%block.x > 0);
        const int grid_y = total.y/block.y + (total.y%block.y > 0);
        const int grid_z = total.z/block.z + (total.z%block.z > 0);

        return dim3(grid_x, grid_y, grid_z);
    }
}

#endif // (__CUDACC__ && !RTE_USE_KMM) || ((__CUDACC__ || __HIPCC__) && RTE_USE_KMM)

#endif // TOOLS_GPU_H
