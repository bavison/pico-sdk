set(CMAKE_SYSTEM_PROCESSOR cortex-m33)

# Specify variables required to configure the EWARM IDE
set(CMAKE_IAR_CHIP_SELECT               "RaspberryPi RP2350")
set(CMAKE_IAR_CORE                      "61")
set(CMAKE_IAR_FPU                       "6")
set(CMAKE_IAR_FPU_NR_REGS               "1")
set(CMAKE_IAR_DSP_EXTENSION             "1")
set(CMAKE_IAR_TRUSTZONE                 "1")
if (PICO_NO_CMSE)
set(CMAKE_IAR_TRUSTZONE_MODES           "1")  # Non-secure
else()
set(CMAKE_IAR_TRUSTZONE_MODES           "0")  # Secure
endif()

include(${CMAKE_CURRENT_LIST_DIR}/util/pico_arm_iar_common.cmake)
