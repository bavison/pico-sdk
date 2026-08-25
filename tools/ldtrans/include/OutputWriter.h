/*
 * Copyright (c) 2026 Raspberry Pi Ltd.
 *
 * SPDX-License-Identifier: BSD-3-Clause
 */

#ifndef INCLUDE_OUTPUTWRITER_H_
#define INCLUDE_OUTPUTWRITER_H_

#include <map>
#include <string_view>

#include "Script.h"

class OutputWriter
{
public:
    virtual ~OutputWriter() = default;

    static void register_writer(std::string_view name, OutputWriter& writer);
    static OutputWriter& lookup_writer(const std::string_view name);

    virtual void write(const Script& script, std::filesystem::path& base) = 0;

private:
    static std::map<std::string_view, OutputWriter&> g_formats;
};

#endif /* sentry INCLUDE_OUTPUTWRITER_H_ */
