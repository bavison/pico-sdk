/*
 * Copyright (c) 2026 Raspberry Pi Ltd.
 *
 * SPDX-License-Identifier: BSD-3-Clause
 */

#ifndef INCLUDE_IDENTIFIER_H_
#define INCLUDE_IDENTIFIER_H_

#include <cstddef>

#include <string>
#include <unordered_map>
#include <vector>

using IdentifierId = std::size_t;

class IdentifierManager
{
public:
    IdentifierId toId(const std::string& raw)
    {
        auto [it, inserted] = m_by_name.try_emplace(raw, m_by_id.size());
        if (inserted) {
            Record r;
            r.raw = raw;
            r.display_name.reserve(raw.size()+2);
            r.display_name = "\"";
            for (auto c : raw) {
                if (c == '\\' || c == '"')
                    r.display_name.push_back('\\');
                r.display_name.push_back(c);
            }
            r.display_name.push_back('"');
            m_by_id.push_back(r);
        }
        return it->second;
    }

    const std::string& toRaw(IdentifierId id) const
    {
        return m_by_id[id].raw;
    }

    const std::string& toDisplayName(IdentifierId id) const
    {
        return m_by_id[id].display_name;
    }

private:
    std::unordered_map<std::string, IdentifierId> m_by_name;

    struct Record
    {
        std::string raw;
        std::string display_name;
    };

    std::vector<Record> m_by_id;
};

#endif /* sentry INCLUDE_IDENTIFIER_H_ */
