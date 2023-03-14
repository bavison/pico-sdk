/*
 * Copyright (c) 2020 Raspberry Pi (Trading) Ltd.
 *
 * SPDX-License-Identifier: BSD-3-Clause
 */

#include "pico.h"

#define alignrom    .align
#define _asciz      .asciz
#define dc8         .byte
#define dc16        .hword
#define dc32        .word
#define end         .end
#define endm        .endm
#define _equ        .equ
#define _macro(x)   .macro x
#define _macro_1arg(x,a)                   .macro x a
#define _macro_2args(x,a,b)                .macro x a,b
#define _macro_3args(x,a,b,c)              .macro x a,b,c
#define _macro_5args(x,a,b,c,d,e)          .macro x a,b,c,d,e
#define _macro_6args(x,a,b,c,d,e,f)        .macro x a,b,c,d,e,f
#define _macro_9args(x,a,b,c,d,e,f,g,h,i)  .macro x a,b,c,d,e,f,g,h,i
#define public      .global

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
endm

.macro regular_func_with_section x
.section .text.\x
 regular_func \x
endm

// do not put align in here as it is used mid function sometimes
.macro wrapper_func x
 regular_func WRAPPER_FUNC_NAME(\x)
endm

.macro __pre_init func, priority_string
.section .preinit_array.\priority_string
.align 2
    .word \func
endm

.macro local_func x
.type \x,%function
.thumb_func
\x:
endm

.macro weak_func x
.weak \x
.type \x,%function
.thumb_func
\x:
endm
