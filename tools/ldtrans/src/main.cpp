/*
 * Copyright (c) 2026 Raspberry Pi Ltd.
 *
 * SPDX-License-Identifier: BSD-3-Clause
 */

#include <cerrno>
#include <cstdlib>
#include <cstdio>

#include <filesystem>
#include <iostream>
#include <optional>
#include <string_view>
#include <system_error>

#include "Diagnostic.h"
#include "lexer.h"
#include "main.h"
#include "parser.hpp"

/* Queue of top-level files to process */
std::queue<std::unique_ptr<TopLevelSource>> g_input_queue;
/* Database of identifiers */
IdentifierManager g_identifier_manager;

int main(int argc, char* argv[])
{
    try {
        auto usage = [](int status) {
            std::cerr << "usage: ldtrans [ldtrans-options] -- [ld-options]\n";
            exit(status);
        };
        auto option = [](std::string_view str,
                              std::string_view prefix)
                              -> std::optional<std::string_view> {
            if (str.size() < prefix.size() ||
                    str.compare(0, prefix.size(), prefix) != 0)
                return std::nullopt;
            return str.substr(prefix.size());
        };

        std::filesystem::path output_file;
        std::string_view format_name;

        int i;
        for (i = 1; i < argc; ++i) {
            std::string_view arg(argv[i]);
            if (arg == "-h" || arg == "--help") {
                usage(EXIT_SUCCESS);
            } else if (i+1 <argc && arg == "-f") {
                format_name = argv[++i];
            } else if (auto a = option(arg, "--format=")) {
                format_name = *a;
            } else if (i+1 < argc && arg == "-o") {
                output_file = argv[++i];
            } else if (auto a = option(arg, "--output=")) {
                output_file = *a;
            } else if (arg == "-v" || arg == "--version") {
                // Print version information
            } else if (arg == "--") {
                // Move on to ld options
                break;
            } else {
                // Unrecognised option
                usage(EXIT_FAILURE);
            }
        }
        if (i == argc) {
            // Didn't find -- option
            usage(EXIT_FAILURE);
        }
        for (++i; i < argc; ++i) {
            std::string_view arg(argv[i]);
            if (auto a = option(arg, "--defsym=")) {
                // Handle symbol definition from command line
                // Only direct (=) assignment is permitted here
                // Perform minimal sanity checks: the string should conform to
                // <symbol>=<non-empty-expresion>
                // with no embedded semicolons that would terminate the code we inject!
                enum {
                    start,
                    identifier,
                    assignment,
                    expression
                } state = start;
                for (auto c : *a) {
                    switch (state) {
                    case start:
                        if (isalpha(static_cast<unsigned char>(c)) || c == '_' || c == '.')
                            state = identifier;
                        else
                            goto invalid_defsym;
                        break;
                    case identifier:
                        if (isalnum(static_cast<unsigned char>(c)) || c == '_' || c == '.' || c == '-')
                            state = identifier;
                        else if (c == '=')
                            state = assignment;
                        else
                            goto invalid_defsym;
                        break;
                    case assignment:
                    case expression:
                        if (c != ';')
                            state = expression;
                        else
                            goto invalid_defsym;
                        break;
                    }
                }
                if (state != expression) {
invalid_defsym:
                    throw(std::runtime_error("--defsym=" + std::string(*a) + ": error: syntax error"));
                }
                g_input_queue.push(std::make_unique<DefSymSource>(std::string(*a)));
            } else if (arg == "--gc-sections") {
                // Ignore
            } else if (auto a = option(arg, "-L")) {
                // Handle search path
                g_source_manager.addSearchPath(std::string(*a));
            } else if (auto a = option(arg, "-Map=")) {
                // Ignore
            } else if(auto a = option(arg, "--script=")) {
                // Handle input script file
                g_input_queue.push(std::make_unique<ScriptSource>(std::string(*a)));
            } else if (auto a = option(arg, "--wrap=")) {
                // Ignore
            } else if (i+1 < argc && arg == "-z") {
                // Ignore but skip next word
                ++i;
            } else {
                // Unrecognised option
                usage(EXIT_FAILURE);
            }
        }

        // Now process the input scripts and defsyms in order
        if (g_input_queue.empty())
            throw(std::runtime_error("No input provided"));
        auto& input = *g_input_queue.front();
        lexer_set_initial_input(input);
        yy::parser parser;
        parser.parse();
        // Subsequent inputs are pulled from the queue during <<EOF>> handling within parser.parse()

        // Now emit the output file (TODO)

        return EXIT_SUCCESS;
    }
    catch (const DiagnosticError& e) {
        std::cerr << e.format();
        return EXIT_FAILURE;
    }
    catch (const std::exception& e) {
        std::cerr << e.what() << "\n";
        return EXIT_FAILURE;
    }
}
