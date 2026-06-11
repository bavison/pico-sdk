/*
 * Copyright (c) 2026 Raspberry Pi Ltd.
 *
 * SPDX-License-Identifier: BSD-3-Clause
 */

#include <fstream>
#include <iostream>
#include <system_error>

#include "SourceManager.h"

SourceManager g_source_manager;

FileId SourceManager::loadFile(const std::string& display_name)
{
    // First check if we match both display name and canonical name.
    // Search by display name first (removes most hits, but not necessarily unique)
    // then test canonical version matches. This is because we only map from
    // display name to canonical name.
    auto canonical = std::filesystem::weakly_canonical(display_name);
    auto [start, end] = m_file_cache.equal_range(display_name);
    while (start != end) {
        if (m_storage[m_file[start->second].storage].canonical_path == canonical)
            break;
        ++start;
    }
    if (start != end)
        return start->second;

    // Next check if we have already read the file (canonical name matches)
    // but the display name differs.
    auto it = m_storage_cache.find(canonical);
    if (it != m_storage_cache.end()) {
        File f{display_name, it->second};
        FileId fid = m_file.size();
        m_file.push_back(f);
        m_file_cache.emplace(display_name, fid);
        return fid;
    }

    // The canonical name differs. It doesn't matter if the display name matches or
    // not, we have to read the file either way.

    // Open file
    std::ifstream ifs(canonical);
    if (!ifs)
        throw std::system_error(
            errno,
            std::generic_category(),
            display_name
        );

    // Create Storage with a std::string allocated large enough to hold the whole file
    ifs.seekg(0, std::ios::end);
    Storage s{canonical, std::string(static_cast<std::size_t>(ifs.tellg()), '\0'), {0}};

    // Load into string
    ifs.seekg(0);
    ifs.read(s.contents.data(), s.contents.size());

    // On Windows, tellg() gives the size including the CR part of CR-LF newlines,
    // but during the load process these will have been substituted for just LF
    // so we need to truncate the string down to the in-memory lemgth
    s.contents.resize(static_cast<std::size_t>(ifs.gcount()));

    // Add to our databases and return
    StorageId sid = m_storage.size();
    m_storage.push_back(s);
    m_storage_cache[canonical] = sid;
    File f{display_name, sid};
    FileId fid = m_file.size();
    m_file.push_back(f);
    m_file_cache.emplace(display_name, fid);
    return fid;
}

FileId SourceManager::virtualFile(const std::string& display_name, const std::string& contents)
{
    // This is simpler - no need for de-duplication
    Storage s{"", contents};
    StorageId sid = m_storage.size();
    m_storage.push_back(s);
    // No need to enter into storage cache here as we will never search virtual files for duplicates
    File f{display_name, sid};
    FileId fid = m_file.size();
    m_file.push_back(f);
    m_file_cache.emplace(display_name, fid);
    return fid;
}

SourceManager::LineColumn SourceManager::decode(SourceLocation location) const
{
    auto const& s = m_storage[m_file[location.file].storage];
    /* Slightly confusingly, we want upper_bound here because it gives us
     * the iterator to the following line start irrespective of whether
     * our location is at the start of a line or not (it effectively
     * finds the first iterator for which line_start > location, while
     * by contrast lower_bound effectively finds the first iterator for
     * which line_start >= location). But given that we want line numbers
     * to be 1-based anyway, the distance to the iterator for the
     * following line is actually the value we wanted anyway!
     */
    auto next_line = std::upper_bound(s.line_starts.begin(), s.line_starts.end(), location.offset);
    return LineColumn{ static_cast<std::size_t>(std::distance(s.line_starts.begin(), next_line)),
                       location.offset - *std::prev(next_line) + 1 };
}

std::string SourceManager::toFileLine(SourceLocation location) const
{
    auto const& s = m_storage[m_file[location.file].storage];
    if (s.canonical_path.empty()) {
        // Virtual file - skip offset
        return file(location.file).display_name;
    } else {
        auto [ line, ignore ] = decode(location);
        return file(location.file).display_name + ":" + std::to_string(line);
    }
}

std::string SourceManager::toFileLineColumn(SourceLocation location) const
{
    auto const& s = m_storage[m_file[location.file].storage];
    if (s.canonical_path.empty()) {
        // Virtual file - skip offsets
        return file(location.file).display_name;
    } else {
        auto [ line, column ] = decode(location);
        return file(location.file).display_name + ":" + std::to_string(line) + ":" + std::to_string(column);
    }
}
