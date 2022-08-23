# include our Platform/PICO.cmake
set(CMAKE_SYSTEM_NAME PICO)
set(CMAKE_SYSTEM_PROCESSOR cortex-m0plus)

# Find IAR tools for ARM
if (NOT DEFINED ENV{CMAKE_TOOLCHAIN_PATH})
    file(GLOB_RECURSE PICO_COMPILER_CC "C:/Program Files/IAR Systems/Embedded Workbench */arm/bin/iccarm.exe")
    list(LENGTH PICO_COMPILER_CC COUNT)
    if (COUNT EQUAL 0)
        message(FATAL_ERROR "Cannot find IAR tools")
    elseif (COUNT EQUAL 1)
        cmake_path(GET PICO_COMPILER_CC PARENT_PATH CMAKE_TOOLCHAIN_PATH)
    else ()
        message(FATAL_ERROR "IAR tools found in multiple locations, use CMAKE_TOOLCHAIN_PATH to select")
    endif ()
else ()
    set(CMAKE_TOOLCHAIN_PATH $ENV{CMAKE_TOOLCHAIN_PATH})
    cmake_path(APPEND CMAKE_TOOLCHAIN_PATH "iccarm.exe"  OUTPUT_VARIABLE PICO_COMPILER_CC)
endif ()

cmake_path(APPEND CMAKE_TOOLCHAIN_PATH "iccarm.exe"  OUTPUT_VARIABLE PICO_COMPILER_CXX)
cmake_path(APPEND CMAKE_TOOLCHAIN_PATH "iasmarm.exe" OUTPUT_VARIABLE PICO_COMPILER_ASM)

# Specify the cross compiler.
set(CMAKE_C_COMPILER   ${PICO_COMPILER_CC}  CACHE FILEPATH "C compiler")
set(CMAKE_CXX_COMPILER ${PICO_COMPILER_CXX} CACHE FILEPATH "C++ compiler")
set(CMAKE_ASM_COMPILER ${PICO_COMPILER_ASM} CACHE FILEPATH "Assembler")
set(CMAKE_C_OUTPUT_EXTENSION .o)

option(PICO_DEOPTIMIZED_DEBUG "Build debug builds without optimisations" 0)

# Specify variables required to configure the EWARM IDE
set(CMAKE_IAR_RUNTIME_LIB_SELECT "2")
set(CMAKE_IAR_CHIP_SELECT "RaspberryPi RP2040")
set(CMAKE_IAR_C_DIAG_SUPPRESS "Pa039,Pe170")
set(CMAKE_IAR_ASM_DIAG_SUPPRESS "12")
set(CMAKE_IAR_CUSTOM_EXTENSIONS ".pio")
set(CMAKE_IAR_CUSTOM_CMDLINE "${PICO_SDK_PATH}/tools/pioasm/pioasm -o c-sdk $FILE_PATH$ $PROJ_DIR$/$FILE_BNAME$.pio.h")
set(CMAKE_IAR_CUSTOM_BUILD_SEQUENCE "preCompile")
set(CMAKE_IAR_CUSTOM_OUTPUTS "$PROJ_DIR$/$FILE_BNAME$.pio.h")
set(CMAKE_IAR_ILINK_KEEP_SYMBOLS "__checksum")
# CMAKE_IAR_ILINK_ICF_FILE is set in pico_standard_link/CMakeLists.txt
set(CMAKE_IAR_ILINK_PROGRAM_ENTRY_LABEL "_entry_point")
set(CMAKE_IAR_DO_FILL "1")
set(CMAKE_IAR_FILLER_START "0x10000000")
set(CMAKE_IAR_FILLER_END "0x100000fb")
set(CMAKE_IAR_CRC_SIZE "2")
set(CMAKE_IAR_CRC_INITIAL_VALUE "0xffffffff")
set(CMAKE_IAR_DO_CRC "1")
set(CMAKE_IAR_ILINK_CRC_USE_AS_INPUT "0")
set(CMAKE_IAR_CRC_ALGORITHM "2")
