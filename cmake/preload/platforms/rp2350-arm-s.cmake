if (NOT PICO_DEFAULT_COMPILER)
    if ("${CMAKE_GENERATOR}" STREQUAL "IAR Embedded Workbench for Arm")
        set(PICO_DEFAULT_COMPILER "pico_arm_cortex_m33_iar")
    else ()
        set(PICO_DEFAULT_COMPILER "pico_arm_cortex_m33_gcc")
    endif ()
endif ()
set(PICO_CHIP rp2350)

