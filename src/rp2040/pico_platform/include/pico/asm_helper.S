/*
 * Copyright (c) 2020 Raspberry Pi (Trading) Ltd.
 *
 * SPDX-License-Identifier: BSD-3-Clause
 */

#include "pico.h"

# note we don't do this by default in this file for backwards comaptibility with user code
# that may include this file, but not use unified syntax. Note that this macro does equivalent
# setup to the pico_default_asm macro for inline assembly in C code.
.macro pico_default_asm_setup
.syntax unified
.cpu cortex-m0plus
.thumb
.eabi_attribute Tag_ABI_align_preserved, 1
.endm

.macro mark_section_used
#if PICO_C_COMPILER_IS_ARMCLANG
__tagsym$$used.\@:
#endif
endm

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
mark_section_used
.p2align 2
.word \func
.endm
