/*
 * Copyright (c) 2026 Raspberry Pi Ltd.
 *
 * SPDX-License-Identifier: BSD-3-Clause
 */

#ifndef INCLUDE_SOURCEMANAGER_H_
#define INCLUDE_SOURCEMANAGER_H_

#include <cstddef>

#include <algorithm>
#include <filesystem>
#include <iterator>
#include <string>
#include <unordered_map>
#include <vector>

#include "SourceLocation.h"

class SourceManager
{
public:
    using StorageId = std::size_t;

    struct Storage
    {
        std::filesystem::path canonical_path; // empty for virtual files
        std::string contents;
        std::vector<std::size_t> line_starts; // unused for virtual files
        bool line_table_complete = false; // guard in case we have multiple inclusion
    };

    struct File
    {
        std::string display_name;
        StorageId storage;
    };

    struct LineColumn
    {
        std::size_t line;
        std::size_t column;
    };

    FileId loadFile(const std::string& display_name);

    FileId virtualFile(const std::string& display_name, const std::string& contents);

    const Storage& storage(StorageId id) const
    {
        return m_storage[id];
    }

    const File& file(FileId id) const
    {
        return m_file[id];
    }

    void addLine(SourceLocation location)
    {
        auto& s = m_storage[m_file[location.file].storage];
        /* In case we lex the same file twice or more, only build the line starts on the first pass */
        if (!s.line_table_complete)
            s.line_starts.push_back(location.offset);
    }

    void completeLineTable(FileId file)
    {
        auto& s = m_storage[m_file[file].storage];
        s.line_table_complete = true;
    }

    LineColumn decode(SourceLocation location) const;

    std::string toFileLine(SourceLocation location) const;

    std::string toFileLineColumn(SourceLocation location) const;

private:
    std::unordered_map<std::filesystem::path, StorageId> m_storage_cache;
    std::unordered_multimap<std::string, FileId> m_file_cache;
    std::vector<Storage> m_storage;
    std::vector<File> m_file;
};

extern SourceManager g_source_manager;

/* An item in the top-level source queue */
class TopLevelSource
{
public:
    explicit TopLevelSource(FileId file) : m_file(file) {}
    FileId getFileId() const
    {
        return m_file;
    }
    const std::string& getSpelling() const
    {
        return g_source_manager.file(m_file).display_name;
    }
    const std::string& getContents() const
    {
        return g_source_manager.storage(g_source_manager.file(m_file).storage).contents;
    }
private:
    FileId m_file;
};

/* If the item in the top-level source queue came from a --script option */
class ScriptSource : public TopLevelSource
{
public:
    ScriptSource(const std::string& path) : TopLevelSource(g_source_manager.loadFile(path)) {}
};

/* If the item in the top-level source queue came from a --defsym option */
class DefSymSource : public TopLevelSource
{
public:
    DefSymSource(const std::string& definition) : TopLevelSource(g_source_manager.virtualFile("--defsym=" + definition, definition + ";\n")) {}
};

#endif /* sentry INCLUDE_SOURCEMANAGER_H_ */
