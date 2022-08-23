# include targets for all for PICO on device

enable_language(ASM)

function(pico_get_runtime_output_directory TARGET output_path_name)
    get_target_property(${TARGET}_runtime_directory ${TARGET} RUNTIME_OUTPUT_DIRECTORY)
    if (${TARGET}_runtime_directory)
        get_filename_component(output_path "${${TARGET}_runtime_directory}"
                REALPATH BASE_DIR "${CMAKE_CURRENT_BINARY_DIR}")
        file(MAKE_DIRECTORY "${output_path}")
        set(output_path "${output_path}/")
    else()
        set(output_path "")
    endif()
    set(${output_path_name} ${output_path} PARENT_SCOPE)
endfunction()

function(pico_get_output_name TARGET output_name_var)
    get_target_property(output_name ${TARGET} OUTPUT_NAME)
    # Generator expressions not supported in byproducts
    set(output_name_copy ${output_name})
    string(GENEX_STRIP "${output_name}" output_name)
    if (NOT output_name OR (NOT output_name STREQUAL output_name_copy))
        get_target_property(output_name ${TARGET} NAME)
    endif()
    set(${output_name_var} ${output_name} PARENT_SCOPE)
endfunction()

# pico_add_hex_output(TARGET)
# \brief\ Generate a hex file for the target
function(pico_add_hex_output TARGET)
    pico_get_runtime_output_directory(${TARGET} output_path)
    pico_get_output_name(${TARGET} output_name)
    add_custom_command(TARGET ${TARGET} POST_BUILD COMMAND ${CMAKE_OBJCOPY} -Oihex $<TARGET_FILE:${TARGET}> ${output_path}$<IF:$<BOOL:$<TARGET_PROPERTY:${TARGET},OUTPUT_NAME>>,$<TARGET_PROPERTY:${TARGET},OUTPUT_NAME>,$<TARGET_PROPERTY:${TARGET},NAME>>.hex VERBATIM BYPRODUCTS "${output_path}${output_name}.hex")
endfunction()

# pico_add_bin_output(TARGET)
# \brief\ Generate a bin file for the target
function(pico_add_bin_output TARGET)
    pico_get_runtime_output_directory(${TARGET} output_path)
    pico_get_output_name(${TARGET} output_name)
    add_custom_command(TARGET ${TARGET} POST_BUILD COMMAND ${CMAKE_OBJCOPY} -Obinary $<TARGET_FILE:${TARGET}> ${output_path}$<IF:$<BOOL:$<TARGET_PROPERTY:${TARGET},OUTPUT_NAME>>,$<TARGET_PROPERTY:${TARGET},OUTPUT_NAME>,$<TARGET_PROPERTY:${TARGET},NAME>>.bin VERBATIM BYPRODUCTS "${output_path}${output_name}.bin")
endfunction()

# pico_add_dis_output(TARGET)
# \brief\ Generate a disassembly file for the target
function(pico_add_dis_output TARGET)
    pico_get_runtime_output_directory(${TARGET} output_path)
    pico_get_output_name(${TARGET} output_name)

    # PICO_CMAKE_CONFIG: PICO_NO_COPRO_DIS, Disable disassembly listing postprocessing that disassembles RP2350 coprocessor instructions, type=bool, default=0, group=build
    if (NOT (PICO_NO_COPRO_DIS OR PICO_NO_PICOTOOL OR PICO_RISCV OR PICO_RP2040))
        # Don't run coprocessor dissassembly on Risc-V or RP2040, as those don't have the RP2350 coprocessors
        pico_init_picotool()
        if(picotool_FOUND)
            # add custom disassembly if we have picotool
            set(EXTRA_COMMAND COMMAND picotool coprodis --quiet ${output_path}$<IF:$<BOOL:$<TARGET_PROPERTY:${TARGET},OUTPUT_NAME>>,$<TARGET_PROPERTY:${TARGET},OUTPUT_NAME>,$<TARGET_PROPERTY:${TARGET},NAME>>.dis ${output_path}$<IF:$<BOOL:$<TARGET_PROPERTY:${TARGET},OUTPUT_NAME>>,$<TARGET_PROPERTY:${TARGET},OUTPUT_NAME>,$<TARGET_PROPERTY:${TARGET},NAME>>.dis)
        endif()
    endif()
    add_custom_command(TARGET ${TARGET} POST_BUILD
            COMMAND ${CMAKE_OBJDUMP} -h $<TARGET_FILE:${TARGET}> > ${output_path}$<IF:$<BOOL:$<TARGET_PROPERTY:${TARGET},OUTPUT_NAME>>,$<TARGET_PROPERTY:${TARGET},OUTPUT_NAME>,$<TARGET_PROPERTY:${TARGET},NAME>>.dis
            COMMAND ${CMAKE_OBJDUMP} -d ${PICO_DISASM_OBJDUMP_ARGS} $<TARGET_FILE:${TARGET}> >> ${output_path}$<IF:$<BOOL:$<TARGET_PROPERTY:${TARGET},OUTPUT_NAME>>,$<TARGET_PROPERTY:${TARGET},OUTPUT_NAME>,$<TARGET_PROPERTY:${TARGET},NAME>>.dis
            ${EXTRA_COMMAND}
            VERBATIM
            BYPRODUCTS "${output_path}${output_name}.dis"
            )
endfunction()

# pico_add_extra_outputs(TARGET)
# \brief_nodesc\ Perform post-build actions for the target
#
# Perform picotool processing and add disassembly, hex, bin, map, and uf2 outputs for the target
function(pico_add_extra_outputs TARGET)
    if ("${CMAKE_GENERATOR}" STREQUAL "IAR Embedded Workbench for Arm")
        # For IAR, add the project directory to the include path, just in case
        # there are any .pio.h there that we won't find otherwise
        target_include_directories(${TARGET} PUBLIC $<TARGET_FILE_DIR:${TARGET}>)

        # For IAR, also hook in here to translate the linker script to ICF format
        # using the ldtrans tool, which must already be built and installed on
        # PATH. The result is placed where CMAKE_IAR_ILINK_ICF_FILE expects it.
        find_program(_ldtrans_executable ldtrans)
        if (NOT _ldtrans_executable)
            message(FATAL_ERROR
                "ldtrans not found on PATH. Build tools/ldtrans from pico-sdk "
                "using a host native toolchain and install it before "
                "configuring with this generator.")
        endif()

        # Build ldtrans options
        set(_ldtrans_args --format=iar)

        if (NOT PICO_DEFAULT_BINARY_TYPE)
            if (PICO_NO_FLASH)
                set(PICO_DEFAULT_BINARY_TYPE no_flash)
            elseif (PICO_USE_BLOCKED_RAM)
                set(PICO_DEFAULT_BINARY_TYPE blocked_ram)
            elseif (PICO_COPY_TO_RAM)
                set(PICO_DEFAULT_BINARY_TYPE copy_to_ram)
            else()
                set(PICO_DEFAULT_BINARY_TYPE default)
            endif()
        endif()
        get_target_property(_ldtrans_binary_type ${TARGET} PICO_TARGET_BINARY_TYPE)
        if (NOT _ldtrans_binary_type)
            set(_ldtrans_binary_type ${PICO_DEFAULT_BINARY_TYPE})
        endif()
        if (_ldtrans_binary_type STREQUAL "no_flash")
            list(APPEND _ldtrans_args --ram-only)
        endif()

        get_target_property(_ldtrans_binary_dir ${TARGET} BINARY_DIR)
        set(_ldtrans_generated_script "${_ldtrans_binary_dir}/${TARGET}")
        set_target_properties(${TARGET} PROPERTIES LDTRANS_GENERATED_SCRIPT "${_ldtrans_generated_script}")
        list(APPEND _ldtrans_args -o "${_ldtrans_generated_script}" --)

        # The options following -- need to be kept in line with
        # pico_standard_link, but we can't use generator expressions here!
        # We can however skip the options that ldtrans doesn't use.

        # add override paths from PICO_TARGET_LINKER_SCRIPT_OVERRIDE_PATHS
        get_target_property(_ldtrans_override_paths ${TARGET} PICO_TARGET_LINKER_SCRIPT_OVERRIDE_PATHS)
        if (NOT _ldtrans_override_paths)
            set(_ldtrans_override_paths "")
        endif()
        foreach(_ldtrans_path IN LISTS _ldtrans_override_paths)
            list(APPEND _ldtrans_args "-L${_ldtrans_path}")
        endforeach()

        # add include paths from PICO_LINKER_SCRIPT_INCLUDE_DIRS
        foreach(_ldtrans_path IN LISTS PICO_LINKER_SCRIPT_INCLUDE_DIRS)
            list(APPEND _ldtrans_args "-L${_ldtrans_path}")
        endforeach()

        # add default locations script, so they can be referenced by pico_set_linker_script_var variables
        list(APPEND _ldtrans_args "--script=${PICO_LINKER_DEFAULT_LOCATIONS_PATH}")

        # add variables set by pico_set_linker_script_var function
        get_target_property(_ldtrans_vars ${TARGET} PICO_TARGET_LINKER_SCRIPT_VARS)
        if (NOT _ldtrans_vars)
            set(_ldtrans_vars "")
        endif()
        foreach(_ldtrans_var IN LISTS _ldtrans_vars)
            list(APPEND _ldtrans_args "--defsym=${_ldtrans_var}")
        endforeach()

        # LINKER script will be PICO_TARGET_LINKER_SCRIPT if set on target, or ${CMAKE_CURRENT_LIST_DIR}/memmap_foo.ld
        # if PICO_TARGET_BINARY_TYPE is set to foo on the target, otherwise ${CMAKE_CURRENT_LIST_DIR}/memmap_${PICO_DEFAULT_BINARY_TYPE).ld
        get_target_property(_ldtrans_ldscript ${TARGET} PICO_TARGET_LINKER_SCRIPT)
        if (NOT _ldtrans_ldscript)
            set(_ldtrans_ldscript "${PICO_LINKER_SCRIPT_PATH}/memmap_${_ldtrans_binary_type}.ld")
        endif()
        list(APPEND _ldtrans_args "--script=${_ldtrans_ldscript}")

        execute_process(
            COMMAND "${_ldtrans_executable}" ${_ldtrans_args}
            RESULT_VARIABLE _ldtrans_result
            ERROR_VARIABLE _ldtrans_error
        )
        if (NOT _ldtrans_result EQUAL 0)
            message(FATAL_ERROR "ldtrans failed for target ${TARGET}:\n${_ldtrans_error}")
        endif()
    endif()

    # Disassembly will be nonsense for encrypted binaries,
    # so disassemble before picotool processing
    pico_add_dis_output(${TARGET})

    # Picotool processing (signing/encrypting/etc)
    # PICO_CMAKE_CONFIG: PICO_NO_PICOTOOL, Disable use/requirement for picotool meaning that UF2 output and signing/hashing and coprocoessor disassembly will all be unavailable, type=bool, default=0, group=build
    if (NOT PICO_NO_PICOTOOL)
        picotool_postprocess_binary(${TARGET} IS_ENCRYPTED)
    endif()

    if (PICO_32BIT)
        pico_add_hex_output(${TARGET})
    endif()
    pico_add_bin_output(${TARGET})
    pico_add_map_output(${TARGET})

    # PICO_CMAKE_CONFIG: PICO_NO_TARGET_NAME, Don't define PICO_TARGET_NAME, type=bool, default=0, group=build
    # PICO_BUILD_DEFINE: PICO_TARGET_NAME, Name of the build target being compiled (unless PICO_NO_TARGET_NAME set in build), type=string, default=target name, group=build
    if (NOT PICO_NO_TARGET_NAME)
        target_compile_definitions(${TARGET} PRIVATE
                PICO_TARGET_NAME="${TARGET}"
                )
    endif()

    if (PICO_SYMLINK_ELF_AS_FILENAME)
        add_custom_target(${TARGET}_symlinked)
        add_dependencies(${TARGET}_symlinked ${TARGET})

        add_custom_command(TARGET ${TARGET}_symlinked POST_BUILD
                COMMAND rm -f "${PICO_SYMLINK_ELF_AS_FILENAME}"
                COMMAND ln -s -r $<TARGET_FILE:${TARGET}> "${PICO_SYMLINK_ELF_AS_FILENAME}"
                COMMENT "Symlinking from ${PICO_SYMLINK_ELF_AS_FILENAME} to ${TARGET}"
                BYPRODUCTS "${PICO_SYMLINK_ELF_AS_FILENAME}"
                )
    endif ()
    # PICO_CMAKE_CONFIG: PICO_NO_UF2, Disable UF2 output, type=bool, default=0, group=build
    if (NOT (PICO_NO_UF2 OR PICO_NO_PICOTOOL))
        pico_add_uf2_output(${TARGET})
    endif()
endfunction()

# PICO_CMAKE_CONFIG: PICO_NO_HARDWARE, Option as to whether the build is not targeting an RP2040 or RP2350 device, type=bool, default=1 when PICO_PLATFORM is host, 0 otherwise, group=build
# PICO_BUILD_DEFINE: PICO_NO_HARDWARE, Whether the build is not targeting an RP2040 or RP2350 device, type=bool, default=1 when PICO_PLATFORM is host, 0 otherwise, group=build
set(PICO_NO_HARDWARE "0" CACHE INTERNAL "")
# PICO_CMAKE_CONFIG: PICO_ON_DEVICE, Option as to whether the build is targeting an RP2040 or RP2350 device, type=bool, default=0 when PICO_PLATFORM is host, 1 otherwise, group=build
# PICO_BUILD_DEFINE: PICO_ON_DEVICE, Whether the build is targeting an RP2040 or RP2350 device, type=bool, default=0 when PICO_PLATFORM is host, 1 otherwise, group=build
set(PICO_ON_DEVICE "1" CACHE INTERNAL "")

set(CMAKE_EXECUTABLE_SUFFIX .elf)
set(CMAKE_EXECUTABLE_SUFFIX "${CMAKE_EXECUTABLE_SUFFIX}" PARENT_SCOPE)
