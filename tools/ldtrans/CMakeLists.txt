cmake_minimum_required(VERSION 3.20...4.2)

project(ldtrans LANGUAGES CXX)

if (NOT CMAKE_BUILD_TYPE)
    set(CMAKE_BUILD_TYPE Release)
endif()

find_package(BISON REQUIRED)
find_package(FLEX REQUIRED)

BISON_TARGET(
    ld_parser
    src/parser.yy
    ${CMAKE_CURRENT_BINARY_DIR}/parser.cpp
)

FLEX_TARGET(
    ld_lexer
    src/lexer.ll
    ${CMAKE_CURRENT_BINARY_DIR}/lexer.cpp
)

ADD_FLEX_BISON_DEPENDENCY(ld_lexer ld_parser)

add_executable(ldtrans
        src/Diagnostic.cpp
        src/Definition.cpp
        src/IarWriter.cpp
        src/main.cpp
        src/OutputWriter.cpp
        src/Script.cpp
        src/SourceManager.cpp
        src/Symbol.cpp
        ${BISON_ld_parser_OUTPUTS}
        ${FLEX_ld_lexer_OUTPUTS}
)

target_compile_features(ldtrans PRIVATE cxx_std_17)

target_include_directories(ldtrans PRIVATE
    include
    ${CMAKE_CURRENT_BINARY_DIR}
)

if (MINGW)
    target_link_options(ldtrans PRIVATE
        -static
        -static-libgcc
        -static-libstdc++
    )
endif()

install(TARGETS ldtrans)

if (NOT LDTRANS_VERSION_STRING)
    message(FATAL_ERROR "LDTRANS_VERSION_STRING must be provided when building ldtrans")
endif()

configure_file( ${CMAKE_CURRENT_LIST_DIR}/version.h.in ${CMAKE_BINARY_DIR}/version.h)
