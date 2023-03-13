if (NOT (DEFINED PICO_COMPILER OR DEFINED CMAKE_TOOLCHAIN_FILE))
    if ("${CMAKE_GENERATOR}" STREQUAL "IAR Embedded Workbench for Arm")
        pico_message("Defaulting PICO platform compiler to pico_arm_iar since not specified.")
        set(PICO_COMPILER "pico_arm_iar")
    else ()
        pico_message("Defaulting PICO platform compiler to pico_arm_gcc since not specified.")
        set(PICO_COMPILER "pico_arm_gcc")
    endif ()
endif ()



