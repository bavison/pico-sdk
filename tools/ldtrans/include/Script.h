/*
 * Copyright (c) 2026 Raspberry Pi Ltd.
 *
 * SPDX-License-Identifier: BSD-3-Clause
 */

#ifndef INCLUDE_SCRIPT_H_
#define INCLUDE_SCRIPT_H_

#include <cstddef>

#include <optional>
#include <vector>

#include "Identifier.h"
#include "MemoryRegion.h"
#include "OutputSection.h"
#include "SourceLocation.h"
#include "Symbol.h"

/* Types for identifiers which are indexes into vectors */
using MemoryRegionId = std::size_t;
using SymbolId = std::size_t;

struct Script
{
    /* Identifiers */
    IdentifierManager identifiers;
    /* Image entry point */
    std::optional<std::pair<SourceLocation,IdentifierId>> entry;
    /* Memory regions (order is significant in case an output section has to match using attributes) */
    std::vector<MemoryRegion> memory_regions;
    /* Map from memory region and region alias names to memory region index */
    std::unordered_map<IdentifierId, MemoryRegionId> memory_region_lookup;
    /* Symbols, stored in discovery order (though redefinitions overwrite the previous definition and so inherit its index) */
    std::vector<Symbol> symbols;
    /* Map from symbol to symbol index */
    std::unordered_map<IdentifierId, SymbolId> symbol_lookup;
    /* Definitions in dependency order */
    std::vector<Definition*> definition_order;
    /* Output sections */
    std::vector<OutputSectionPtr> output_sections;

    void SortDefinitions();
    void EvaluateDefinitions();
};

extern Script g_script;

#endif /* sentry INCLUDE_SCRIPT_H_ */
