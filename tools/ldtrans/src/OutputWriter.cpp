/*
 * Copyright (c) 2026 Raspberry Pi Ltd.
 *
 * SPDX-License-Identifier: BSD-3-Clause
 */

#include "OutputWriter.h"

std::map<std::string_view, OutputWriter&> OutputWriter::g_formats;

void OutputWriter::register_writer(std::string_view name, OutputWriter& writer)
{
    g_formats.emplace(name, writer);
}

OutputWriter& OutputWriter::lookup_writer(const std::string_view name)
{
    if (name.empty())
        throw std::runtime_error("error: output format must be specified");
    auto it = g_formats.find(name);
    if (it == g_formats.end())
        throw std::runtime_error("error: unrecognised output format");
    return it->second;
}
