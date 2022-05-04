/*
 * Copyright (c) 2020 Raspberry Pi (Trading) Ltd.
 *
 * SPDX-License-Identifier: BSD-3-Clause
 */

#include "pico/asm_helper.S"
#include "hardware/regs/m0plus.h"
#include "hardware/regs/addressmap.h"
#include "hardware/regs/sio.h"
#include "pico/binary_info/defs.h"

#ifdef __IASMARM__

 _extern `BINARY_INFO$$Base`
 _set __binary_info_start, `BINARY_INFO$$Base`
 _extern `BINARY_INFO$$Limit`
 _set __binary_info_end, `BINARY_INFO$$Limit`

 _extern `BSS$$Base`
 _set __bss_start__, `BSS$$Base`
 _extern `BSS$$Limit`
 _set __bss_end__, `BSS$$Limit`

 _extern `DATA_INITIALIZERS$$Base`
 _set __etext, `DATA_INITIALIZERS$$Base`
 _extern `DATA$$Base`
 _set __data_start__, `DATA$$Base`
 _extern `DATA$$Limit`
 _set __data_end__, `DATA$$Limit`

 _extern `SCRATCH_X_INITIALIZERS$$Base`
 _set __scratch_x_source__, `SCRATCH_X_INITIALIZERS$$Base`
 _extern `SCRATCH_X$$Base`
 _set __scratch_x_start__, `SCRATCH_X$$Base`
 _extern `SCRATCH_X$$Limit`
 _set __scratch_x_end__, `SCRATCH_X$$Limit`

 _extern `SCRATCH_Y_INITIALIZERS$$Base`
 _set __scratch_y_source__, `SCRATCH_Y_INITIALIZERS$$Base`
 _extern `SCRATCH_Y$$Base`
 _set __scratch_y_start__, `SCRATCH_Y$$Base`
 _extern `SCRATCH_Y$$Limit`
 _set __scratch_y_end__, `SCRATCH_Y$$Limit`

 _extern `SCRATCH_Y$$Limit`
 _set __StackTop, `SCRATCH_Y$$Limit`

 #else

 _extern __binary_info_start
 _extern __binary_info_end

 _extern __bss_start__
 _extern __bss_end__

 _extern __etext
 _extern __data_start__
 _extern __data_end__

 _extern __scratch_x_source__
 _extern __scratch_x_start__
 _extern __scratch_x_end__

 _extern __scratch_y_source__
 _extern __scratch_y_start__
 _extern __scratch_y_end__

 _extern __StackTop

#endif

 _extern exit
 _extern main
 _extern rom_func_lookup

#ifdef NDEBUG
#ifndef COLLAPSE_IRQS
#define COLLAPSE_IRQS
#endif
#endif

 _section(.vectors, `.vectors`, "ax", CODE, 2)
 _align 2

    data_in_code_area
 _global __vectors, __VECTOR_TABLE
__VECTOR_TABLE:
__vectors:
#ifdef __IASMARM__
// The IAR debugger uses the two words at the symbol __vector_table to set
// the initial stack pointer and program counter, so be sure to define it.
 public __vector_table
__vector_table:
#endif
    _word __StackTop
    _word _reset_handler
    _word isr_nmi
    _word isr_hardfault
    _word isr_invalid // Reserved, should never fire
    _word isr_invalid // Reserved, should never fire
    _word isr_invalid // Reserved, should never fire
    _word isr_invalid // Reserved, should never fire
    _word isr_invalid // Reserved, should never fire
    _word isr_invalid // Reserved, should never fire
    _word isr_invalid // Reserved, should never fire
    _word isr_svcall
    _word isr_invalid // Reserved, should never fire
    _word isr_invalid // Reserved, should never fire
    _word isr_pendsv
    _word isr_systick
    _word isr_irq0
    _word isr_irq1
    _word isr_irq2
    _word isr_irq3
    _word isr_irq4
    _word isr_irq5
    _word isr_irq6
    _word isr_irq7
    _word isr_irq8
    _word isr_irq9
    _word isr_irq10
    _word isr_irq11
    _word isr_irq12
    _word isr_irq13
    _word isr_irq14
    _word isr_irq15
    _word isr_irq16
    _word isr_irq17
    _word isr_irq18
    _word isr_irq19
    _word isr_irq20
    _word isr_irq21
    _word isr_irq22
    _word isr_irq23
    _word isr_irq24
    _word isr_irq25
    _word isr_irq26
    _word isr_irq27
    _word isr_irq28
    _word isr_irq29
    _word isr_irq30
    _word isr_irq31

 code_in_code_area

// all default exception handlers do nothing, and we can check for them being set to our
// default values by seeing if they point to somewhere between __defaults_isrs_start and __default_isrs_end
 _global __default_isrs_start
__default_isrs_start:

// Declare a weak symbol for each ISR.
// By default, they will fall through to the undefined IRQ handler below (breakpoint),
// but can be overridden by C functions with correct name.

_macro_1arg(decl_isr_bkpt, name)
 weak_func MA(name)
    bkpt #0
 _endm(endm)

// these are separated out for clarity
 decl_isr_bkpt isr_invalid
 decl_isr_bkpt isr_nmi
 decl_isr_bkpt isr_hardfault
 decl_isr_bkpt isr_svcall
 decl_isr_bkpt isr_pendsv
 decl_isr_bkpt isr_systick

 _global __default_isrs_end
__default_isrs_end:

_macro_1arg(decl_isr, name)
 weak_func MA(name)
 _endm(endm)

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
    bl __get_current_exception
    subs r0, #16
 _global unhandled_user_irq_num_in_r0
unhandled_user_irq_num_in_r0:
    bkpt #0

// ----------------------------------------------------------------------------

 _section(.binary_info_header, `.binary_info_header`, "a", CONST, 2)

// Header must be in first 256 bytes of main image (i.e. excluding flash boot2).
// For flash builds we put it immediately after vector table; for NO_FLASH the
// vectors are at a +0x100 offset because the bootrom enters RAM images directly
// at their lowest address, so we put the header in the VTOR alignment hole.

#if !PICO_NO_BINARY_INFO
binary_info_header:
    _word BINARY_INFO_MARKER_START
    _word __binary_info_start
    _word __binary_info_end
    _word data_cpy_table // we may need to decode pointers that are in RAM at runtime.
    _word BINARY_INFO_MARKER_END
#endif

// ----------------------------------------------------------------------------

 _section(.reset, `.reset`, "ax", CODE, 2)

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

    adr r4, data_cpy_table

    // assume there is at least one entry
next:
    ldmia r4!, {r1-r3}
    cmp r1, #0
    beq done
    bl data_cpy
    b next
done:

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
 weak_func _exit
infinite: // separate label because _exit can be moved out of branch range
    bkpt #0
    b infinite

#ifndef __IASMARM__

data_cpy_loop:
    ldm r1!, {r0}
    stm r2!, {r0}
data_cpy:
    cmp r2, r3
    blo data_cpy_loop
    bx lr

#endif

 _align 2
    data_in_code_area
data_cpy_table:
#if PICO_COPY_TO_RAM
    _word __ram_text_source__
    _word __ram_text_start__
    _word __ram_text_end__
#endif
    _word __etext
    _word __data_start__
    _word __data_end__

    _word __scratch_x_source__
    _word __scratch_x_start__
    _word __scratch_x_end__

    _word __scratch_y_source__
    _word __scratch_y_start__
    _word __scratch_y_end__

    _word 0 // null terminator

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

 regular_func __get_current_exception
    mrs  r0, ipsr
    uxtb r0, r0
    bx   lr

// ----------------------------------------------------------------------------
// Stack/heap dummies to set size

 _root_section(.stack, `.stack`, "", DATA, 5)
// align to allow for memory protection (although this alignment is pretty much ignored by linker script)
 _align 5
 _equ StackSize, PICO_STACK_SIZE
 _space StackSize

 _root_section(.heap, `.heap`, "", DATA, 2)
 _align 2
 _equ HeapSize, PICO_HEAP_SIZE
 _space HeapSize

 _end
