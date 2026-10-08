/*
 * Copyright (c) 2026 Raspberry Pi Ltd.
 *
 * SPDX-License-Identifier: BSD-3-Clause
 */

#ifndef INCLUDE_SOURCELOCATION_H_
#define INCLUDE_SOURCELOCATION_H_

#include <cstddef>

#include <string>

using FileId = std::size_t;

/** A specific location in a specific file */
struct SourceLocation
{
    FileId file;
    std::size_t offset;
};

/** A location range in a specific file */
struct SourceRange
{
    FileId file;
    std::size_t begin;
    std::size_t length;
};

#endif /* sentry INCLUDE_SOURCELOCATION_H_ */
