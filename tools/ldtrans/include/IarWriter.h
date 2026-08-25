/*
 * Copyright (c) 2026 Raspberry Pi Ltd.
 *
 * SPDX-License-Identifier: BSD-3-Clause
 */

#ifndef INCLUDE_IARWRITER_H_
#define INCLUDE_IARWRITER_H_

#include "OutputWriter.h"

class IarWriter : public OutputWriter
{
    void write(const Script& script, std::filesystem::path& base) override;
};

#endif /* sentry INCLUDE_IARWRITER_H_ */
