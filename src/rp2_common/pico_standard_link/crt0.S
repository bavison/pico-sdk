/*
 * Copyright (c) 2020 Raspberry Pi (Trading) Ltd.
 *
 * SPDX-License-Identifier: BSD-3-Clause
 */

#include "hardware/regs/m0plus.h"
#include "hardware/regs/addressmap.h"
#include "hardware/regs/sio.h"
#include "pico/asm_helper.S"
#include "pico/binary_info/defs.h"

#ifdef __IASMARM__

 extern `BINARY_INFO$$Base`
 _set __binary_info_start, `BINARY_INFO$$Base`
 extern `BINARY_INFO$$Limit`
 _set __binary_info_end, `BINARY_INFO$$Limit`

 extern `BSS$$Base`
 _set __bss_start__, `BSS$$Base`
 extern `BSS$$Limit`
 _set __bss_end__, `BSS$$Limit`

#if PICO_COPY_TO_RAM
 extern `RAM_TEXT_INITIALIZERS$$Base`
 _set __ram_text_source__, `RAM_TEXT_INITIALIZERS$$Base`
 extern `RAM_TEXT$$Base`
 _set __ram_text_start__, `RAM_TEXT$$Base`
 extern `RAM_TEXT$$Limit`
 _set  __ram_text_end__, `RAM_TEXT$$Limit`
#endif

 extern `DATA_INITIALIZERS$$Base`
 _set __etext, `DATA_INITIALIZERS$$Base`
 extern `DATA$$Base`
 _set __data_start__, `DATA$$Base`
 extern `DATA$$Limit`
 _set __data_end__, `DATA$$Limit`

 extern `SCRATCH_X_INITIALIZERS$$Base`
 _set __scratch_x_source__, `SCRATCH_X_INITIALIZERS$$Base`
 extern `SCRATCH_X$$Base`
 _set __scratch_x_start__, `SCRATCH_X$$Base`
 extern `SCRATCH_X$$Limit`
 _set __scratch_x_end__, `SCRATCH_X$$Limit`

 extern `SCRATCH_Y_INITIALIZERS$$Base`
 _set __scratch_y_source__, `SCRATCH_Y_INITIALIZERS$$Base`
 extern `SCRATCH_Y$$Base`
 _set __scratch_y_start__, `SCRATCH_Y$$Base`
 extern `SCRATCH_Y$$Limit`
 _set __scratch_y_end__, `SCRATCH_Y$$Limit`

 extern `SCRATCH_Y$$Limit`
 _set __StackTop, `SCRATCH_Y$$Limit`

 #else

 extern __binary_info_start
 extern __binary_info_end

 extern __bss_start__
 extern __bss_end__

#if PICO_COPY_TO_RAM
 extern __ram_text_source__
 extern __ram_text_start__
 extern __ram_text_end__
#endif

 extern __etext
 extern __data_start__
 extern __data_end__

 extern __scratch_x_source__
 extern __scratch_x_start__
 extern __scratch_x_end__

 extern __scratch_y_source__
 extern __scratch_y_start__
 extern __scratch_y_end__

 extern __StackTop

#endif

 extern exit
 extern main
 extern rom_func_lookup

#ifdef NDEBUG
#ifndef COLLAPSE_IRQS
#define COLLAPSE_IRQS
#endif
#endif

 _section(.vectors, "ax", CODE, 2)
 alignrom 2

    data_in_code_area
 public __vectors, __VECTOR_TABLE
__VECTOR_TABLE:
__vectors:
    dc32 __StackTop
    dc32 _reset_handler
    dc32 isr_nmi
    dc32 isr_hardfault
    dc32 isr_invalid // Reserved, should never fire
    dc32 isr_invalid // Reserved, should never fire
    dc32 isr_invalid // Reserved, should never fire
    dc32 isr_invalid // Reserved, should never fire
    dc32 isr_invalid // Reserved, should never fire
    dc32 isr_invalid // Reserved, should never fire
    dc32 isr_invalid // Reserved, should never fire
    dc32 isr_svcall
    dc32 isr_invalid // Reserved, should never fire
    dc32 isr_invalid // Reserved, should never fire
    dc32 isr_pendsv
    dc32 isr_systick
    dc32 isr_irq0
    dc32 isr_irq1
    dc32 isr_irq2
    dc32 isr_irq3
    dc32 isr_irq4
    dc32 isr_irq5
    dc32 isr_irq6
    dc32 isr_irq7
    dc32 isr_irq8
    dc32 isr_irq9
    dc32 isr_irq10
    dc32 isr_irq11
    dc32 isr_irq12
    dc32 isr_irq13
    dc32 isr_irq14
    dc32 isr_irq15
    dc32 isr_irq16
    dc32 isr_irq17
    dc32 isr_irq18
    dc32 isr_irq19
    dc32 isr_irq20
    dc32 isr_irq21
    dc32 isr_irq22
    dc32 isr_irq23
    dc32 isr_irq24
    dc32 isr_irq25
    dc32 isr_irq26
    dc32 isr_irq27
    dc32 isr_irq28
    dc32 isr_irq29
    dc32 isr_irq30
    dc32 isr_irq31

 code_in_code_area

// all default exception handlers do nothing, and we can check for them being set to our
// default values by seeing if they point to somewhere between __defaults_isrs_start and __default_isrs_end
 public __default_isrs_start
__default_isrs_start:

// Declare a weak symbol for each ISR.
// By default, they will fall through to the undefined IRQ handler below (breakpoint),
// but can be overridden by C functions with correct name.

_macro_1arg(decl_isr_bkpt, name)
 weak_func MA(name)
    bkpt #0
 endm

// these are separated out for clarity
 decl_isr_bkpt isr_invalid
 decl_isr_bkpt isr_nmi
 decl_isr_bkpt isr_hardfault
 decl_isr_bkpt isr_svcall
 decl_isr_bkpt isr_pendsv
 decl_isr_bkpt isr_systick

 public __default_isrs_end
__default_isrs_end:

_macro_1arg(decl_isr, name)
 weak_func MA(name)
 endm

 decl_isr isr_irq0
 decl_isr isr_irq1
 decl_isr isr_irq2
 decl_isr isr_irq3
 decl_isr isr_irq4
 decl_isr isr_irq5
 decl_isr isr_irq6
 decl_isr isr_irq7
 decl_isr isr_irq8
 decl_isr isr_irq9
 decl_isr isr_irq10
 decl_isr isr_irq11
 decl_isr isr_irq12
 decl_isr isr_irq13
 decl_isr isr_irq14
 decl_isr isr_irq15
 decl_isr isr_irq16
 decl_isr isr_irq17
 decl_isr isr_irq18
 decl_isr isr_irq19
 decl_isr isr_irq20
 decl_isr isr_irq21
 decl_isr isr_irq22
 decl_isr isr_irq23
 decl_isr isr_irq24
 decl_isr isr_irq25
 decl_isr isr_irq26
 decl_isr isr_irq27
 decl_isr isr_irq28
 decl_isr isr_irq29
 decl_isr isr_irq30
 decl_isr isr_irq31

// All unhandled USER IRQs fall through to here
 regular_func __unhandled_user_irq
    mrs  r0, ipsr
    subs r0, #16
 public unhandled_user_irq_num_in_r0
unhandled_user_irq_num_in_r0:
    bkpt #0

// ----------------------------------------------------------------------------

 _section(.binary_info_header, "a", CONST, 2)

// Header must be in first 256 bytes of main image (i.e. excluding flash boot2).
// For flash builds we put it immediately after vector table; for NO_FLASH the
// vectors are at a +0x100 offset because the bootrom enters RAM images directly
// at their lowest address, so we put the header in the VTOR alignment hole.

#if !PICO_NO_BINARY_INFO
binary_info_header:
    dc32 BINARY_INFO_MARKER_START
    dc32 __binary_info_start
    dc32 __binary_info_end
    dc32 data_cpy_table // we may need to decode pointers that are in RAM at runtime.
    dc32 BINARY_INFO_MARKER_END
#endif

// ----------------------------------------------------------------------------

 _section(.reset, "ax", CODE, 2)

// On flash builds, the vector table comes first in the image (conventional).
// On NO_FLASH builds, the reset handler section comes first, as the entry
// point is at offset 0 (fixed due to bootrom), and VTOR is highly-aligned.
// Image is entered in various ways:
//
// - NO_FLASH builds are entered from beginning by UF2 bootloader
//
// - Flash builds vector through the table into _reset_handler from boot2
//
// - Either type can be entered via _entry_point by the debugger, and flash builds
//   must then be sent back round the boot sequence to properly initialise flash

// ELF entry point:
 regular_func _entry_point

#if PICO_NO_FLASH
    // Vector through our own table (SP, VTOR will not have been set up at
    // this point). Same path for debugger entry and bootloader entry.
    ldr r0, =__vectors
#else
    // Debugger tried to run code after loading, so SSI is in 03h-only mode.
    // Go back through bootrom + boot2 to properly initialise flash.
    movs r0, #0
#endif
    ldr r1, =(PPB_BASE + M0PLUS_VTOR_OFFSET)
    str r0, [r1]
    ldmia r0!, {r1, r2}
    msr msp, r1
    bx r2

// Reset handler:
// - initialises .data
// - clears .bss
// - calls runtime_init
// - calls main
// - calls exit (which should eventually hang the processor via _exit)

 local_func _reset_handler
    // Only core 0 should run the C runtime startup code; core 1 is normally
    // sleeping in the bootrom at this point but check to be sure
    ldr r0, =(SIO_BASE + SIO_CPUID_OFFSET)
    ldr r0, [r0]
    cmp r0, #0
    bne hold_non_core0_in_bootrom

#ifdef __IASMARM__

    // The IAR linker can compress static initialisers, which reduces image
    // size, but requires that we use the IAR runtime to initialise statics
 extern __iar_data_init3
    bl __iar_data_init3

#else

    // In a NO_FLASH binary, don't perform .data copy, since it's loaded
    // in-place by the SRAM load. Still need to clear .bss
#if !PICO_NO_FLASH
    adr r4, data_cpy_table

    // assume there is at least one entry
next:
    ldmia r4!, {r1-r3}
    cmp r1, #0
    beq done
    bl data_cpy
    b next
done:
#endif

    // Zero out the BSS
    ldr r1, =__bss_start__
    ldr r2, =__bss_end__
    movs r0, #0
    b bss_fill_test
bss_fill_loop:
    stm r1!, {r0}
bss_fill_test:
    cmp r1, r2
    bne bss_fill_loop

#endif

platform_entry: // symbol for stack traces
    // Use 32-bit jumps, in case these symbols are moved out of branch range
    // (e.g. if main is in SRAM and crt0 in flash)
    ldr r1, =runtime_init
    blx r1
    ldr r1, =main
    blx r1
    ldr r1, =exit
    blx r1
    // exit should not return.  If it does, hang the core.
    // (fall thru into our hang _exit impl
infinite: // separate label because _exit can be moved out of branch range
    bkpt #0
    b infinite

#if !defined(__IASMARM__) && !PICO_NO_FLASH
data_cpy_loop:
    ldm r1!, {r0}
    stm r2!, {r0}
data_cpy:
    cmp r2, r3
    blo data_cpy_loop
    bx lr
#endif

// Note the data copy table is still included for NO_FLASH builds, even though
// we skip the copy, because it is listed in binary info

 alignrom 2
    data_in_code_area
data_cpy_table:
#if PICO_COPY_TO_RAM
    dc32 __ram_text_source__
    dc32 __ram_text_start__
    dc32 __ram_text_end__
#endif
    dc32 __etext
    dc32 __data_start__
    dc32 __data_end__

    dc32 __scratch_x_source__
    dc32 __scratch_x_start__
    dc32 __scratch_x_end__

    dc32 __scratch_y_source__
    dc32 __scratch_y_start__
    dc32 __scratch_y_end__

    dc32 0 // null terminator

// ----------------------------------------------------------------------------
// Provide safe defaults for _exit and runtime_init
// Full implementations usually provided by platform.c

 code_in_code_area

 weak_func runtime_init
    bx lr

// ----------------------------------------------------------------------------
// If core 1 somehow gets into crt0 due to a spectacular VTOR mishap, we need to
// catch it and send back to the sleep-and-launch code in the bootrom. Shouldn't
// happen (it should sleep in the ROM until given an entry point via the
// cross-core FIFOs) but it's good to be defensive.

hold_non_core0_in_bootrom:
    ldr r0, = 'W' | ('V' << 8)
    bl rom_func_lookup
    bx r0

// ----------------------------------------------------------------------------
// Stack/heap dummies to set size

 _root_section(.stack, "a", DATA, 5)
// align to allow for memory protection (although this alignment is pretty much ignored by linker script)
 alignrom 5
 _equ StackSize, PICO_STACK_SIZE
 ds StackSize

 _root_section(.heap, "a", DATA, 2)
 alignrom 2
 _equ HeapSize, PICO_HEAP_SIZE
 ds HeapSize

 end
