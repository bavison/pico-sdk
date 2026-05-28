// PICO_CONFIG: PICO_CRT0_INCLUDE_PICOBIN_IMAGE_TYPE_ITEM, Include an image type item in the metadata block, default=0 on RP2040, 1 otherwise, type=bool, group=pico_crt0
#ifndef PICO_CRT0_INCLUDE_PICOBIN_IMAGE_TYPE_ITEM
// todo decide whether we want this item for RP2040 by default, probably not (there are a zilloon binaries out there without it)
#if !PICO_RP2040
#define PICO_CRT0_INCLUDE_PICOBIN_IMAGE_TYPE_ITEM 1
#endif
#endif

// PICO_CONFIG: PICO_CRT0_INCLUDE_PICOBIN_VECTOR_TABLE_ITEM, Include a vector table item in the metadata block, default=1 for no_flash binaries, 0 otherwise or on RP2040, type=bool, group=pico_crt0
#ifndef PICO_CRT0_INCLUDE_PICOBIN_VECTOR_TABLE_ITEM
// If no_flash bin, then include a vector table item
#if PICO_NO_FLASH && !PICO_RP2040
#define PICO_CRT0_INCLUDE_PICOBIN_VECTOR_TABLE_ITEM 1
#endif
#endif

// PICO_CONFIG: PICO_CRT0_INCLUDE_PICOBIN_ENTRY_POINT_ITEM, Include an entry point item in the metadata block, default=1 for Risc-V, 0 otherwise, type=bool, group=pico_crt0
#ifndef PICO_CRT0_INCLUDE_PICOBIN_ENTRY_POINT_ITEM
// On RISC-V the default entry point from bootrom is the start of the binary, but
// we have our vtable at the start, so we must include an entry point
#ifdef __riscv
#define PICO_CRT0_INCLUDE_PICOBIN_ENTRY_POINT_ITEM 1
#endif
#endif

// PICO_CONFIG: PICO_CRT0_INCLUDE_PICOBIN_BLOCK, Include a metadata block at the start of the image, default=PICO_CRT0_INCLUDE_PICOBIN_IMAGE_TYPE_ITEM, type=bool, group=pico_crt0
#ifndef PICO_CRT0_INCLUDE_PICOBIN_BLOCK
#define PICO_CRT0_INCLUDE_PICOBIN_BLOCK PICO_CRT0_INCLUDE_PICOBIN_IMAGE_TYPE_ITEM
#endif

// PICO_CONFIG: PICO_CRT0_INCLUDE_PICOBIN_END_BLOCK, Include a metadata block at the end of the image, default=1 for flash binaries with a metadata block at the start, type=bool, group=pico_crt0
#ifndef PICO_CRT0_INCLUDE_PICOBIN_END_BLOCK
#define PICO_CRT0_INCLUDE_PICOBIN_END_BLOCK (PICO_CRT0_INCLUDE_PICOBIN_BLOCK && !PICO_NO_FLASH)
#endif

// PICO_CONFIG: PICO_CRT0_IMAGE_TYPE_TBYB, Set the TBYB flag for the IMAGE_DEF which requires a flash update boot to boot it, default=0, type=bool, group=pico_crt0
#ifndef PICO_CRT0_IMAGE_TYPE_TBYB
#define PICO_CRT0_IMAGE_TYPE_TBYB 0
#endif

#if PICO_CRT0_IMAGE_TYPE_TBYB
#define CRT0_TBYB_FLAG PICOBIN_IMAGE_TYPE_EXE_TBYB_BITS
#else
#define CRT0_TBYB_FLAG 0
#endif

// PICO_CONFIG: PICO_CRT0_VERSION_MAJOR, The major version for the metadata block (ignored if 0), default=0, type=int, group=pico_crt0
// PICO_CONFIG: PICO_CRT0_VERSION_MINOR, The minor version for the metadata block (ignored if 0), default=0, type=int, group=pico_crt0
#if defined(PICO_CRT0_VERSION_MINOR) && !defined(PICO_CRT0_VERSION_MAJOR)
#define PICO_CRT0_VERSION_MAJOR 0
#elif defined(PICO_CRT0_VERSION_MAJOR) && !defined(PICO_CRT0_VERSION_MINOR)
#define PICO_CRT0_VERSION_MINOR 0
#endif

// PICO_CONFIG: PICO_CRT0_IMAGE_TYPE_ITEM_VALUE, The IMAGE_TYPE value for the IMAGE_DEF, default=matching the PICO_PLATFORM, type=int, group=pico_crt0
#ifndef PICO_CRT0_IMAGE_TYPE_ITEM_VALUE
#if defined(__riscv)
#define PICO_CRT0_IMAGE_TYPE_ITEM_VALUE \
       PICOBIN_IMAGE_TYPE_IMAGE_TYPE_AS_BITS(EXE) | \
       PICOBIN_IMAGE_TYPE_EXE_CPU_AS_BITS(RISCV) | \
       PICOBIN_IMAGE_TYPE_EXE_CHIP_AS_BITS(RP2350) | \
       CRT0_TBYB_FLAG
#elif PICO_RP2040
#define PICO_CRT0_IMAGE_TYPE_ITEM_VALUE \
       PICOBIN_IMAGE_TYPE_IMAGE_TYPE_AS_BITS(EXE) | \
       PICOBIN_IMAGE_TYPE_EXE_SECURITY_AS_BITS(NS) | \
       PICOBIN_IMAGE_TYPE_EXE_CPU_AS_BITS(ARM) | \
       PICOBIN_IMAGE_TYPE_EXE_CHIP_AS_BITS(RP2040) | \
       CRT0_TBYB_FLAG
#else
#define PICO_CRT0_IMAGE_TYPE_ITEM_VALUE \
       PICOBIN_IMAGE_TYPE_IMAGE_TYPE_AS_BITS(EXE) | \
       PICOBIN_IMAGE_TYPE_EXE_SECURITY_AS_BITS(S) | \
       PICOBIN_IMAGE_TYPE_EXE_CPU_AS_BITS(ARM) | \
       PICOBIN_IMAGE_TYPE_EXE_CHIP_AS_BITS(RP2350) | \
       CRT0_TBYB_FLAG
#endif
#endif

#if PICO_CRT0_INCLUDE_PICOBIN_BLOCK
 section `.embedded_block`:DATA:ROOT(2)
 alignrom 2
embedded_block:
    dc32 PICOBIN_BLOCK_MARKER_START

#if PICO_CRT0_INCLUDE_PICOBIN_IMAGE_TYPE_ITEM
// include an IMAGE_TYPE item at the start so this block is a valid IMAGE_DEF block, and can be used as a basis
// for booting the binary with a known type.
    dc8 PICOBIN_BLOCK_ITEM_1BS_IMAGE_TYPE
    dc8 0x1 // 1 word
    dc16 PICO_CRT0_IMAGE_TYPE_ITEM_VALUE
#else
// if no image type, then add ignored item
    dc8 PICOBIN_BLOCK_ITEM_2BS_IGNORED
    dc8 0x1 // 1 word
    dc16 0
#endif

#ifdef PICO_CRT0_VERSION_MAJOR
    dc8 PICOBIN_BLOCK_ITEM_1BS_VERSION
    dc8 0x2 // 2 words
    dc16 0
    dc16 PICO_CRT0_VERSION_MINOR
    dc16 PICO_CRT0_VERSION_MAJOR
#endif

#if PICO_CRT0_INCLUDE_PICOBIN_ENTRY_POINT_ITEM
    dc8 PICOBIN_BLOCK_ITEM_1BS_ENTRY_POINT
    dc8 0x3 // word size to next item
    dc8 0 // pad
    dc8 0 // pad
    dc32 _reset_handler
    dc32 SRAM_END // stack pointer
#endif

#if PICO_CRT0_INCLUDE_PICOBIN_VECTOR_TABLE_ITEM
    dc8 PICOBIN_BLOCK_ITEM_1BS_VECTOR_TABLE
    dc8 0x2
    dc16 0
    dc32 __vectors
#endif

    dc8 PICOBIN_BLOCK_ITEM_2BS_LAST
    dc16 (embedded_block_end - embedded_block - 16 ) / 4 // total size of all
    dc8 0
#if PICO_CRT0_INCLUDE_PICOBIN_END_BLOCK
    dc32 embedded_end_block - embedded_block
#else
// offset from this block to next block in loop (since we are a single block loop, we point back to ourselves
// so the offset is 0)
    dc32 0
#endif
    dc32 PICOBIN_BLOCK_MARKER_END
embedded_block_end:
#endif
