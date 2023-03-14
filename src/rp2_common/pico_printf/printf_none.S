/*
 * Copyright (c) 2020 Raspberry Pi (Trading) Ltd.
 *
 * SPDX-License-Identifier: BSD-3-Clause
 */

#include "pico/asm_helper.S"
#include "pico/bootrom/sf_table.h"

 wrapper_func sprintf
 wrapper_func snprintf
 wrapper_func vsnprintf
 regular_func printf_none_assert
    push {lr}       // keep stack trace sane
    ldr r0, =str
    bl panic

str:
    data_in_code_area
    _asciz "printf support is disabled"

 end
