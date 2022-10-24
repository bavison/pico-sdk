/*
 * Copyright (c) 2020 Raspberry Pi (Trading) Ltd.
 *
 * SPDX-License-Identifier: BSD-3-Clause
 */

#include <stdlib.h>
#include <stdio.h>
#include "pico.h"
#include "pico/malloc.h"
#include "pico/platform.h"

#if PICO_USE_MALLOC_MUTEX
#include "pico/mutex.h"
auto_init_mutex(malloc_mutex);
#endif

/* We need macros that will expand their arguments before concatenating */
#define REAL_FUNC_EXP(x)    REAL_FUNC(x)
#define WRAPPER_FUNC_EXP(x) WRAPPER_FUNC(x)

#ifdef __ARMCOMPILER_VERSION
#include "pico/memmap.h"
#define STACK_LIMIT ((char *) PICO_RAM_LIMIT)
#else
extern char __StackLimit; /* Set by linker.  */
#define STACK_LIMIT &__StackLimit
#endif

static inline void check_alloc(__unused void *mem, __unused uint size) {
#if PICO_MALLOC_PANIC
    if (!mem || (((char *)mem) + size) > STACK_LIMIT) {
        panic("Out of memory");
    }
#endif
}

#ifdef __GNUC__

/* Just the one heap implementation */
#define PREFIX
#include "pico_malloc.h"

#elif defined __ICCARM__

/* Used when you select "No-free heap" in Project > Options... > General options > Library options 2 */
#define PREFIX __no_free_
#include "pico_malloc.h"
#undef PREFIX
/* Used when you select "Basic heap" in Project > Options... > General options > Library options 2 */
#define PREFIX __basic_
#include "pico_malloc.h"
#undef PREFIX
/* Used when you select "Advanced heap" in Project > Options... > General options > Library options 2 */
#define PREFIX __iar_dl
#include "pico_malloc.h"
#undef PREFIX

#else

#error Unsupported toolchain

#endif
