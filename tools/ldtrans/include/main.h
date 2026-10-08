/*
 * Copyright (c) 2026 Raspberry Pi Ltd.
 *
 * SPDX-License-Identifier: BSD-3-Clause
 */

#ifndef INCLUDE_MAIN_H_
#define INCLUDE_MAIN_H_

#include <queue>
#include <memory>
#include <vector>

#include "Identifier.h"
#include "SourceLocation.h"
#include "SourceManager.h"

extern std::queue<std::unique_ptr<TopLevelSource>> g_input_queue;

#endif /* sentry INCLUDE_MAIN_H_ */
