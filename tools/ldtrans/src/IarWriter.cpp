/*
 * Copyright (c) 2026 Raspberry Pi Ltd.
 *
 * SPDX-License-Identifier: BSD-3-Clause
 */

#include <fstream>
#include <iostream>
#include <unordered_set>

#include "IarWriter.h"
#include "OutputSection.h"

static IarWriter writer;
static const bool registered = [] { OutputWriter::register_writer("iar", writer); return true; } ();

/* For propagating untranslatable PROVIDE definitions */

static std::unordered_set<const Definition*> m_untranslatable_definitions;

/* Set theory operations on groups of strings */

class StringSet
{
public:
    using const_iterator = std::vector<std::string>::const_iterator;

    StringSet(std::initializer_list<std::string> data) : m_data(std::move(data)) {}
    StringSet() = default;

    auto begin() const noexcept { return m_data.begin(); }
    void clear() noexcept       { m_data.clear(); }
    template <typename... Args>
    decltype(auto) emplace_back(Args&&... args) { return m_data.emplace_back(std::forward<Args>(args)...); }
    auto empty() const noexcept { return m_data.empty(); }
    auto end()   const noexcept { return m_data.end(); }
    auto erase(const_iterator pos) { return m_data.erase(pos); }

    bool contains(const std::string& item) const
    {
        return std::find(m_data.begin(), m_data.end(), item) != m_data.end();
    }

    /* operator& finds intersection */
    StringSet operator&(const StringSet& other) const
    {
        StringSet result;
        for (const auto& item : m_data)
            if (other.contains(item))
                result.m_data.push_back(item);
        return result;
    }

    /* operator| finds union */
    StringSet operator|(const StringSet& other) const
    {
        StringSet result = *this;
        for (const auto& item : other.m_data)
            if (!result.contains(item))
                result.m_data.push_back(item);
        return result;
    }

    /* operator- finds set-difference (elements in left set that are not in right set) */
    StringSet operator-(const StringSet& other) const
    {
        StringSet result;
        for (const auto& item: m_data)
            if (!other.contains(item))
                result.m_data.push_back(item);
        return result;
    }

private:
    std::vector<std::string> m_data;
};

/* Structures to track how GNU syntax can implicitly knock out matches for a subset of filespecs for any given section spec */

struct SectionSelector
{
    std::optional<std::string> sections;
    std::optional<std::string> objects;
};

class FilesRemaining
{
private:
    static std::string generate_except_clause(const StringSet& files)
    {
        std::string result;
        const char* sep = "object ";
        for (const auto& file : files) {
            result += sep + file + ",";
            sep = "\n  object ";
        }
        return result;
    }

public:
    /* Result to be emitted to the IAR file after applying a GNU rule to a FilesRemaining */
    struct Selection
    {
        std::vector<SectionSelector> main_selectors;
        std::vector<SectionSelector> init_selectors;
        std::string except_clause;
    };

    FilesRemaining(SourceLocation first_ref, bool poisoned = false) : m_poisoned(poisoned), m_first_ref(first_ref) {}

    bool poisoned() const noexcept { return m_poisoned; }
    SourceLocation first_ref() const noexcept { return m_first_ref; }

    /* Find emitted selection, and update files remaining, in case where GNU specifies both positive and negative patterns */
    Selection select(const std::optional<std::string>& main_sections, const std::optional<std::string>& init_sections,
            const std::string& positive_pattern, const StringSet& negative_patterns, bool initialised)
    {
        /* In this case we've already established that this section pattern hasn't been found before, so FilesRemaining contains nothing of interest */
        Selection result;
        result.main_selectors.emplace_back(SectionSelector{ main_sections, positive_pattern });
        if (initialised)
            result.init_selectors.emplace_back(SectionSelector{ init_sections, positive_pattern });
        result.except_clause = generate_except_clause(negative_patterns);
        return result;
    }

    /* Find emitted selection, and update files remaining, in case where GNU specifies only positive pattern */
    Selection select(const std::optional<std::string>& main_sections, const std::optional<std::string>& init_sections,
            const std::string& positive_pattern, bool initialised)
    {
        Selection result;
        if (m_negative_match) {
            auto it = std::find(m_matches.begin(), m_matches.end(), positive_pattern);
            if (it == m_matches.end()) {
                result.main_selectors.emplace_back(SectionSelector{ main_sections, positive_pattern });
                if (initialised)
                    result.init_selectors.emplace_back(SectionSelector{ init_sections, positive_pattern });
                /* now we have one more pattern we MUST NOT match... */
                m_matches.emplace_back(positive_pattern);
            } /* else do nothing, this filespec was already matched by an earlier specific match */
        } else {
            auto it = std::find(m_matches.begin(), m_matches.end(), positive_pattern);
            if (it != m_matches.end()) {
                result.main_selectors.emplace_back(SectionSelector{ main_sections, positive_pattern });
                if (initialised)
                    result.init_selectors.emplace_back(SectionSelector{ init_sections, positive_pattern });
                /*  now we have one fewer pattern that we CAN match...*/
                m_matches.erase(it);
            } /* else do nothing, this filespec was not excepted from an earlier global match */
        }
        return result;
    }

    /* Find emitted selection, and update files remaining, in case where GNU specifies negative patterns */
    Selection select(const std::optional<std::string>& main_sections, const std::optional<std::string>& init_sections,
            const StringSet& negative_patterns, bool initialised)
    {
        Selection result;
        if (m_negative_match) {
            /* files not to match this time is the union of those already positively matched (i.e. which are marked as MUST NOT match again)
              with the files that are excluded in the new GNU entry */
            StringSet excluded_files = m_matches | negative_patterns;
            /* in future, we CAN only match files from the new GNU entry that we also haven't previously positively matched */
            m_negative_match = false;
            m_matches = negative_patterns - m_matches;
            result.main_selectors.emplace_back(SectionSelector{ main_sections, std::optional<std::string>{} });
            if (initialised)
                result.init_selectors.emplace_back(SectionSelector{ init_sections, std::optional<std::string>{} });
            result.except_clause = generate_except_clause(excluded_files);
        } else {
            /* files to match this time are those that we already CAN, less those excluded by the new GNU entry */
            StringSet included_files = m_matches - negative_patterns;
            /* in future, we CAN only match files that we already CAN and which also aren't covered by the new GNU entry */
            m_matches = m_matches & negative_patterns;
            for (const auto& filespec : included_files) {
                result.main_selectors.emplace_back(SectionSelector{ main_sections, filespec });
                if (initialised)
                    result.init_selectors.emplace_back(SectionSelector{ init_sections, filespec });
            }
        }
        return result;
    }

    /* Find emitted selection, and update files remaining, in case where GNU specifies negative patterns */
    Selection select(const std::optional<std::string>& main_sections, const std::optional<std::string>& init_sections,
            bool initialised)
    {
        Selection result;
        if (m_negative_match) {
            result.main_selectors.emplace_back(SectionSelector{ main_sections, std::optional<std::string>{} });
            if (initialised)
                result.init_selectors.emplace_back(SectionSelector{ init_sections, std::optional<std::string>{} });
            result.except_clause = generate_except_clause(m_matches);
        } else {
            for (auto& filespec : m_matches) {
                result.main_selectors.emplace_back(SectionSelector{ main_sections, filespec });
                if (initialised)
                    result.init_selectors.emplace_back(SectionSelector{ init_sections, filespec });
            }
        }
        m_negative_match = false;
        m_matches.clear();
        return result;
    }

private:
    bool m_poisoned; /* we've encountered a GNU section definition that required matching filenames both positively and negatively - the remainder can't be expressed in IAR terms */
    SourceLocation m_first_ref; /* for generating diagnostic notes */
    bool m_negative_match = true; /* remaining files are those which DON'T match any in matches, else those which DO match at least one */
    StringSet m_matches; /* list of filespecs to compare */
};


/* Unique block name generator */

class BlockName
{
public:
    static std::string next(const std::string& type) {
        auto& index = m_next_indices[type];
        return "ldtrans_" + type + "_" + std::to_string(++index);
    }

private:
    static std::unordered_map<std::string, unsigned> m_next_indices;
};

std::unordered_map<std::string, unsigned> BlockName::m_next_indices;

/* Anchor block indexes generated during parsing can have gaps due to the
 * nature of a GLR parser (some reductions get discarded) so compact them
 * back again at output time using a map
 */

class AnchorBlockName
{
public:
    static std::string next(unsigned index)
    {
        return m_names[index] = BlockName::next("anchor");
    }

    static std::string lookup(unsigned index)
    {
        return m_names.at(index);
    }

private:
    static std::unordered_map<unsigned, std::string> m_names;
};

std::unordered_map<unsigned, std::string> AnchorBlockName::m_names;

/* Generated block and sub-block representation */

struct InitialiseDirectiveOutputState
{
    enum class OpenDirective : std::uint8_t
    {
        None,
        ByCopy,
        DoNot,
    } open_directive = OpenDirective::None;
    std::string except_objects;

    void close(std::ostream& output)
    {
        if (open_directive != OpenDirective::None) {
            if (!except_objects.empty())
                output << "\n} except {\n  " << except_objects;
            output << "\n};\n\n";
        }
        open_directive = OpenDirective::None;
        except_objects.clear();
    }
};

struct KeepDirectiveOutputState
{
    bool open = false;
    std::string except_objects;

    void close(std::ostream& output)
    {
        if (open) {
            if (!except_objects.empty())
                output << "\n} except {\n  " << except_objects;
            output << "\n};\n\n";
        }
        open = false;
        except_objects.clear();
    }
};

class Block;

class BlockEntry
{
public:
    virtual ~BlockEntry() = default;

    virtual void output_initialise_directives(std::ostream& output, InitialiseDirectiveOutputState& state, std::string except_objects, bool writable, bool uninitialised) const = 0;
    virtual void output_keep_directives(std::ostream& output, KeepDirectiveOutputState& state, std::string except_objects, bool writable) const = 0;
    virtual void output_define_directives(std::ostream& output, bool writable) const = 0;
};

class SubBlock : public BlockEntry
{
public:
    SubBlock(std::unique_ptr<Block> block) : m_block(std::move(block)) {}

    /* Define these later to resolve circular dependency in declarations */
    void output_initialise_directives(std::ostream& output, InitialiseDirectiveOutputState& state, std::string except_objects, bool writable, bool uninitialised) const override;
    void output_keep_directives(std::ostream& output, KeepDirectiveOutputState& state, std::string except_objects, bool writable) const override;
    void output_define_directives(std::ostream& output, bool writable) const override;

    const Block& block(void) const { return *m_block.get(); }

private:
    std::unique_ptr<Block> m_block;
};

class SectionSelectors : public BlockEntry
{
public:
    SectionSelectors(std::vector<SectionSelector> section_selectors, bool keep) : m_section_selectors(std::move(section_selectors)), m_keep(keep) {}

    void output_initialise_directives(std::ostream& output, InitialiseDirectiveOutputState& state, std::string except_objects, bool writable, bool uninitialised) const override
    {
        if (writable) {
            const char *intro;
            InitialiseDirectiveOutputState::OpenDirective new_open_directive = uninitialised ? InitialiseDirectiveOutputState::OpenDirective::DoNot : InitialiseDirectiveOutputState::OpenDirective::ByCopy;
            if (new_open_directive != state.open_directive || except_objects != state.except_objects) {
                state.close(output);
                if (uninitialised)
                    intro = "do not initialize {\n  ";
                else
                    intro = "initialize by copy {\n  ";
                state.open_directive = new_open_directive;
                state.except_objects = except_objects;
            } else {
                intro = "\n  ";
            }
            for (const auto& selection_selector : m_section_selectors) {
                if (selection_selector.sections && selection_selector.objects)
                    output << intro << "readwrite section " << *selection_selector.sections << " object " << *selection_selector.objects;
                else if (selection_selector.sections)
                    output << intro << "readwrite section " << *selection_selector.sections;
                else if (selection_selector.objects)
                    output << intro << "object " << *selection_selector.objects;
                intro = "\n  ";
            }
        }
    }

    void output_keep_directives(std::ostream& output, KeepDirectiveOutputState& state, std::string except_objects, bool writable) const override
    {
        if (m_keep) {
            const char* attribute = writable ? "readwrite" : "readonly";
            const char* intro;
            if (!state.open || except_objects != state.except_objects) {
                state.close(output);
                intro = "keep {\n  ";
                state.open = true;
                state.except_objects = except_objects;
            } else {
                intro = "\n  ";
            }
            for (const auto& selection_selector : m_section_selectors) {
                if (selection_selector.sections && selection_selector.objects)
                    output << intro << attribute << " section " << *selection_selector.sections << " object " << *selection_selector.objects;
                else if (selection_selector.sections)
                    output << intro << attribute << " section " << *selection_selector.sections;
                else if (selection_selector.objects)
                    output << intro << "object " << *selection_selector.objects;
                intro = "\n  ";
            }
        }
    }

    void output_define_directives(std::ostream& output, bool writable) const override
    {
        const char* attribute = writable ? "readwrite" : "readonly";
        for (const auto& selection_selector : m_section_selectors) {
            if (selection_selector.sections && selection_selector.objects)
                output << "  " << attribute << " section " << *selection_selector.sections << " object " << *selection_selector.objects << ",\n";
            else if (selection_selector.sections)
                output << "  " << attribute << " section " << *selection_selector.sections << ",\n";
            else if (selection_selector.objects)
                output << "  object " << *selection_selector.objects << ",\n";
        }
    }

private:
    std::vector<SectionSelector> m_section_selectors;
    bool m_keep;
};

class Block
{
public:
    Block(std::string name, DefinitionPtr address = nullptr, std::optional<IdentifierId> region = {}, std::string except_objects = "", std::optional<uint64_t> align = {}, bool sorted = false, bool writable = false, bool uninitialised = false) :
        m_name(std::move(name)), m_address(address), m_region(region), m_except_objects(except_objects), m_align(align), m_sorted(sorted), m_writable(writable), m_uninitialised(uninitialised) {}

    void push_back(std::unique_ptr<BlockEntry> entry)
    {
        m_entries.push_back(std::move(entry));
    }

    void output_initialise_directives(std::ostream& output, InitialiseDirectiveOutputState& state) const
    {
        for (const auto& entry : m_entries)
            entry->output_initialise_directives(output, state, m_except_objects, m_writable, m_uninitialised);
    }

    void output_keep_directives(std::ostream& output, KeepDirectiveOutputState& state) const
    {
        for (const auto& entry : m_entries)
            entry->output_keep_directives(output, state, m_except_objects, m_writable);
    }

    void output_define_directives(std::ostream& output) const
    {
        for (const auto& entry : m_entries) {
            if (auto sub = dynamic_cast<const SubBlock*>(entry.get())) {
                sub->block().output_define_directives(output);
            }
        }

        const char* attribute = m_writable ? "readwrite" : "readonly";
        output << "define block " << m_name;
        if (m_sorted)
            output << " with alphabetical order";
        else
            output << " with fixed order";
        if (m_align)
            output << ", alignment = " << std::dec << *m_align;
        output << " {\n";
        for (const auto& entry : m_entries)
            entry->output_define_directives(output, m_writable);
        if (!m_except_objects.empty())
            output << "} except {\n  " << m_except_objects << std::endl;
        output << "};\n\n";
    }

    const std::string& name(void) const { return m_name; }

private:
    std::vector<std::unique_ptr<BlockEntry>> m_entries;
    std::string m_name;
    DefinitionPtr m_address;
    std::optional<IdentifierId> m_region;
    std::string m_except_objects;
    std::optional<uint64_t> m_align;
    bool m_sorted;
    bool m_writable;
    bool m_uninitialised;
};

void SubBlock::output_initialise_directives(std::ostream& output, InitialiseDirectiveOutputState& state, std::string except_objects, bool writable, bool uninitialised) const
{
    m_block->output_initialise_directives(output, state);
}

void SubBlock::output_keep_directives(std::ostream& output, KeepDirectiveOutputState& state, std::string except_objects, bool writable) const
{
    m_block->output_keep_directives(output, state);
}

void SubBlock::output_define_directives(std::ostream& output, bool writable) const
{
    output << "  block " << m_block->name() << ",\n";
}

static std::string iar_filespec(const FileSpec& generic)
{
    switch (generic.archive_type) {
    case ArchiveSpecType::None:
        return generic.file + "()";
    case ArchiveSpecType::Specified:
        if (generic.file.empty())
            return std::string("*(") + generic.archive + ")";
        else
            return generic.file + "(" + generic.archive + ")";
    case ArchiveSpecType::Any:
        return generic.file;
    default:
        throw std::runtime_error("internal error: invalid archive type");
    }
}

static std::string iar_identifier(const std::string& raw)
{
    bool needs_quoting = raw.empty();
    auto invalid_first_char = [](unsigned char c) {
        return !isalpha(c) && c != '_' && c != '.';
    };
    if (!needs_quoting)
        needs_quoting = invalid_first_char(raw[0]);
    auto invalid_later_char = [](unsigned char c) {
        return !isalnum(c) && c != '_' && c != '.';
    };
    for (size_t i = 1; !needs_quoting && i < raw.size(); ++i)
        needs_quoting = invalid_later_char(raw[i]);
    if (!needs_quoting)
        return raw;

    std::string result = "`";
    for (size_t i = 0; i < raw.size(); ++i) {
        if (raw[i] == '`')
            result += '`';
        result += raw[i];
    }
    result += '`';
    return result;
}

static std::string iar_identifier(IdentifierId id)
{
    return iar_identifier(g_script.identifiers.toRaw(id));
}

class ProcessVisitor : public ConstOutputSectionItemVisitor
{
public:
    ProcessVisitor(Block* main_block, Block* init_block, std::unordered_map<std::string, FilesRemaining>& all_remaining, bool initialised, bool uninitialised, bool writable) :
        m_main_block(main_block), m_init_block(init_block), m_all_remaining(all_remaining), m_initialised(initialised), m_uninitialised(uninitialised), m_writable(writable) {}

    void visit(const OutputSectionNop& item) override { /* nothing to do */ }

    void visit(const OutputSectionLocationMarker& item) override
    {
        auto subblock = std::make_unique<Block>(
                AnchorBlockName::next(item.index())
        );
        auto entry = std::make_unique<SubBlock>(std::move(subblock));
        m_main_block->push_back(std::move(entry));
    }

    void visit(const OutputSectionAlign& item) override
    {
        auto subblock = std::make_unique<Block>(
                BlockName::next("align"),
                nullptr,
                std::optional<IdentifierId>{},
                "",
                item.granule()
        );
        auto entry = std::make_unique<SubBlock>(std::move(subblock));
        m_main_block->push_back(std::move(entry));
    }

    void visit(const OutputSectionInputSectionDescription& item) override
    {
        if (item.filter().files.sorted_by_name) {
            Diagnostic warning(item.filter().files.location, "warning: ignoring file-scope SORT directive which cannot be represented in IAR syntax");
            std::cerr << warning.format();
        }
        std::string common_positive_file_pattern = iar_filespec(item.filter().files.files);
        StringSet common_negative_file_patterns;
        for (const auto& pattern : item.filter().files.exclude_files)
            common_negative_file_patterns.emplace_back(iar_filespec(pattern));

        for (const auto& section_list_item : *item.filter().sections) {
            bool sorted = false;
            for (const auto& sort : section_list_item->sorts) {
                if (sort == SortType::ByName)
                    sorted = true;
                else if (sort == SortType::ByAlignment) {
                    Diagnostic warning(*section_list_item->location, "warning: ignoring SORT_BY_ALIGNMENT directive which cannot be represented in IAR syntax");
                    std::cerr << warning.format();
                }
            }
            StringSet negative_file_patterns = common_negative_file_patterns;
            for (const auto& pattern: *section_list_item->exclude_files)
                negative_file_patterns.emplace_back(iar_filespec(pattern));

            SourceLocation loc = section_list_item->location ? *section_list_item->location : item.filter().location;
            std::optional<std::string> main_sections = section_list_item->sections == "*" ? std::optional<std::string>{} : section_list_item->sections;
            std::optional<std::string> init_sections = section_list_item->sections == "*" ? std::optional<std::string>{} : section_list_item->sections + "_init";
            FilesRemaining::Selection selection;

            if (auto it = m_all_remaining.find(section_list_item->sections); it != m_all_remaining.end() && it->second.poisoned())
                throw DiagnosticError(loc, "error: cannot reference same section pattern more than once if any of them have both positive and negative file patterns",
                        {{ it->second.first_ref(), "section pattern was first encountered here" }});
            if (common_positive_file_pattern != "*" && !negative_file_patterns.empty()) {
                auto [it, inserted] = m_all_remaining.try_emplace(section_list_item->sections, FilesRemaining(loc, true));
                if (!inserted)
                    throw DiagnosticError(loc, "error: cannot reference same section pattern more than once if any of them have both positive and negative file patterns",
                            {{ it->second.first_ref(), "section pattern was first encountered here" }});
                selection = it->second.select(main_sections, init_sections, common_positive_file_pattern, negative_file_patterns, m_initialised);
            } else if (common_positive_file_pattern != "*") {
                auto [it, inserted] = m_all_remaining.try_emplace(section_list_item->sections, FilesRemaining(loc));
                selection = it->second.select(main_sections, init_sections, common_positive_file_pattern, m_initialised);
            } else if (!negative_file_patterns.empty()) {
                auto [it, inserted] = m_all_remaining.try_emplace(section_list_item->sections, FilesRemaining(loc));
                selection = it->second.select(main_sections, init_sections, negative_file_patterns, m_initialised);
            } else {
                auto [it, inserted] = m_all_remaining.try_emplace(section_list_item->sections, FilesRemaining(loc));
                selection = it->second.select(main_sections, init_sections, m_initialised);
            }

            if (sorted) {
                if (!selection.except_clause.empty()) {
                    Diagnostic warning(*section_list_item->location, "warning: unable to represent both SORT and file exclusion in IAR syntax; ignoring file exclusion");
                    std::cerr << warning.format();
                }
                /* Init block doesn't use a subblock in SORT case */
                std::unique_ptr<Block> main_subblock = std::make_unique<Block>(
                        BlockName::next("sort"),
                        nullptr,
                        std::optional<IdentifierId>{},
                        "",
                        std::optional<uint64_t>{},
                        true,
                        m_writable,
                        m_uninitialised
                );
                auto main_subblock_entry = std::make_unique<SectionSelectors>(std::move(selection.main_selectors), item.filter().keep);
                main_subblock->push_back(std::move(main_subblock_entry));
                auto main_entry = std::make_unique<SubBlock>(std::move(main_subblock));
                m_main_block->push_back(std::move(main_entry));
                if (m_initialised) {
                    auto init_entry = std::make_unique<SectionSelectors>(std::move(selection.init_selectors), item.filter().keep);
                    m_init_block->push_back(std::move(init_entry));
                }
            } else if (!selection.except_clause.empty()) {
                std::unique_ptr<Block> main_subblock = std::make_unique<Block>(
                        BlockName::next("except"),
                        nullptr,
                        std::optional<IdentifierId>{},
                        selection.except_clause,
                        std::optional<uint64_t>{},
                        false,
                        m_writable,
                        m_uninitialised
                );
                std::unique_ptr<Block> init_subblock;
                if (m_initialised) {
                    init_subblock = std::make_unique<Block>(
                            BlockName::next("except"),
                            nullptr,
                            std::optional<IdentifierId>{},
                            selection.except_clause
                    );
                }
                auto main_subblock_entry = std::make_unique<SectionSelectors>(std::move(selection.main_selectors), item.filter().keep);
                main_subblock->push_back(std::move(main_subblock_entry));
                auto main_entry = std::make_unique<SubBlock>(std::move(main_subblock));
                m_main_block->push_back(std::move(main_entry));
                if (m_initialised) {
                    auto init_subblock_entry = std::make_unique<SectionSelectors>(std::move(selection.init_selectors), item.filter().keep);
                    init_subblock->push_back(std::move(init_subblock_entry));
                    auto init_entry = std::make_unique<SubBlock>(std::move(init_subblock));
                    m_init_block->push_back(std::move(init_entry));
                }
            } else if (!selection.main_selectors.empty()) {
                auto main_entry = std::make_unique<SectionSelectors>(std::move(selection.main_selectors), item.filter().keep);
                m_main_block->push_back(std::move(main_entry));
                if (m_initialised) {
                    auto init_entry = std::make_unique<SectionSelectors>(std::move(selection.init_selectors), item.filter().keep);
                    m_init_block->push_back(std::move(init_entry));
                }
            }
        }
    }

private:
    Block* m_main_block;
    Block* m_init_block;
    std::unordered_map<std::string, FilesRemaining>& m_all_remaining;
    bool m_initialised;
    bool m_uninitialised;
    bool m_writable;
};

static std::pair<std::unique_ptr<Block>, std::unique_ptr<Block>> build_blocks(
        bool initialised, const OutputSection& os,
        std::unordered_map<std::string, FilesRemaining>& all_remaining)
{
    bool uninitialised = os.noload;
    bool writable = initialised || uninitialised;
    std::unique_ptr<Block> main_block = std::make_unique<Block>(
            iar_identifier(os.name),
            os.vma,
            os.vma_region,
            "",
            std::optional<uint64_t>(),
            false,
            writable,
            uninitialised
    );
    std::unique_ptr<Block> init_block;
    if (initialised)
        init_block = std::make_unique<Block>(
                iar_identifier(g_script.identifiers.toRaw(os.name) + "_init"),
                os.lma,
                os.lma_region
        );

    ProcessVisitor processor(main_block.get(), init_block.get(), all_remaining, initialised, uninitialised, writable);
    for (auto& item : *os.items)
        item->accept(processor);

    return { std::move(main_block), std::move(init_block) };
}

static std::string format_uint64(uint64_t value, SourceLocation location)
{
    char buffer[2 + 16 + 1] = "0x"; // includes null terminator, wherever that is
    auto [ptr, ec] = std::to_chars(buffer + 2, buffer + 2 + 16, value, 16);
    if (ec != std::errc{})
        throw DiagnosticError(location, "error: unable to represent integer");
    return buffer;
}

class FormatVisitor : public ConstExpressionVisitor
{
public:
    explicit FormatVisitor(bool provide_scope) : m_provide_scope(provide_scope) {}

    void visit(const SymbolExpression& expr) override
    {
        auto it = g_script.symbol_lookup.find(expr.identifier());
        if (it == g_script.symbol_lookup.end()) {
            if (m_provide_scope) {
                Diagnostic warning (expr.location(), "warning: undefined symbol within PROVIDE, skipping");
                std::cerr << warning.format();
                m_skip_me = true;
            }
        } else if (m_untranslatable_definitions.find(&g_script.symbols[it->second].definition()) != m_untranslatable_definitions.end()) {
            if (m_provide_scope) {
                Diagnostic warning (expr.location(), "warning: reference to skipped symbol within PROVIDE, skipping");
                std::cerr << warning.format();
                m_skip_me = true;
            } else {
                throw DiagnosticError(expr.location(), "error: reference to skipped symbol");
            }
        }
        m_result = iar_identifier(expr.identifier());
        m_precedence = IarOperatorPrecedence::Operand;
    }

    void visit(const IntegerExpression& expr) override
    {
        m_result = format_uint64(expr.value(), expr.location());
        m_precedence = IarOperatorPrecedence::Operand;
    }

    void visit(const UnaryExpression& expr) override
    {
        expr.sub_expr().accept(*this);
        /* Note that IAR requires parentheses when nesting one unary operator within another */
        if (m_precedence <= IarOperatorPrecedence::Unary)
            m_result = "(" + m_result + ")";
        switch (expr.operation()) {
        case UnaryOperator::Plus:
            m_result = "+" + m_result;
            break;
        case UnaryOperator::Minus:
            m_result = "-" + m_result;
            break;
        case UnaryOperator::BitwiseNot:
            m_result = "~" + m_result;
            break;
        case UnaryOperator::LogicalNot:
            m_result = "!" + m_result;
            break;
        case UnaryOperator::Align:
            throw DiagnosticError(expr.location(), "error: ALIGN only supported in assignments to location counter");
        default:
            throw DiagnosticError(expr.location(), "error: unable to represent subexpression");
        }
        m_precedence = IarOperatorPrecedence::Unary;
    }

    void visit(const BinaryExpression& expr) override
    {
        IarOperatorPrecedence precedence;
        bool left_associative; /* whether we need to add parentheses to right subexprs of same precedence */
        const char* op;
        switch (expr.operation()) {
        case BinaryOperator::Multiply:
            precedence = IarOperatorPrecedence::Multiplicative;
            left_associative = false;
            op = " * ";
            break;
        case BinaryOperator::Add:
            precedence = IarOperatorPrecedence::Additive;
            left_associative = false;
            op = " + ";
            break;
        case BinaryOperator::Subtract:
            precedence = IarOperatorPrecedence::Additive;
            left_associative = true;
            op = " - ";
            break;
        case BinaryOperator::GreaterOrEqual:
            precedence = IarOperatorPrecedence::Relational;
            left_associative = true;
            op = " >= ";
            break;
        case BinaryOperator::Greater:
            precedence = IarOperatorPrecedence::Relational;
            left_associative = true;
            op = " > ";
            break;
        case BinaryOperator::LessOrEqual:
            precedence = IarOperatorPrecedence::Relational;
            left_associative = true;
            op = " <= ";
            break;
        case BinaryOperator::Less:
            precedence = IarOperatorPrecedence::Relational;
            left_associative = true;
            op = " < ";
            break;
        case BinaryOperator::Equal:
            precedence = IarOperatorPrecedence::Equality;
            left_associative = true;
            op = " == ";
            break;
        case BinaryOperator::BitwiseAnd:
            precedence = IarOperatorPrecedence::BitwiseAnd;
            left_associative = false;
            op = " & ";
            break;
        case BinaryOperator::Max:
            /* do nothing - handled separately */
            break;
        default:
            throw DiagnosticError(expr.location(), "error: unable to represent subexpression");
        }

        expr.left_expr().accept(*this);
        auto left_expr = std::move(m_result);
        auto left_precedence = m_precedence;
        expr.right_expr().accept(*this);
        auto right_expr = std::move(m_result);
        auto right_precedence = m_precedence;

        if (expr.operation() == BinaryOperator::Max) {
            m_result = "max(" + left_expr + ", " + right_expr + ")";
            m_precedence = IarOperatorPrecedence::Operand;
        } else {
            if (left_precedence < precedence)
                left_expr = "(" + left_expr + ")";
            if (right_precedence < precedence || (right_precedence == precedence && left_associative))
                right_expr = "(" + right_expr + ")";
            m_result = left_expr + op + right_expr;
            m_precedence = precedence;
        }
    }

    void visit(const TernaryExpression& expr) override
    {
        expr.if_expr().accept(*this);
        auto if_expr = std::move(m_result);
        auto if_precedence = m_precedence;
        expr.then_expr().accept(*this);
        auto then_expr = std::move(m_result);
        expr.else_expr().accept(*this);
        auto else_expr = std::move(m_result);

        /* Since the ternary operator is already the lowest precedence, and is right associative,
         * the only place we might need to add parentheses is the left (if) subexpression */
        if (if_precedence == IarOperatorPrecedence::Ternary)
            if_expr = "(" + if_expr + ")";

        m_result = if_expr + " ? " + then_expr + " : " + else_expr;
        m_precedence = IarOperatorPrecedence::Ternary;
    }

    void visit(const SectionExpression& expr) override
    {
        switch (expr.operation()) {
        case SectionOperator::AlignOf:
            if (m_provide_scope) {
                Diagnostic warning(expr.location(), "warning: ALIGNOF encountered, but within PROVIDE, skipping");
                std::cerr << warning.format();
                m_result = "<unsupported>";
                m_skip_me = true;
            } else {
                throw DiagnosticError(expr.location(), "error: ALIGNOF encountered");
            }
            break;
        case SectionOperator::LoadAddr:
            /* This one is exactly the same in IAR syntax! */
            m_result = std::string("LOADADDR(") + iar_identifier(expr.section()) + ")";
            break;
        case SectionOperator::SizeOf:
            m_result = std::string("SIZE(") + iar_identifier(expr.section()) + ")";
            break;
        default:
            throw DiagnosticError(expr.location(), "error: unable to represent subexpression");
        }
        m_precedence = IarOperatorPrecedence::Operand;
    }

    void visit(const DefinedExpression& expr) override
    {
        m_result = std::string("isdefinedsymbol(") + iar_identifier(expr.symbol()) + ")";
        m_precedence = IarOperatorPrecedence::Operand;
    }

    void visit(const MemoryExpression& expr) override
    {
        switch (expr.operation()) {
        case MemoryOperator::Length:
            m_result = std::string("size(") + iar_identifier(expr.memory()) + ")";
            break;
        case MemoryOperator::Origin:
            m_result = std::string("start(") + iar_identifier(expr.memory()) + ")";
            break;
        default:
            throw DiagnosticError(expr.location(), "error: unable to represent subexpression");
        }
        m_precedence = IarOperatorPrecedence::Operand;
    }

    void visit(const LocationCounterExpression& expr) override
    {
        if (!expr.index())
            throw DiagnosticError(expr.location(), "error: unknown location counter");
        m_result = "start(" + AnchorBlockName::lookup(*expr.index()) + ")";
        m_precedence = IarOperatorPrecedence::Operand;
    }

    std::string result() const { return m_result; }
    bool skip_me() const { return m_skip_me; }

private:
    bool m_provide_scope;
    enum class IarOperatorPrecedence
    {
        Ternary,
        BitwiseAnd,
        Equality,
        Relational,
        Additive,
        Multiplicative,
        Unary,
        Operand,
    }
    m_precedence = IarOperatorPrecedence::Operand;
    std::string m_result;
    bool m_skip_me = false;
};

void IarWriter::write(const Script& script, std::filesystem::path& base)
{
    std::ofstream output_file_stream;

    if (base != "-") {
        if (base.empty())
            throw std::runtime_error("output file must be specified");
        std::filesystem::path icf_file = base;
        icf_file += ".icf";
        output_file_stream.open(icf_file);
        if (!output_file_stream)
            throw std::runtime_error("cannot open output file: " + icf_file.string());
    }

    std::ostream& output = base == "-" ? std::cout : output_file_stream;

    /* Memory space */
    output << "define memory mem with size = 4G;\n\n";

    /* Memory regions */
    for (auto& region : g_script.memory_regions) {
        bool ram = false;
        auto origin = region.origin().value().absolute;
        auto length = region.length().value().absolute;
        for (auto& os : g_script.output_sections) {
            if (os->noload || os->lma || os->lma_region) {
                if (os->vma) {
                    auto vma_value = os->vma ? os->vma->value().absolute : 0;
                    if (vma_value >= origin && vma_value < origin + length) {
                        ram = true;
                        break;
                    }
                } else if (os->vma_region && *os->vma_region == region.name()) {
                    ram = true;
                    break;
                }
            }
        }
        output << "define " << (ram ? "ram" : "rom") << " region " << iar_identifier(region.name());
        output << " = mem:[from " << std::hex << std::showbase << origin;
        output << " size " << std::hex << std::showbase << length;
        output << "];" << std::endl;
    }
    output << std::endl;

    /* Restructure output sections to fit IAR syntax better */
    std::vector<std::unique_ptr<Block>> top_level_blocks;
    std::unordered_map<std::string, FilesRemaining> all_remaining;
    for (auto& os : g_script.output_sections) {
        bool initialised = os->lma || os->lma_region;
        auto [main_block, init_block] = build_blocks(initialised, *os, all_remaining);
        top_level_blocks.push_back(std::move(main_block));
        if (initialised)
            top_level_blocks.push_back(std::move(init_block));
    }

    /* RAM initialisation */
    InitialiseDirectiveOutputState initialise_directive_output_state;
    for (const auto& block : top_level_blocks)
        block->output_initialise_directives(output, initialise_directive_output_state);
    initialise_directive_output_state.close(output);

    /* Specify kept sections */
    KeepDirectiveOutputState keep_directive_output_state;
    for (const auto& block : top_level_blocks)
        block->output_keep_directives(output, keep_directive_output_state);
    keep_directive_output_state.close(output);

    /* Define block layouts */
    for (const auto& block : top_level_blocks)
        block->output_define_directives(output);

    /* Mapping of top-level blocks to memory regions */
    std::optional<IdentifierId> current_vma_region;
    std::map<IdentifierId, std::vector<std::string>> block_mapping;
    for (const auto& os : g_script.output_sections) {
        if (os->vma_region && !os->vma)
            // new region name - but do lookup to resolve any possible alias
            current_vma_region = g_script.memory_regions[g_script.memory_region_lookup[*os->vma_region]].name();
        else if (os->vma && os->vma->value().type == DefinitionValueType::Absolute)
            current_vma_region.reset();
        // else either it's an error condition or we have a VMA expression which evaluates to the location counter, so keep the same region
        if (os->vma && os->vma_region) {
            Diagnostic warning { os->location, "warning: output section VMA region ignored in favour of VMA address" };
            std::cerr << warning.format();
        }
        if ((os->vma && os->vma->value().type == DefinitionValueType::LocationCounter) || (os->vma_region && !os->vma)) {
            if (!current_vma_region)
                throw DiagnosticError( os->location, "error: cannot determine VMA region for output section");
            block_mapping[*current_vma_region].emplace_back(iar_identifier(os->name));
        }

        /* With LMA, there's no equivalent persistence mechanism so we recalculate it each time */
        std::optional<IdentifierId> current_lma_region;
        if (os->lma_region && !os->lma)
            current_lma_region = g_script.memory_regions[g_script.memory_region_lookup[*os->lma_region]].name();
        else if (os->lma && os->lma->value().type == DefinitionValueType::LocationCounter)
            current_lma_region = current_vma_region;
        if (os->lma && os->lma_region) {
            Diagnostic warning { os->location, "warning: output section LMA region ignored in favour of LMA address" };
            std::cerr << warning.format();
        }
        if ((os->lma && os->lma->value().type == DefinitionValueType::LocationCounter) || (os->lma_region && !os->lma)) {
            if (!current_vma_region)
                throw DiagnosticError( os->location, "error: cannot determine LMA region for output section");
            block_mapping[*current_lma_region].emplace_back(iar_identifier(os->name) + "_init");
        }
    }
    for (const auto& this_region : block_mapping) {
        output << "place in " << iar_identifier(this_region.first) << " {\n";
        for (const auto& block: this_region.second)
            output << "  block " << block << ",\n";
        output << "}\n\n";
    }

    /* Definitions */
    for (const auto& def : g_script.definition_order) {
        if (def->visibility() != DefinitionVisibility::Standard) {
            Diagnostic warning { def->location(), std::string("warning: ") + (def->visibility() == DefinitionVisibility::Provide ? "PROVIDE" : "PROVIDE_HIDDEN") + " semantics cannot be expressed in destination format" };
            std::cerr << warning.format();
        }
        FormatVisitor format(def->visibility() != DefinitionVisibility::Standard);
        switch (def->kind()) {
        case DefinitionKind::TopLevelSymbol:
            def->expression().accept(format);
            if (!format.skip_me())
                output << "define exported symbol " << iar_identifier(*def->name()) << " = " << format.result() << ";" << std::endl;
            break;
        case DefinitionKind::SectionScopeSymbol:
            def->expression().accept(format);
            if (!format.skip_me())
                output << "define image symbol " << iar_identifier(*def->name()) << " = " << format.result() << ";" << std::endl;
            break;
        case DefinitionKind::OutputSectionVMA:
        case DefinitionKind::OutputSectionLMA:
            if (def->value().type == DefinitionValueType::Absolute) {
                if (!def->value().uses_location_counter)
                    def->expression().accept(format);
                if (!format.skip_me()) {
                    output << "place at address ";
                    if (def->value().uses_location_counter)
                        output << format_uint64(def->value().absolute, def->location());
                    else
                        output << format.result();
                    output << " { block " << iar_identifier(*def->name()) << " };" << std::endl;
                }
            }
            break;
        case DefinitionKind::Assertion:
            def->expression().accept(format);
            if (!format.skip_me())
                output << "check that " << format.result() << ";" << std::endl;
            break;
        default:
            break;
        }
        if (format.skip_me())
            m_untranslatable_definitions.insert(def);
    }
}
