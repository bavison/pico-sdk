/*
 * Copyright (c) 2026 Raspberry Pi Ltd.
 *
 * SPDX-License-Identifier: BSD-3-Clause
 */

#include <fstream>
#include <iostream>

#include "IarWriter.h"
#include "OutputSection.h"

static IarWriter writer;
static const bool registered = [] { OutputWriter::register_writer("iar", writer); return true; } ();

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

struct FilesRemaining
{
    bool poisoned; /* we've encountered a GNU section definition that required matching filenames both positively and negatively - the remainder can't be expressed in IAR terms */
    SourceLocation first_ref; /* for generating diagnostic notes */
    bool negative_match = true; /* remaining files are those which DON'T match any in matches, else those which DO match at least one */
    StringSet matches; /* list of filespecs to compare */
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

/* Generated block and sub-block representation */

struct InitialiseDirectiveOutputState
{
    enum class OpenDirective
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

struct SectionSelector
{
    std::optional<std::string> sections;
    std::optional<std::string> objects;
};

class SectionSelectors : public BlockEntry
{
public:
    SectionSelectors(std::vector<SectionSelector>& section_selectors, bool keep) : m_section_selectors(std::move(section_selectors)), m_keep(keep) {}

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
        m_name(name), m_address(address), m_region(region), m_except_objects(except_objects), m_align(align), m_sorted(sorted), m_writable(writable), m_uninitialised(uninitialised) {}

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

    std::string name(void) { return m_name; }

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
        auto origin = region.origin().value();
        auto length = region.length().value();
        for (auto& os : g_script.output_sections) {
            if (os->noload || os->lma || os->lma_region) {
                if (os->vma) {
                    auto vma_value = os->vma ? os->vma->value() : 0;
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
        output << "define " << (ram ? "ram" : "rom") << " region " << g_script.identifiers.toRaw(region.name());
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
        bool uninitialised = os->noload;
        bool writable = initialised || uninitialised;
        bool in_sub_block = false;
        std::unique_ptr<Block> main_block = std::make_unique<Block>(
                g_script.identifiers.toRaw(os->name),
                os->vma,
                os->vma_region,
                "",
                std::optional<uint64_t>(),
                false,
                writable,
                uninitialised
        );
        std::unique_ptr<Block> init_block;
        if (initialised)
            init_block = std::make_unique<Block>(
                    g_script.identifiers.toRaw(os->name) + "_init",
                    os->lma,
                    os->lma_region
            );
        for (auto& item : *os->items) {
            if (auto location_marker = std::dynamic_pointer_cast<OutputSectionLocationMarker>(item)) {
                auto subblock = std::make_unique<Block>(
                        BlockName::next("anchor")
                );
                auto entry = std::make_unique<SubBlock>(std::move(subblock));
                main_block->push_back(std::move(entry));

            } else if (auto align = std::dynamic_pointer_cast<OutputSectionAlign>(item)) {
                auto subblock = std::make_unique<Block>(
                        BlockName::next("align"),
                        nullptr,
                        std::optional<IdentifierId>{},
                        "",
                        align->granule()
                );
                auto entry = std::make_unique<SubBlock>(std::move(subblock));
                main_block->push_back(std::move(entry));

            } else if (auto filter = std::dynamic_pointer_cast<OutputSectionInputSectionDescription>(item)) {
                if (filter->filter().files.sorted_by_name) {
                    Diagnostic warning(filter->filter().files.location, "warning: ignoring file-scope SORT directive which cannot be represented in IAR syntax");
                    std::cerr << warning.format();
                }
                std::string common_positive_file_pattern = iar_filespec(filter->filter().files.files);
                StringSet common_negative_file_patterns;
                for (const auto& pattern : filter->filter().files.exclude_files)
                    common_negative_file_patterns.emplace_back(iar_filespec(pattern));

                std::vector<SectionSelector> main_section_selectors;
                std::vector<SectionSelector> init_section_selectors;
                for (const auto& section_list_item : *filter->filter().sections) {
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

                    std::vector<SectionSelector> *p_main_section_selectors;
                    std::vector<SectionSelector> *p_init_section_selectors;
                    std::unique_ptr<Block> main_subblock;
                    std::unique_ptr<Block> init_subblock;
                    std::vector<SectionSelector> main_subblock_section_selectors;
                    std::vector<SectionSelector> init_subblock_section_selectors;

                    std::vector<SectionSelector> new_main_section_selectors;
                    std::vector<SectionSelector> new_init_section_selectors;
                    std::string except_clause;
                    SourceLocation loc = section_list_item->location ? *section_list_item->location : filter->filter().location;
                    std::optional<std::string> main_sections = section_list_item->sections == "*" ? std::optional<std::string>{} : section_list_item->sections;
                    std::optional<std::string> init_sections = section_list_item->sections == "*" ? std::optional<std::string>{} : section_list_item->sections + "_init";
                    auto it = all_remaining.find(section_list_item->sections);
                    if (it != all_remaining.end() && it->second.poisoned) {
                        throw DiagnosticError(loc, "error: cannot reference same section pattern more than once if any of them have both positive and negative file patterns",
                                {{ it->second.first_ref, "section pattern was first encountered here" }});
                    }
                    if (common_positive_file_pattern != "*" && !negative_file_patterns.empty()) {
                        if (it != all_remaining.end()) {
                            throw DiagnosticError(loc, "error: cannot reference same section pattern more than once if any of them have both positive and negative file patterns",
                                    {{ it->second.first_ref, "section pattern was first encountered here" }});
                        }
                        all_remaining[section_list_item->sections] = FilesRemaining{ true, loc };

                        new_main_section_selectors.emplace_back(SectionSelector{ main_sections, common_positive_file_pattern });
                        new_init_section_selectors.emplace_back(SectionSelector{ init_sections, common_positive_file_pattern });
                        const char* sep = "object ";
                        for (auto& negative_file_pattern : negative_file_patterns) {
                            except_clause += sep + negative_file_pattern + ",";
                            sep = "\n  object ";
                        }
                    } else if (common_positive_file_pattern != "*") {
                        bool fresh = it != all_remaining.end();
                        auto& remaining = all_remaining[section_list_item->sections]; /* default-constructs if not already present */
                        if (fresh)
                            remaining.first_ref = loc;
                        if (remaining.negative_match) {
                            auto it = std::find(remaining.matches.begin(), remaining.matches.end(), common_positive_file_pattern);
                            if (it == remaining.matches.end()) {
                                new_main_section_selectors.emplace_back(SectionSelector{ main_sections, common_positive_file_pattern });
                                new_init_section_selectors.emplace_back(SectionSelector{ init_sections, common_positive_file_pattern });
                                remaining.matches.emplace_back(common_positive_file_pattern);
                            } /* else do nothing, this filespec was already matched by an earlier specific match */
                        } else {
                            auto it = std::find(remaining.matches.begin(), remaining.matches.end(), common_positive_file_pattern);
                            if (it != remaining.matches.end()) {
                                new_main_section_selectors.emplace_back(SectionSelector{ main_sections, common_positive_file_pattern });
                                new_init_section_selectors.emplace_back(SectionSelector{ init_sections, common_positive_file_pattern });
                                remaining.matches.erase(it);
                            } /* else do nothing, this filespec was not excepted from an earlier global match */
                        }
                    } else if (!negative_file_patterns.empty()) {
                        bool fresh = it != all_remaining.end();
                        auto& remaining = all_remaining[section_list_item->sections]; /* default-constructs if not already present */
                        if (fresh)
                            remaining.first_ref = loc;
                        if (remaining.negative_match) {
                            StringSet excluded_files;
                            excluded_files = remaining.matches | negative_file_patterns;
                            remaining.negative_match = false;
                            remaining.matches = negative_file_patterns - remaining.matches;
                            new_main_section_selectors.emplace_back(SectionSelector{ main_sections, std::optional<std::string>{} });
                            new_init_section_selectors.emplace_back(SectionSelector{ init_sections, std::optional<std::string>{} });
                            const char* sep = "object ";
                            for (const auto& filespec : excluded_files) {
                                except_clause += sep + filespec + ",";
                                sep = "\n  object ";
                            }
                        } else {
                            StringSet included_files;
                            included_files = remaining.matches - negative_file_patterns;
                            remaining.matches = remaining.matches & negative_file_patterns;
                            for (const auto& filespec : included_files) {
                                new_main_section_selectors.emplace_back(SectionSelector{ main_sections, filespec });
                                new_init_section_selectors.emplace_back(SectionSelector{ init_sections, filespec });
                            }
                        }
                    } else {
                        /* Catch-all case with no filtering by filename */
                        bool fresh = it != all_remaining.end();
                        auto& remaining = all_remaining[section_list_item->sections]; /* default-constructs if not already present */
                        if (fresh)
                            remaining.first_ref = loc;
                        if (remaining.negative_match) {
                            const char* sep = "object ";
                            for (auto& negative_file_pattern : remaining.matches) {
                                except_clause += sep + negative_file_pattern + ",";
                                sep = "\n  object ";
                            }
                            new_main_section_selectors.emplace_back(SectionSelector{ main_sections, std::optional<std::string>{} });
                            new_init_section_selectors.emplace_back(SectionSelector{ init_sections, std::optional<std::string>{} });
                        } else {
                            for (auto& filespec : remaining.matches) {
                                new_main_section_selectors.emplace_back(SectionSelector{ main_sections, filespec });
                                new_init_section_selectors.emplace_back(SectionSelector{ init_sections, filespec });
                            }
                        }
                        remaining.negative_match = false;
                        remaining.matches.clear();
                    }

                    if (sorted) {
                        if (!except_clause.empty()) {
                            Diagnostic warning(*section_list_item->location, "warning: unable to represent both SORT and file exclusion in IAR syntax; ignoring file exclusion");
                            std::cerr << warning.format();
                        }
                        /* Init block doesn't use a subblock in SORT case */
                        main_subblock = std::make_unique<Block>(
                                BlockName::next("sort"),
                                nullptr,
                                std::optional<IdentifierId>{},
                                "",
                                std::optional<uint64_t>{},
                                true,
                                writable,
                                uninitialised
                        );
                        p_main_section_selectors = &main_subblock_section_selectors;
                        p_init_section_selectors = &init_section_selectors;
                    } else if (!except_clause.empty()) {
                        main_subblock = std::make_unique<Block>(
                                BlockName::next("except"),
                                nullptr,
                                std::optional<IdentifierId>{},
                                except_clause,
                                std::optional<uint64_t>{},
                                false,
                                writable,
                                uninitialised
                        );
                        if (initialised)
                            init_subblock = std::make_unique<Block>(
                                    BlockName::next("except"),
                                    nullptr,
                                    std::optional<IdentifierId>{},
                                    except_clause
                            );
                        p_main_section_selectors = &main_subblock_section_selectors;
                        p_init_section_selectors = &init_subblock_section_selectors;
                    } else {
                        p_main_section_selectors = &main_section_selectors;
                        p_init_section_selectors = &init_section_selectors;
                    }

                    p_main_section_selectors->insert(p_main_section_selectors->end(), std::make_move_iterator(new_main_section_selectors.begin()), std::make_move_iterator(new_main_section_selectors.end()));
                    if (initialised)
                        p_init_section_selectors->insert(p_init_section_selectors->end(), std::make_move_iterator(new_init_section_selectors.begin()), std::make_move_iterator(new_init_section_selectors.end()));

                    if (sorted) {
                        auto main_subblock_entry = std::make_unique<SectionSelectors>(main_subblock_section_selectors, filter->filter().keep);
                        main_subblock->push_back(std::move(main_subblock_entry));
                        auto main_entry = std::make_unique<SubBlock>(std::move(main_subblock));
                        main_block->push_back(std::move(main_entry));
                        if (initialised) {
                            auto init_entry = std::make_unique<SectionSelectors>(init_section_selectors, filter->filter().keep);
                            init_block->push_back(std::move(init_entry));
                        }
                    } else if (!except_clause.empty()) {
                        auto main_subblock_entry = std::make_unique<SectionSelectors>(main_subblock_section_selectors, filter->filter().keep);
                        main_subblock->push_back(std::move(main_subblock_entry));
                        auto main_entry = std::make_unique<SubBlock>(std::move(main_subblock));
                        main_block->push_back(std::move(main_entry));
                        if (initialised) {
                            auto init_subblock_entry = std::make_unique<SectionSelectors>(init_subblock_section_selectors, filter->filter().keep);
                            init_subblock->push_back(std::move(init_subblock_entry));
                            auto init_entry = std::make_unique<SubBlock>(std::move(init_subblock));
                            init_block->push_back(std::move(init_entry));
                        }
                    } else if (!main_section_selectors.empty()) {
                        auto main_entry = std::make_unique<SectionSelectors>(main_section_selectors, filter->filter().keep);
                        main_block->push_back(std::move(main_entry));
                        if (initialised) {
                            auto init_entry = std::make_unique<SectionSelectors>(init_section_selectors, filter->filter().keep);
                            init_block->push_back(std::move(init_entry));
                        }
                    }
                }
            }
        }
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
}
