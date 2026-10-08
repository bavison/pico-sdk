/*
 * Copyright (c) 2026 Raspberry Pi Ltd.
 *
 * SPDX-License-Identifier: BSD-3-Clause
 */

#ifndef INCLUDE_LEXER_H_
#define INCLUDE_LEXER_H_

#include "SourceLocation.h"
#include "SourceManager.h"

extern SourceLocation lexer_symbol_location;

void lexer_set_initial_input(const TopLevelSource& input);
void lexer_push_include(FileId new_file);

#endif /* sentry INCLUDE_LEXER_H_ */
