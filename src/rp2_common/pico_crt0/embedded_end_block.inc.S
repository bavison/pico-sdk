#if PICO_CRT0_INCLUDE_PICOBIN_END_BLOCK
 section `.embedded_end_block`:DATA:ROOT(2)
 alignrom 2
embedded_end_block:
    dc32 PICOBIN_BLOCK_MARKER_START

    dc8 PICOBIN_BLOCK_ITEM_2BS_IGNORED
    dc8 0x1 // 1 word
    dc16 0

    dc8 PICOBIN_BLOCK_ITEM_2BS_LAST
    dc16 (embedded_end_block_end - embedded_end_block - 16 ) / 4 // total size of all items
    dc8 0
// offset from this block to first block
    dc32 embedded_block - embedded_end_block
    dc32 PICOBIN_BLOCK_MARKER_END
embedded_end_block_end:
#endif
