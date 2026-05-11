/*
 * Copyright (c) 2026 Raspberry Pi Ltd.
 *
 * SPDX-License-Identifier: BSD-3-Clause
 */

#include "pico.h"
#include "arch/cc.h"

// lwIP is written on the assumption that LWIP_ASSERT() may return and
// follows many asserts with defensive code. This implementation is
// deliberately defined out-of-line, in a separate translation unit from
// its callers, and is not declared noreturn, so that compilers don't flag
// that defensive code as unreachable.
void pico_lwip_assert_handler(const char *x) {
    panic("%s", x);
}
