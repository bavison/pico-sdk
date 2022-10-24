/*
 * Copyright (c) 2020 Raspberry Pi (Trading) Ltd.
 *
 * SPDX-License-Identifier: BSD-3-Clause
 */

#if defined __GNUC__


#include "pico.h"

.eabi_attribute Tag_ABI_align_preserved, 1

#define _align      .align
#define _asciz      .asciz
#define _byte       .byte
#define else        .else
#define _end        .end
#define endif       .endif
#define _endm(x)    .endm
#define endr        .endr
#define _equ        .equ
#define _extern     .extern
#define _global     .global
#define _hword      .hword
#define if          .if
#define _ltorg      .ltorg
#define _macro(x)   .macro x
#define _macro_1arg(x,a)                   .macro x a
#define _macro_2args(x,a,b)                .macro x a,b
#define _macro_3args(x,a,b,c)              .macro x a,b,c
#define _macro_5args(x,a,b,c,d,e)          .macro x a,b,c,d,e
#define _macro_6args(x,a,b,c,d,e,f)        .macro x a,b,c,d,e,f
#define _macro_9args(x,a,b,c,d,e,f,g,h,i)  .macro x a,b,c,d,e,f,g,h,i
#define _org        .org
#define rept        .rept
#define _section(name, flags, cd, align)   .section name, flags
#define _root_section(name, flags, cd, align) .section name, flags
#define _set        .set
#define _space      .space
#define _word       .word

// Expand a macro argument
#define MA(x)  \##x
#define MA2(x) \##x

.altmacro
.syntax unified
.cpu cortex-m0plus
.thumb
.section .text

.macro mark_section_used
#ifdef __ARMCOMPILER_VERSION
__tagsym$$used.\@:
#endif
.endm

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
.endm

.macro __pre_init func, priority_string
.section .preinit_array.\priority_string
mark_section_used
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

#define code_in_code_area
#define data_in_code_area


#elif defined __IASMARM__


#define __ASSEMBLER__
#include "pico.h"

// Note the blank line after this is important!
#define BACKTICK `

#define QUOTED(string,quote) quote ## string ## quote
#define BACKTICK_QUOTED(string) QUOTED(string,BACKTICK)

                                section         `.text`:CODE:NOROOT(2)
                                aapcs           base, interwork
                                preserve8
                                require8
                                thumb

#define _align                  alignrom
#define _byte                   dc8
#define _end                    end
#define _endm(x)                endm

_equ                            macro           x, y
x                               equ             y
                                endm

#define _extern                 extern
#define _global                 public
#define _hword                  dc16
#define _ltorg                  ltorg
#define _macro(x)                               x macro
#define _macro_1arg(x,a)                        x macro a
#define _macro_2args(x,a,b)                     x macro a,b
#define _macro_3args(x,a,b,c)                   x macro a,b,c
#define _macro_5args(x,a,b,c,d,e)               x macro a,b,c,d,e
#define _macro_6args(x,a,b,c,d,e,f)             x macro a,b,c,d,e,f
#define _macro_9args(x,a,b,c,d,e,f,g,h,i)       x macro a,b,c,d,e,f,g,h,i
#define _org                    ;

_set                            macro           x, y
x                               set             y
                                endm

#define _section(name, flags, cd, align)        section BACKTICK_QUOTED(name):cd:NOROOT(align)
#define _root_section(name, flags, cd, align)   section BACKTICK_QUOTED(name):cd:ROOT(align)
#define _space                  ds
#define _word                   dc32

// Expand a macro argument
// Two identical deinitions of the preprocessor macros are required to work
// around a bug in the IAR assembler where we use nested assembly macros
#define MA(x)  x
#define MA2(x) x

mark_section_used               macro
                                endm

// do not put align in here as it is used mid function sometimes
regular_func                    macro           x
                                public          x
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

local_func                      macro           x
                                thumb
x:
                                endm
weak_func                       macro           x
                                pubweak         x
                                thumb
x:
                                endm

#define code_in_code_area thumb
#define data_in_code_area data


#else


#error Unsupported toolchain


#endif

#ifdef __ARMCOMPILER_VERSION

#define DECLARE_LOCAL_LABEL(l)
#define LOCAL_LABEL(l) local_##l##_\@

#else

#define DECLARE_LOCAL_LABEL(l) local local_##l
#define LOCAL_LABEL(l) local_##l

#endif
