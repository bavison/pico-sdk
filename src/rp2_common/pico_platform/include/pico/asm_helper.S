/*
 * Copyright (c) 2020 Raspberry Pi (Trading) Ltd.
 *
 * SPDX-License-Identifier: BSD-3-Clause
 */

#include "pico.h"

// do not put align in here as it is used mid function sometimes
.macro regular_func x
.global \x
.type \x,%function
.thumb_func
\x:
.endm

.macro regular_func_with_section x
.section .text.\x
regular_func \x
.endm

// do not put align in here as it is used mid function sometimes
.macro wrapper_func x
regular_func WRAPPER_FUNC_NAME(\x)
.endm

// gnu_func is for functions unique to GNU C libraries, so uses wrapper only in GNU case
.macro gnu_func x
 regular_func WRAPPER_FUNC_NAME(\x)
endm

.macro __pre_init func, priority_string
.section .preinit_array.\priority_string
.align 2
.word \func
.endm

#define code_in_code_area
#define data_in_code_area
