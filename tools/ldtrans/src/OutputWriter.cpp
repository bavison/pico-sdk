/*
 * Copyright (c) 2026 Raspberry Pi Ltd.
 *
 * SPDX-License-Identifier: BSD-3-Clause
 */

#include "OutputWriter.h"

void OutputWriter::register_writer(std::string_view name, OutputWriter& writer)
{
    formats().emplace(name, writer);
}

OutputWriter& OutputWriter::lookup_writer(const std::string_view name)
{
    if (name.empty())
        throw std::runtime_error("error: output format must be specified");
    auto it = formats().find(name);
    if (it == formats().end())
        throw std::runtime_error("error: unrecognised output format");
    return it->second;
}
