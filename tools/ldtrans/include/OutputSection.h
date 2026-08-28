/*
 * Copyright (c) 2026 Raspberry Pi Ltd.
 *
 * SPDX-License-Identifier: BSD-3-Clause
 */

#ifndef INCLUDE_OUTPUTSECTION_H_
#define INCLUDE_OUTPUTSECTION_H_

#include <charconv>
#include <string>

enum class ArchiveSpecType : std::uint8_t
{
    None,
    Specified,
    Any,
};

struct FileSpec
{
    SourceLocation location;
    ArchiveSpecType archive_type;
    std::string archive;
    std::string file;
    std::string dump() const
    {
        switch (archive_type) {
        case ArchiveSpecType::None:
            return file + " not in an archive";
        case ArchiveSpecType::Specified:
            if (file.empty())
                return "any file in archive " + archive;
            else
                return file + " in archive " + archive;
        case ArchiveSpecType::Any:
            return file + " in any archive (or none)";
        default:
            return "<unknown>";
        }
    }
};

enum class SortType : std::uint8_t
{
    ByName,
    ByAlignment,
};

struct SectionListItem
{
    std::optional<SourceLocation> location; /* optional because it can be implicit "*" in GNU syntax */
    std::string sections;
    std::shared_ptr<std::vector<FileSpec>> exclude_files = std::make_shared<std::vector<FileSpec>>();
    std::vector<SortType> sorts;
    std::string dump() const
    {
        std::string result = "sections: " + sections;
        if (!empty(*exclude_files)) {
            const char* sep = ", excluding those in ";
            for (const auto& exclusion : *exclude_files) {
                result += sep + exclusion.dump();
                sep = " or ";
            }
        }
        for (const auto& sort : sorts)
            result += (std::string) ", sorted by " + (sort == SortType::ByName ? "name" : "alignment");
        return result;
    }
};

using SectionListItemPtr = std::shared_ptr<SectionListItem>;

struct FileFilter
{
    SourceLocation location;
    FileSpec files;
    std::vector<FileSpec> exclude_files;
    bool sorted_by_name = false;
    std::string dump() const
    {
        std::string result = "files: " + files.dump();
        if (!empty(exclude_files)) {
            const char* sep = ", excluding those matching ";
            for (const auto& exclusion : exclude_files) {
                result += sep + exclusion.dump();
                sep = " or ";
            }
        }
        if (sorted_by_name)
            result += ", sorted by name";
        return result;
    }
};

using FileFilterPtr = std::shared_ptr<FileFilter>;

struct InputSectionFilter
{
    SourceLocation location;
    FileFilter files;
    std::shared_ptr<std::vector<SectionListItemPtr>> sections =
        std::make_shared<std::vector<SectionListItemPtr>>(
            std::initializer_list<SectionListItemPtr>{std::make_shared<SectionListItem>(SectionListItem{{}, "*"})});
    bool keep = false;
    std::vector<std::string> dump() const
    {
        std::vector<std::string> result;
        result.push_back(files.dump());
        for (const auto& section_filter : *sections)
            result.push_back(section_filter->dump());
        result.push_back(std::string("keep: ") + (keep ? "yes" : "no"));
        return result;
    }
};

using InputSectionFilterPtr = std::shared_ptr<InputSectionFilter>;

class ConstOutputSectionItemVisitor
{
public:
    virtual ~ConstOutputSectionItemVisitor() = default;

    virtual void visit(const class OutputSectionNop& item) = 0;
    virtual void visit(const class OutputSectionLocationMarker& item) = 0;
    virtual void visit(const class OutputSectionAlign& item) = 0;
    virtual void visit(const class OutputSectionInputSectionDescription& item) = 0;
};

class OutputSectionItem
{
public:
   virtual ~OutputSectionItem() = default;
   std::optional<SourceLocation> location() const { return m_location; }
   virtual std::string dump(const IdentifierManager& ids) const = 0;
   virtual void accept(ConstOutputSectionItemVisitor& visitor) = 0;
protected:
   OutputSectionItem() = default;
   explicit OutputSectionItem(SourceLocation location) : m_location(location) {}
private:
   std::optional<SourceLocation> m_location;
};

using OutputSectionItemPtr = std::shared_ptr<OutputSectionItem>;

class OutputSectionNop : public OutputSectionItem
{
public:
    std::string dump(const IdentifierManager& ids) const override
    {
        return "";
    }
    void accept(ConstOutputSectionItemVisitor& visitor) override { visitor.visit(*this); }
};

class OutputSectionLocationMarker : public OutputSectionItem
{
public:
    OutputSectionLocationMarker(SourceLocation location, unsigned index) : OutputSectionItem(location), m_index(index) {}
    std::string dump(const IdentifierManager& ids) const override
    {
        return "    anchor: " + std::to_string(m_index) + "\n";
    }
    void accept(ConstOutputSectionItemVisitor& visitor) override { visitor.visit(*this); }
    unsigned index() const { return m_index; }
private:
    unsigned m_index;
};

class OutputSectionAlign : public OutputSectionItem
{
public:
    OutputSectionAlign(SourceLocation location, uint64_t granule) : OutputSectionItem(location), m_granule(granule) {}
    std::string dump(const IdentifierManager& ids) const override
    {
        return "    align: " + std::to_string(m_granule) + "\n";
    }
    void accept(ConstOutputSectionItemVisitor& visitor) override { visitor.visit(*this); }
    uint64_t granule() const { return m_granule; }
private:
    uint64_t m_granule;
};

class OutputSectionInputSectionDescription : public OutputSectionItem
{
public:
    OutputSectionInputSectionDescription(InputSectionFilterPtr filter) : OutputSectionItem(filter->location), m_filter(filter) {}
    std::string dump(const IdentifierManager& ids) const override
    {
        std::string result = "    input section pattern:\n";
        for (const auto line : m_filter->dump())
            result += "      " + line + "\n";
        return result;
    }
    void accept(ConstOutputSectionItemVisitor& visitor) override { visitor.visit(*this); }
    const InputSectionFilter& filter(void) const { return *m_filter; }
private:
    InputSectionFilterPtr m_filter;
};

/* Distinct type from IdentifierId (which is typedefed to size_t, matching uint64_t on many platforms)
 * to avoid bison from complaining about type aliasing */
struct Fill
{
    uint64_t value;
};

struct OutputSection
{
    SourceLocation location;
    IdentifierId name;
    bool noload;
    DefinitionPtr vma;
    DefinitionPtr lma;
    std::optional<IdentifierId> vma_region;
    std::optional<IdentifierId> lma_region;
    std::optional<Fill> fill;
    std::shared_ptr<std::vector<OutputSectionItemPtr>> items;
    std::string dump(const IdentifierManager& ids) const
    {
        std::string result = "OUTPUT SECTION\n";
        result += "  location: " + g_source_manager.toFileLineColumn(location) + "\n";
        result += "  name: " + ids.toDisplayName(name) + "\n";
        result += (std::string) "  type: " + (noload ? "NOLOAD" : "<default>") + "\n";
        auto dump_expression = [&ids](DefinitionPtr d) {
            DumpVisitor expression_dump(ids);
            d->expression().accept(expression_dump);
            return expression_dump.result();
        };
        result += "  vma address: " + (vma ? dump_expression(vma) : "<undefined>") + "\n";
        result += "  lma address: " + (lma ? dump_expression(lma) : "<undefined>") + "\n";
        result += "  vma region: " + (vma_region ? ids.toDisplayName(*vma_region) : "<undefined>") + "\n";
        result += "  lma region: " + (lma_region ? ids.toDisplayName(*lma_region) : "<undefined>") + "\n";
        auto dump_integer = [](uint64_t value) -> std::string {
            char buffer[2 + 16 + 1] = "0x"; // includes null terminator, wherever that is
            auto [ptr, ec] = std::to_chars(buffer + 2, buffer + 2 + 16, value, 16);
            return ec == std::errc{} ? buffer : "<invalid>";
        };
        result += "  fill: " + (fill ? dump_integer(fill->value) : "<undefined>") + "\n";
        const char *header = "  items:\n";
        for (const auto& item : *items) {
            auto info = item->dump(ids);
            if (!info.empty()) {
                result += header + info;
                header = "";
            }
        }
        if (*header)
            result += "  items: <none>\n";
        return result;
    }
};

using OutputSectionPtr = std::shared_ptr<OutputSection>;

#endif /* sentry INCLUDE_OUTPUTSECTION_H_ */
