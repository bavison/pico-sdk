/*
 * Copyright (c) 2020 Raspberry Pi (Trading) Ltd.
 *
 * SPDX-License-Identifier: BSD-3-Clause
 */

#if defined __GNUC__


#include "pico.h"

#ifdef __riscv
// Get macros for convenient use of Hazard3 instructions without binutils support
#include "hardware/hazard3/instructions.h"
#endif

#if !PICO_ASSEMBLER_IS_CLANG
#define apsr_nzcv r15
#endif
// note we don't do this by default in this file for backwards comaptibility with user code
// that may include this file, but not use unified syntax. Note that this macro does equivalent
// setup to the pico_default_asm macro for inline assembly in C code.
.macro pico_default_asm_setup
#ifndef __riscv
.syntax unified
.cpu cortex-m33
.fpu fpv5-sp-d16
.thumb
#endif
.endm

// do not put align in here as it is used mid function sometimes
.macro regular_func x
.global \x
.type \x,%function
#ifndef __riscv
.thumb_func
#endif
\x:
.endm

.macro weak_func x
.weak \x
.type \x,%function
#ifndef __riscv
.thumb_func
#endif
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

.macro __pre_init_with_offset func, offset, priority_string1
.section .preinit_array.\priority_string1
.p2align 2
.word \func + \offset
.endm

// backwards compatibility
.macro __pre_init func, priority_string1
__pre_init_with_offset func, 0, priority_string1
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
