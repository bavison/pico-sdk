/*
 * Copyright (c) 2020 Raspberry Pi (Trading) Ltd.
 *
 * SPDX-License-Identifier: BSD-3-Clause
 */

#ifndef INCLUDED_ASM_HELPER_S
#define INCLUDED_ASM_HELPER_S

#if defined __GNUC__


#include "pico.h"

# note we don't do this by default in this file for backwards comaptibility with user code
# that may include this file, but not use unified syntax. Note that this macro does equivalent
# setup to the pico_default_asm macro for inline assembly in C code.
.macro pico_default_asm_setup
.text
.syntax unified
.cpu cortex-m0plus
.thumb
.endm

// do not put align in here as it is used mid function sometimes
.macro regular_func x
.global \x
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
.endm

.macro weak_wrapper_func x
weak_func WRAPPER_FUNC_NAME(\x)
.endm

# backwards compatibility
.macro __pre_init func, priority_string
.section .preinit_array.\priority_string
.p2align 2
.word \func
.endm

#define code_in_code_area
#define data_in_code_area


#elif defined __IASMARM__


#define __ASSEMBLER__
#include "pico.h"

// Note the blank line after this is important!
#define BACKTICK `

#define QUOTED(string,quote) quote ## string ## quote
#define BACKTICK_QUOTED(string) QUOTED(string,BACKTICK)

pico_default_asm_setup          macro
                                section         `.text`:CODE:NOROOT(2)
                                aapcs           base, interwork
                                preserve8
                                require8
                                thumb
                                endm

// do not put align in here as it is used mid function sometimes
regular_func                    macro           x
                                public          x
                                thumb
x:
                                endm

weak_func                       macro           x
                                pubweak         x
                                thumb
x:
                                endm

regular_func_with_section       macro           x
                                section         `.text.\1`:CODE:NOROOT(2)
                                regular_func    x
                                endm

// do not put align in here as it is used mid function sometimes
wrapper_func                    macro           x
                                regular_func    BACKTICK_QUOTED(WRAPPER_FUNC_NAME(\1))
                                endm

// gnu_func is for functions unique to GNU C libraries, so uses wrapper only in GNU case
gnu_func                        macro           x
                                regular_func    \1
                                endm

weak_wrapper_func               macro           x
                                weak_func       BACKTICK_QUOTED(WRAPPER_FUNC_NAME(\1))
                                endm

__pre_init                      macro           func, priority_string
                                section         `.preinit_array.\2`:DATA:ROOT(2)
                                alignrom        2
                                dc32            func
                                endm

#define code_in_code_area thumb
#define data_in_code_area data


#else


#error Unsupported toolchain


#endif

#endif // sentry INCLUDED_ASM_HELPER_S
