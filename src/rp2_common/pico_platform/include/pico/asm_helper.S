/*
 * Copyright (c) 2020 Raspberry Pi (Trading) Ltd.
 *
 * SPDX-License-Identifier: BSD-3-Clause
 */

#include "pico.h"

#define _align      .align
#define _asciz      .asciz
#define _byte       .byte
#define _end        .end
#define _equ        .equ
#define _hword      .hword
#define _word       .word

.syntax unified
.cpu cortex-m0plus
.thumb
.section .text

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

.macro __pre_init func, priority_string
.section .preinit_array.\priority_string
.align 2
    _word \func
.endm

.macro local_func x
.type \x,%function
.thumb_func
\x:
.endm

.macro weak_func x
.weak \x
.type \x,%function
.thumb_func
\x:
.endm
