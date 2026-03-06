#!/bin/sh

set -e

git checkout -f portability-v4-filters
git checkout --detach

git checkout HEAD^^^^^^^^^^^^^^^^^^^^^^^^^^
#git diff portability-v4-filters^^^^^^^^^^^^^^^^^^^^^^^^^
#exit 1







# Standardise assembly comment introducer to '//'

for f in $(find src -name \*.S); do sed -i -E '
# Convert leading # into // but only if not a valid C preprocessor directive
/^ *#/ {
  /^ *# *(if|elif|else|endif|ifdef|ifndef|elifdef|elifndef|define|undef|include|line|error|warning|pragma)\>/ !{
    s/^( *)# ?/\1\/\/ /
  }
}
# @ at the start of a line is always a comment introducer
s/^@/\/\//
# Skip lines containing C-style comments that have a literal @ in the comment text!
/\/\*.*@.*\*\// !{
  # @ can appear within macro counters (or theoretically in literal strings)
  # as well as within comments, so attempt to isolate remaining comment
  # introducers by looking for the first @ on a line with a preceding space
  s/(([^ ]@|[^@])* )@/\1\/\//
}
' $f; done

# Insert space before assembly macro invocations that were left aligned

macros=$(find src -name \*.S -exec gawk '/^ *\.macro\>/ { print $2 }' {} \;)

for f in $(find src test -name \*.S ! -name asm_helper.S); do gawk -v list="$macros" '
# Build a database of all macro names used in codebase
BEGIN {
  n=split(list,m)
  for (i = 1; i <= n; ++i)
    macros[m[i]] = 1
}

# For these two macros, any number of leading spaces was reduced to 1 when hand-editing.
# Not sure we should keep this inconsistency now.
/^ *(gnu|wrapper)_func\>/ {
    sub(/^ +/, "", $0)
    print " " $0
    next
}

# Now look for those symbol names appearing in column 1
/^[[:alpha:]_][[:alnum:]_]*\>/ {
  if ($1 in macros) {
    sub(/ +$/, "", $0) # strip trailing whitespace on modified lines
    print " " $0
    next
  }
}

{
  print
 }
' $f > $f.tmp && mv $f.tmp $f; done

# Opcodes can't start in column 1 for some assemblers

for f in $(find src test -name \*.S); do gawk '
function is_opcode(line) {
  # Impractical to list all ARM opcodes here to distinguish them from other symbols
  # that may legitimately appear in column 1, so just add to this list as ncessary
  return line ~ /^(ldr|pop|push|str) /
}

{
  # Buffer all lines
  line[NR] = $0
}

END {
  for (i = 1; i <= NR; ++i) {
    if (line[i] ~ /^\/\//) {
      if (!in_comment && i < NR && is_opcode(line[i+1]))
        # Single-line comment followed by an opcode: indent
        print "    " line[i]
      else
        # Multi-line comment or not followed by opcode: leave as is
        print line[i]
      in_comment = 1
    } else {
      if (is_opcode(line[i]))
        # Opcode: indent
        print "    " line[i]
      else
        # Default: leave as is
        print line[i]
      in_comment = 0
    }
  }
}
' $f > $f.tmp && mv $f.tmp $f; done

# Move common once-per-file directives into pico/asm_helper.S
#
# The .syntax, .cpu and .thumb directives commonly differ for other toolchains.
# Also move the default .section directive (for section .text) even though this
# isn't universally present. A few files now need to include asm_helper.S for
# the first time.

git apply << EOF
--- a/src/rp2_common/pico_platform/include/pico/asm_helper.S
+++ b/src/rp2_common/pico_platform/include/pico/asm_helper.S
@@ -12,6 +12,11 @@
 
 #include "pico.h"
 
+.syntax unified
+.cpu cortex-m0plus
+.thumb
+.section .text
+
 // do not put align in here as it is used mid function sometimes
 .macro regular_func x
 .global \x
EOF

for f in $(find src test -name \*.S ! -name asm_helper.S); do gawk '
BEGIN {
  in_header = 1
  after_header = 1 # line at which to insert #include if necesary
}
{
  # Buffer all lines
  line[NR] = $0

  # Identify extent of header comment (and any following blank lines)
  if (in_header) {
    if (in_c_comment) {
      if ($0 ~ /\*\//) {
        in_c_comment = 0
      }
      next
    } else if ($0 ~ /^ *\/\*/) {
      # Started a C comment, did it finish on same line?
      had_c_header = 1
      if ($0 !~ /\*\//)
        in_c_comment = 1
      next
    } else if ((!had_c_header && $0 ~ /^ *\/\//) || $0 ~ /^ *$/) {
      # C++ comment or blank line, so header continues
      next
    } else {
      # First non-header, non-blank line
      after_header = NR
      in_header = 0
    }
  }
  
  # Scan for lines of interest
  if ($0 ~ /^#include "pico\/asm_helper\.S"$/)
    already_includes_asm_helper = 1
  if ($0 ~ /^#include "pico\.h"$/)
    include_pico_h_line = NR
  if ($0 ~ /^ *\.syntax\>/ ||
      $0 ~ /^ *\.cpu\>/ ||
      $0 ~ /^ *\.thumb\>/ ||
      ($0 ~ /^ *.section .text$/ && !already_seen_section_directive)) {
    delete_directives = 1
    del[NR] = 1
  }
  if ($0 ~ /^ *\.macro\>/)
    in_macro = 1
  if ($0 ~ /^ *\.endm\>/)
    in_macro = 0
  if ($0 ~ /^ *\.section\>/ && !in_macro)
    already_seen_section_directive = 1
}

END {
  # Include of pico.h is redundant if we now include asm_helper.S
  # because the latter includes the former, and for IAR we need to
  # include asm_helper.S first so that __ASSEMBLER__ is defined
  if (delete_directives || already_includes_asm_helper)
    del[include_pico_h_line] = 1

  # Run through buffer, deciding what to do
  for (i = 1; i <= NR; ++i) {
    if (i == after_header && delete_directives && !already_includes_asm_helper) {
      print "#include \"pico/asm_helper.S\""
      if (line[i+1] !~ /^#include/)
        print ""
    }
    # Print line unless deleted or a blank line following a deleted line
    if (!(i in del) && (line[i] !~ /^ *$/ || !((i-1) in del)))
      print line[i]
  }
}
' $f > $f.tmp && mv $f.tmp $f; done

# Ensure all function entry points are declared using a macro
#
# Every function should use regular_func or new macros weak_func or local_func,
# which are similar but for weak or file-scope functions.

git apply << EOF
--- a/src/rp2_common/pico_platform/include/pico/asm_helper.S
+++ b/src/rp2_common/pico_platform/include/pico/asm_helper.S
@@ -46,6 +46,19 @@ endm
 .word \func
 .endm
 
+.macro local_func x
+.type \x,%function
+.thumb_func
+\x:
+.endm
+
+.macro weak_func x
+.weak \x
+.type \x,%function
+.thumb_func
+\x:
+.endm
+
 #define code_in_code_area
 #define data_in_code_area
 
EOF

for f in $(find src test -name \*.S ! -name asm_helper.S); do gawk '
# On first pass, buffer the whole file, but skip .type directives: these are
# sometimes missing and when they are present, their position relative to
# other directives is inconsistent, making matching harder, while not aiding
# in identifying the places where a macro is needed
/^ *\.type\>/ {
  next
}
{
  line[++i] = $0
}
END {
  j = 1;
  while (j <= i) {
    # Identify the indexes of the next two *non-blank* lines since in many
    # cases these will otherwise trip up the pattern detection
    k = j + 1;
    while (k <= i && line[k] == "")
      ++k;
    l = k + 1;
    while (l <= i && line[l] == "")
      ++l

    # Detect regular_func. Most often .global is before before .thumb_func but occasionally the reverse
    if (l <= i &&
        ((match(line[j], /^ *\.global (\\?[[:alnum:]_]+)$/, m1) &&
          line[k] ~ /^ *\.thumb_func$/) ||
         (line[j] ~ /^ *\.thumb_func$/ &&
          match(line[k], /^ *\.global (\\?[[:alnum:]_]+)$/, m1))) &&
        match(line[l], /^(\\?[[:alnum:]_]+):$/, m2) &&
        m1[1] == m2[1]) {
      print " regular_func " m1[1]
      j = l + 1

    # Detect weak_func. .weak always precedes .thumb_func. Sometimes there is a comment to preserve
    } else if (match(line[j], /^ *\.weak (\\?[[:alnum:]_]+)( *\/\/.*)?$/, m1) &&
      k <= i && line[k] ~ /^ *\.thumb_func$/ &&
      l <= i && match(line[l], /^(\\?[[:alnum:]_]+):$/, m2) &&
      m1[1] == m2[1]) {
      print " weak_func " m1[1] m1[2]
      j = l + 1

    # Detect local_func, where there is a .thumb_func without a nearby .global or .weak
    } else if (line[j] ~ /^ *\.thumb_func$/ &&
      k <= i && match(line[k], /^(\\?[[:alnum:]_]+):$/, m)) {
      print " local_func " m[1]
      j = k + 1

    # Handle other lines
    } else {
      print line[j]
      j = j + 1
    }
  }
}
' $f > $f.tmp && mv $f.tmp $f; done

# Replace data-emitting directives with IAR equivalents

git apply << EOF
--- a/src/rp2_common/pico_platform/include/pico/asm_helper.S
+++ b/src/rp2_common/pico_platform/include/pico/asm_helper.S
@@ -12,6 +12,12 @@
 
 #include "pico.h"
 
+#define _asciz      .asciz
+#define dc8         .byte
+#define dc16        .hword
+#define dc32        .word
+#define ds          .space
+
 .syntax unified
 .cpu cortex-m0plus
 .thumb
EOF

#s/^ *\.asciz +(.*)/    dc8 \1, 0/;
for f in $(find src -name \*.S ! -name asm_helper.S); do sed -i -E '
s/^ *\.byte +/    dc8 /;
s/^ *\.hword +/    dc16 /;
s/^ *\.word +/    dc32 /;
s/^ *\.asciz +/    _asciz /;
s/^ *\.space +/ ds /;
' $f; done

# Replace .align directive with IAR alignrom directive

git apply << EOF
--- a/src/rp2_common/pico_platform/include/pico/asm_helper.S
+++ b/src/rp2_common/pico_platform/include/pico/asm_helper.S
@@ -12,6 +12,7 @@
 
 #include "pico.h"
 
+#define alignrom    .align
 #define _asciz      .asciz
 #define dc8         .byte
 #define dc16        .hword
EOF

for f in $(find src test -name \*.S ! -name asm_helper.S); do sed -i -E 's/^ *\.align *([0-9]+)/ alignrom \1/' $f; done

# Replace .equ directive with IAR equ directive

git apply << EOF
--- a/src/rp2_common/pico_divider/divider.S
+++ b/src/rp2_common/pico_divider/divider.S
@@ -4,6 +4,7 @@
  * SPDX-License-Identifier: BSD-3-Clause
  */
 
+#include "pico/asm_helper.S"
 #include "hardware/regs/addressmap.h"
 #include "hardware/divider_helper.S"
 
@@ -12,8 +13,6 @@
 
 // PICO_CONFIG: PICO_DIVIDER_DISABLE_INTERRUPTS, Disable interrupts around division such that divider state need not be saved/restored in exception handlers, default=0, group=pico_divider
 
-#include "pico/asm_helper.S"
-
 // PICO_CONFIG: PICO_DIVIDER_CALL_IDIV0, Whether 32 bit division by zero should call __aeabi_idiv0, default=1, group=pico_divider
 #ifndef PICO_DIVIDER_CALL_IDIV0
 #define PICO_DIVIDER_CALL_IDIV0 1
--- a/src/rp2_common/pico_platform/include/pico/asm_helper.S
+++ b/src/rp2_common/pico_platform/include/pico/asm_helper.S
@@ -18,6 +18,7 @@
 #define dc16        .hword
 #define dc32        .word
 #define ds          .space
+#define _equ        .equ
 
 .syntax unified
 .cpu cortex-m0plus
EOF

#for f in $(find src -name \*.S); do sed -i -E 's/^ *\.equ *([[:alnum:]_]+)( *, *)(.*)/\1 equ \3/' $f; done
for f in $(find src -name \*.S); do sed -i -E 's/^ *\.equ *([[:alnum:]_]+)( *, *)(.*)/ _equ \1\2\3/' $f; done

# Replace .end directive with end macro
#
# Also ensure it is present in all files except for those where an include is
# active (which is faulted by IAR).

git apply << EOF
--- a/src/rp2_common/pico_platform/include/pico/asm_helper.S
+++ b/src/rp2_common/pico_platform/include/pico/asm_helper.S
@@ -18,6 +18,7 @@
 #define dc16        .hword
 #define dc32        .word
 #define ds          .space
+#define end         .end
 #define _equ        .equ
 
 .syntax unified
EOF

for f in $(find src test -name \*.S); do gawk '
{
  # Buffer whole file
  line[NR] = $0
}
END {
  requires_end = ARGV[1] ~ /compile_time_choice\.S/ || ARGV[1] !~ /boot_stage2/ && ARGV[1] !~ /_helper\.S/
  # Strip the .end directive off files that should not have it
  if (!requires_end && line[NR-1] == "" && line[NR] ~ /^ *\.end *$/) {
    for (i = 1; i <= NR-2; ++i)
      print line[i]
  } else {
    for (i = 1; i <= NR; ++i)
      print line[i]
    # Add end directive to the other files (adding blank line if not already present)
    if (requires_end) {
      if (line[NR] != "")
        print ""
      print " end"
    }
  }
}
' $f > $f.tmp && mv $f.tmp $f; done

# Replace .global directive with IAR public directive

git apply << EOF
--- a/src/rp2_common/pico_platform/include/pico/asm_helper.S
+++ b/src/rp2_common/pico_platform/include/pico/asm_helper.S
@@ -20,6 +20,7 @@
 #define ds          .space
 #define end         .end
 #define _equ        .equ
+#define public      .global
 
 .syntax unified
 .cpu cortex-m0plus
EOF

for f in $(find src -name \*.S); do sed -i -E 's/^ *\.global *([[:alnum:]_]+)/ public \1/' $f; done

# Replace .macro and .endm directives with macros

git apply << EOF
--- a/src/rp2_common/pico_platform/include/pico/asm_helper.S
+++ b/src/rp2_common/pico_platform/include/pico/asm_helper.S
@@ -19,7 +19,15 @@
 #define dc32        .word
 #define ds          .space
 #define end         .end
+#define endm        .endm
 #define _equ        .equ
+#define _macro(x)   .macro x
+#define _macro_1arg(x,a)                   .macro x a
+#define _macro_2args(x,a,b)                .macro x a,b
+#define _macro_3args(x,a,b,c)              .macro x a,b,c
+#define _macro_5args(x,a,b,c,d,e)          .macro x a,b,c,d,e
+#define _macro_6args(x,a,b,c,d,e,f)        .macro x a,b,c,d,e,f
+#define _macro_9args(x,a,b,c,d,e,f,g,h,i)  .macro x a,b,c,d,e,f,g,h,i
 #define public      .global
 
 .syntax unified
EOF

for f in $(find src -name \*.S); do gawk '
# Skip one special file
ARGV[1] ~ /asm_helper\.S/ {
  print
  next
}
# Handle .macro
/^ *\.macro +/ {
  line = $0
  sub(/^ *\.macro +/, "", line)
  # GAS allows commas or whitespace as argument separators but we need to regularise on commas
  parts = split(line, part, /( +| *, *)/)
  if (parts == 1) {
    #print part[1] " macro"
    print "_macro(" part[1] ")"
  } else if (parts == 2) {
    #print part[1] " macro " part[2]
    print "_macro_1arg(" part[1] ", " part[2] ")"
  } else {
    #printf("%s macro %s", part[1], part[2])
    #for (i = 3; i <= parts; ++i)
    #  printf(", %s", part[i])
    #print ""
    printf("_macro_%dargs(%s", parts-1, part[1])
    for (i = 2; i <= parts; ++i)
      printf(", %s", part[i])
    print ")"
  }
  next
}
# Handle .endm
/^ *\.endm *$/ {
  print " endm"
  next
}
# Default to no edit
{ print }
' $f > $f.tmp && mv $f.tmp $f; done

# Abstract citations of macro arguments
#
# GAS requires a leading '\' when citing macro arguments within a macro
# definition, but IAR does not. Use C preprocessor macro MA (for "macro
# argument") to abstract this difference.
#
# Work around quirks:
# * When the macro argument was passed to WRAPPER_FUNC_NAME, it wasn't
#   being expanded before being concatenated with "__wrap_". Fix by the usual
#   C preprocessor two-level macro trick.
# * IAR has a bug whereby macros cannot be applied recursively. In
#   preparation, create an identical MA2 macro. This is used wherever we
#   need an assembly macro to pass on of its arguments to another assembly
#   macro if that macro itself uses the MA preprocessor macro.

git apply << 'EOF'
--- a/src/rp2_common/pico_platform/include/pico/asm_helper.S
+++ b/src/rp2_common/pico_platform/include/pico/asm_helper.S
@@ -30,6 +30,10 @@
 #define _macro_9args(x,a,b,c,d,e,f,g,h,i)  .macro x a,b,c,d,e,f,g,h,i
 #define public      .global
 
+// Expand a macro argument
+#define MA(x)  \##x
+#define MA2(x) \##x
+
 .syntax unified
 .cpu cortex-m0plus
 .thumb
--- a/src/rp2_common/pico_platform/include/pico/platform.h
+++ b/src/rp2_common/pico_platform/include/pico/platform.h
@@ -559,9 +559,9 @@ __force_inline static uint get_core_num(void) {
 #else // __ASSEMBLER__
 
 #if defined(__IASMARM__) || defined(PICO_USE_ARM_LINK)
-#define WRAPPER_FUNC_NAME(x) $Sub$$##x
+#define WRAPPER_FUNC_NAME(x) __CONCAT1($Sub$$,x)
 #else
-#define WRAPPER_FUNC_NAME(x) __wrap_##x
+#define WRAPPER_FUNC_NAME(x) __CONCAT1(__wrap_,x)
 #endif
 #define SECTION_NAME(x) .text.##x
 #define RAM_SECTION_NAME(x) .time_critical.##x
EOF

for f in $(find src -name \*.S); do gawk '
{
  # Skip one special file
  if (ARGV[1] ~ /asm_helper\.S/) {
    print
    next
  }
  # Have to split string in two passes because awk regex lacks lazy qualifiers
  if (match($0, /( *)(\/\/.*)$/, m)) {
    main = substr($0, 1, RSTART-1)
    ws = m[1]
    comment = m[2]
  } else {
    main    = $0
    ws      = ""
    comment = ""
  }
  if (match(main, /^([^\\]*)\\([[:alpha:]_][[:alnum:]_]*)([^\\]*)\\([[:alpha:]_][[:alnum:]_]*)(.*)/, m)) {
    #print m[1] m[2] m[3] m[4] m[5] (ws == "" ? "" : "  " ws) comment
    print m[1] "MA(" m[2] ")" m[3] "MA(" m[4] ")" m[5] substr(ws, 7) comment
  } else if (match(main, /^([^\\]*)\\([[:alpha:]_][[:alnum:]_]*)(.*)/, m)) {
    #print m[1] m[2] m[3] (ws == "" ? "" : " " ws)  comment
    # Ensure MA() does not appear within another MA() to avoid triggering IAR bug
    if (!no_ma2_on_next_line && index(tolower(main), "wrapper"))
      print m[1] "MA2(" m[2] ")" m[3] substr(ws, 5) comment
    else
      print m[1] "MA(" m[2] ")" m[3] substr(ws, 4) comment
  } else {
    print
  }
  # Use MA instead of MA2 within definitions of _float_wrapper_func and _double_wrapper_func
  no_ma2_on_next_line = $0 ~ /wrapper_func, x\)/
}
' $f > $f.tmp && mv $f.tmp $f; done

# Rename section so it doesn't start with a digit (macro argument compat)
#
# The problem is that section names end up being passed to the MA() macro, and
# in its IAR variant, this leaves the section name unchanged. But when the
# preprocessor looks at this to see if it can be further expanded, it sees a
# token that looks like a decimal number with an invalid suffix, and it throws
# an error.

sed -E -i 's/642float_shims/sixtyfourbit_to_float_shims/' src/rp2_common/pico_float/float_v1_rom_shim.S

# Replace .section, .data and .text directives with _section macro
#
# An alternate _root_section is required for heap and stack sections so that
# they don't get garbage-collected by the IAR linker. We also use this for
# .vectors, .binary_info_header and .reset even though it's not needed by IAR
# to reflect the fact that the ArmDS linker would also garbage collect them
# given the opportunity.

git apply << EOF
--- a/src/rp2_common/pico_platform/include/pico/asm_helper.S
+++ b/src/rp2_common/pico_platform/include/pico/asm_helper.S
@@ -29,6 +29,8 @@
 #define _macro_6args(x,a,b,c,d,e,f)        .macro x a,b,c,d,e,f
 #define _macro_9args(x,a,b,c,d,e,f,g,h,i)  .macro x a,b,c,d,e,f,g,h,i
 #define public      .global
+#define _section(name, flags, cd, align)   .section name, flags
+#define _root_section(name, flags, cd, align) .section name, flags
 
 // Expand a macro argument
 #define MA(x)  \##x
EOF

for f in $(find src -name \*.S); do gawk '
{
  # Skip one special file
  if (ARGV[1] ~ /asm_helper\.S/) {
    print
    next
  }
  # Defaults
  root = 0
  name = ".text"
  flags = "ax"
  cd = "CODE"
  align = 2
  if ($0 ~ /^ *\.data$/) {
    # Simple directive for main data section
    name = ".data"
    flags = "aw"
    cd = "DATA"
  } else if ($0 ~ /^ *\.text$/) {
    # Defaults suffice for main text section
  } else if (match($0, /^ *\.section ([[:alnum:]_.]+)$/, m)) {
    # Sections with simple names and no specified flags - deduce from name prefix
    name = m[1]
    if (m[1] ~ /^.data/) {
      flags = "aw"
      cd = "DATA"
    }
    if (m[1] == ".data.aeabi_bits_funcs")
      align = 4
  } else if (match($0, /^ *\.section ([[:alnum:]_.]+), "a"$/, m)) {
    # Sections with simple names and explicit "a" flag
    root = 1
    name  = m[1]
    flags = "a"
    cd = m[1] == ".binary_info_header" ? "CONST" : "DATA"
    if (m[1] == ".stack")
      align = 5
  } else if (match($0, /^ *\.section ([[:alnum:]_.]+), "aw"$/, m)) {
    # Sections with simple names and explicit "aw" flags
    name = m[1]
    flags = "aw"
    cd = "DATA"
  } else if (match($0, /^ *\.section ([[:alnum:]_.()]+)(, "ax")?$/, m)) {
    # Sections with preprocessed names and/or explicit "ax" flags
    if (m[1] == ".reset" || m[1] == ".vectors")
      root = 1
    name = m[1]
  } else {
    print
    next
  }
# Replace with these lines if abandoning _root_section and _section macros (flags variable can then be deleted too)
#  if (name ~ /\(/)
#    print " section BACKTICK_QUOTED(" name "):" cd (root ? ":ROOT(" : ":NOROOT(") align ")"
#  else
#    print " section `" name "`:" cd (root ? ":ROOT(" : ":NOROOT(") align ")"
  print (root ? " _root_section(" : " _section(") name ", \"" flags "\", " cd ", " align ")"
}
' $f > $f.tmp && mv $f.tmp $f; done

# Replace .set directive with IAR set directive

git apply << EOF
--- a/src/rp2_common/pico_platform/include/pico/asm_helper.S
+++ b/src/rp2_common/pico_platform/include/pico/asm_helper.S
@@ -31,6 +31,7 @@
 #define public      .global
 #define _section(name, flags, cd, align)   .section name, flags
 #define _root_section(name, flags, cd, align) .section name, flags
+#define _set        .set
 
 // Expand a macro argument
 #define MA(x)  \##x
EOF

#for f in $(find src -name \*.S); do sed -i -E 's/^ *\.set *([[:alnum:]_]+), */\1 set /' $f; done
for f in $(find src -name \*.S); do sed -i -E 's/^ *\.set\>/ _set/' $f; done

# Replace .rept/.endr directives with IAR rept/endr directives

git apply << EOF
--- a/src/rp2_common/pico_platform/include/pico/asm_helper.S
+++ b/src/rp2_common/pico_platform/include/pico/asm_helper.S
@@ -20,6 +20,7 @@
 #define ds          .space
 #define end         .end
 #define endm        .endm
+#define endr        .endr
 #define _equ        .equ
 #define _macro(x)   .macro x
 #define _macro_1arg(x,a)                   .macro x a
@@ -29,6 +30,7 @@
 #define _macro_6args(x,a,b,c,d,e,f)        .macro x a,b,c,d,e,f
 #define _macro_9args(x,a,b,c,d,e,f,g,h,i)  .macro x a,b,c,d,e,f,g,h,i
 #define public      .global
+#define rept        .rept
 #define _section(name, flags, cd, align)   .section name, flags
 #define _root_section(name, flags, cd, align) .section name, flags
 #define _set        .set
EOF

for f in $(find src -name \*.S); do sed -i -E 's/^ *\.(rept|endr)\>/ \1/' $f; done

# Replace .if/.else/.endif directives with IAR if/else/endif directives

git apply << EOF
--- a/src/rp2_common/pico_platform/include/pico/asm_helper.S
+++ b/src/rp2_common/pico_platform/include/pico/asm_helper.S
@@ -18,10 +18,13 @@
 #define dc16        .hword
 #define dc32        .word
 #define ds          .space
+#define else        .else
 #define end         .end
+#define endif       .endif
 #define endm        .endm
 #define endr        .endr
 #define _equ        .equ
+#define if          .if
 #define _macro(x)   .macro x
 #define _macro_1arg(x,a)                   .macro x a
 #define _macro_2args(x,a,b)                .macro x a,b
EOF

for f in $(find src -name \*.S); do sed -i -E 's/^ *\.(if|else|endif)\>/ \1/' $f; done

# Replace .ltorg directive with IAR ltorg directive

git apply << EOF
--- a/src/rp2_common/pico_platform/include/pico/asm_helper.S
+++ b/src/rp2_common/pico_platform/include/pico/asm_helper.S
@@ -25,6 +25,7 @@
 #define endr        .endr
 #define _equ        .equ
 #define if          .if
+#define ltorg       .ltorg
 #define _macro(x)   .macro x
 #define _macro_1arg(x,a)                   .macro x a
 #define _macro_2args(x,a,b)                .macro x a,b
EOF

for f in $(find src -name \*.S); do sed -i -E 's/^ *\.ltorg\>/ ltorg/' $f; done

# Replace .export directive with IAR export directive

for f in $(find src -name \*.S); do sed -i -E 's/^ *\.extern\>/ extern/' $f; done

# Remove .org directive
 #
 # IAR doesn't seem to have an equivalent of this. Unclear if it's actually needed?

for f in $(find src -name \*.S); do sed -i -E '/^ *\.org\>/d' $f; done

# Use 'r12' instead of 'ip' because the latter isn't recognised by IAR

for f in $(find src -name \*.S); do sed -i -E 's/\<ip\>/r12/g' $f; done

# Explicitly include all registers in asrs/lsls/lsrs instructions
#
# The Armv7-AR ARM permits the first register to be inferred in these
# instructions, which is presumably why GAS allows it. However. the Armv6-M
# ARM does not, and the IAR assembler follows these stricter rules.

for f in $(find src -name \*.S); do gawk '
{
  if (match($0, /^([/ ]+)(asrs|lsls|lsrs)( +)(r[0-7], *|MA\([[:alnum:]_]+\), *)(r[0-7]|#[[:alnum:]_]+)( *)(\/\/.*)?$/, m)) {
    if (length(m[6]) > 0) {
      old_comment_col = length(m[1] m[2] m[3] m[4] m[5] m[6])
      new_comment_col = length(m[1] m[2] m[3] m[4] m[4] m[5])
      if (new_comment_col + 1 <= old_comment_col)
        print m[1] m[2] m[3] m[4] m[4] m[5] sprintf("%*s", old_comment_col - new_comment_col, "") m[7]
    } else {
      print m[1] m[2] m[3] m[4] m[4] m[5]
    }
  } else {
    print
  }
}
' $f > $f.tmp && mv $f.tmp $f; done

# Macro invocations with 2 or more arguments should use comma delimiters
#
# The comma is optional for GAS, mandatory for IAR.

for f in $(find src -name \*.S); do sed -i -E 's/(shimmable_table_tail_call [[:alnum:]_]+) /\1, /' $f; done

# Refactor approach to macro-scope labels
#
# There are, in general, a numer of ways to express branches and labels in
# macros that are invoked multiple times within the same source file, when
# you can't use a normal label due to it being considered a redefinition of
# a symbol:
#
# * "altmacro" style local labels - not supported by armclang
# * PC-relative expressions as branch targets - not appropriate in all cases,
#   and also unsupported by armclang
# * numeric labels - not supported by IAR
# * macro counter ("\@") derived label names - not supported by IAR
#
# As there is no option that works with all toolchains, introduce a couple
# of C preprocessor macros to abstract the differences. These use the macro
# counter for armclang and altmacro local labels for other toolchains. The
# logic behind having GCC use local labels is that that scheme requires the
# label names to be declared ahead of use, and since GCC builds are expected
# to receive more regular testing, this will prevent build failures from
# being introduced for IAR users.

git apply << EOF
--- a/src/rp2_common/pico_divider/divider.S
+++ b/src/rp2_common/pico_divider/divider.S
@@ -34,10 +34,22 @@ _macro_1arg(div_section, name)
 
 // wait 8-n cycles for the hardware divider
 _macro_1arg(wait_div, n)
- rept (8-MA(n)) / 2
-  b 9f
-9:
- endr
+ if (8-MA(n) >= 8)
+ b l\@_1
+ endif
+l\@_1:
+ if (8-MA(n) >= 6)
+ b l\@_2
+ endif
+l\@_2:
+ if (8-MA(n) >= 4)
+ b l\@_3
+ endif
+l\@_3:
+ if (8-MA(n) >= 2)
+ b l\@_4
+ endif
+l\@_4:
  if (8-MA(n)) % 2
  nop
  endif
--- a/src/rp2_common/pico_platform/include/pico/asm_helper.S
+++ b/src/rp2_common/pico_platform/include/pico/asm_helper.S
@@ -44,6 +44,7 @@
 #define MA(x)  \##x
 #define MA2(x) \##x
 
+.altmacro
 .syntax unified
 .cpu cortex-m0plus
 .thumb
@@ -191,6 +192,18 @@ x:
 #error Unsupported toolchain
 
 
+#endif
+
+#if PICO_C_COMPILER_IS_ARMCLANG
+
+#define DECLARE_LOCAL_LABEL(l)
+#define LOCAL_LABEL(l) local_##l##_\@
+
+#else
+
+#define DECLARE_LOCAL_LABEL(l) local local_##l
+#define LOCAL_LABEL(l) local_##l
+
 #endif
 
 #endif // sentry INCLUDED_ASM_HELPER_S
EOF

for f in $(find src -name \*.S); do gawk '
function test_macro_introducer(row) {
  if (match(row, /^_macro_(1arg|[259]args)\(([[:alnum:]_]+),/, m)) {
    current_macro = m[2]
    return 1
  }
  return 0
}

# Build database of labels on first pass, no output yet as local labels must be declared before use
{
  ++i
  test_macro_introducer($0)
  row[i] = $0
  if (match(row[i], /^l\\@_([0-9]+):$/, m)) {
    idx = ++macro_label_count[current_macro]
    macro_label[current_macro][idx]["old"] = m[1]
    macro_label[current_macro][idx]["new"] = m[1]
  }
}

END {
  # Override some names to match earlier hand conversion
  macro_label["dneg"][1]["new"] = "skip"
  macro_label["mdunpack"][1]["new"] = "not_inf_or_nan"
  macro_label["mdunpack"][2]["new"] = "done"
  macro_label["mdunpacks"][1]["new"] = "mantissa_signed"
  macro_label["mdunpacks"][2]["new"] = "not_inf_or_nan"
  macro_label["mdunpacks"][3]["new"] = "done"
  macro_label["mul32_32_64"][1]["new"] = "overflow_handled"
  macro_label["muls32_s32_64"][1]["new"] = "overflow_handled"
  
  for (j = 1; j <= i; ++j) {
    if (test_macro_introducer(row[j])) {
      print row[j]
      if (current_macro in macro_label) {
        for (k = 1; k <= macro_label_count[current_macro]; ++k)
          print " DECLARE_LOCAL_LABEL(" macro_label[current_macro][k]["new"] ")"
      }
    } else if (match(row[j], /^( +)b(|cc|cs|eq|ge|gt|hi|hs|le|lo|ls|lt|mi|ne|pl|vc|vs)( +)l\\@_([0-9]+)( *)(\/\/.*)?$/, m)) {
      for (k = 1; k <= macro_label_count[current_macro]; ++k) {
        if (macro_label[current_macro][k]["old"] == m[4]) {
          if (length(m[5]) > 0) {
            old_comment_col = length(m[1] "b" m[2] m[3] "l\\@_" m[4] m[5])
            new_comment_col = length(m[1] "b" m[2] m[3] "LOCAL_LABEL(" macro_label[current_macro][k]["new"] ")")
            if (new_comment_col + 1 <= old_comment_col) {
              print m[1] "b" m[2] m[3] "LOCAL_LABEL(" macro_label[current_macro][k]["new"] ")" sprintf("%*s", old_comment_col - new_comment_col, "") m[6]
            } else {
              print m[1] "b" m[2] m[3] "LOCAL_LABEL(" macro_label[current_macro][k]["new"] ") " m[6]
            }
          } else {
            print m[1] "b" m[2] m[3] "LOCAL_LABEL(" macro_label[current_macro][k]["new"] ")"
          }
          break
        }
      }
    } else if (match(row[j], /^l\\@_([0-9]+):$/, m)) {
      for (k = 1; k <= macro_label_count[current_macro]; ++k) {
        if (macro_label[current_macro][k]["old"] == m[1]) {
          print "LOCAL_LABEL(" macro_label[current_macro][k]["new"] "):"
          break
        }
      }
    } else {
      print row[j]
    }
  }
}
' $f > $f.tmp && mv $f.tmp $f; done

# Replace remaining numeric labels with alphanumeric ones
#
# This is because numeric labels are not supported by IAR. Where reasonably
# easy to do, labels have been given meaningful names. More complex cases use
# a standardised prefix within a function, with a monotonically increasing
# suffix.

git apply << EOF
--- a/src/rp2_common/hardware_irq/irq_handler_chain.S
+++ b/src/rp2_common/hardware_irq/irq_handler_chain.S
@@ -45,7 +45,7 @@ irq_handler_chain_slots:
  endif
     // next is the 8 bit unsigned priority
     dc8 0x00
-1:
+
     // and finally the handler function pointer
     dc32 0x00000000
  _set next_slot_number, next_slot_number + 1
EOF

for f in $(find src -name \*.S); do gawk '
function test_function_introducer(row) {
  if (match(row, /^ .*section (__aeabi_d2f|__aeabi_f2d|__aeabi_l2f|__aeabi_ul2f|sincos)$/, m)) {
    # In a few cases branch targets are before the entry point so key off the section introducer instead
    current_func = m[1]
  }
  if (match(row, /^ +(regular|wrapper|gnu|local|weak)_func(_d2|_f1|_f2|_with_section)? +([[:alnum:]_]+)( *)(\/\/.*)?$/, m)) {
    # A few of these are alternative entry points that we need to branch over, so blacklist them
    if (m[3] != "__aeabi_cdcmpeq" &&
        m[3] != "__aeabi_cfcmpeq" &&
        m[3] != "__aeabi_i2d" &&
        m[3] != "dcordic_rot_step" &&
        m[3] != "dsin_shim" &&
        m[3] != "double2fix_shim" &&
        m[3] != "double2fix64_shim" &&
        m[3] != "double2int_z" &&
        m[3] != "double2int64_z" &&
        m[3] != "fix642float_shim" &&
        m[3] != "float2int_z" &&
        m[3] != "float2int64_z" &&
        m[3] != "int642float_shim")
      current_func = m[3]
  } else if (current_func == "" && row ~ /^[[:alnum:]_]+:$/) {
    # Some source files do not use the macros at all...
    split(row, a, ":")
    current_func = a[1]
  }
}

function lookup(line, f, old, dir) {
  if (dir == "f") {
    for (new = 1; new <= max_label[f]; ++new) {
      if (old_label[f, new] == old && label_line[f, new] > line) {
        result = new
        break
      }
    }
    if (new > max_label[f]) {
      print "Can'\''t find label " old " in function " f " forward from line " ARGV[1] ":" line > "/dev/stderr"
      exit 1
    }
  } else {
    for (new = max_label[f]; new >= 1 ; --new) {
      if (old_label[f, new] == old && label_line[f, new] <= line) {
        result = new
        break
      }
    }
    if (new == 0) {
      print "Can'\''t find label " old " in function " f " backward from line " ARGV[1] ":" line > "/dev/stderr"
      exit 1
    }
  }
  result = f "_" result
  if (result in map)
    result = map[result]
  return result
}

# Set up meaningful names
BEGIN {
  map["wait_ssi_ready_1"] = "poll_for_command_complete"
  if (ARGV[1] ~ /boot2_w25x10cl\.S/)
    map["_stage2_boot_1"] = "poll_for_read_completion"
  else
    map["_stage2_boot_1"] = "poll_for_write_completion"
  map["hw_divider_divmod_u32_1"] = "delay1"
  map["hw_divider_divmod_u32_2"] = "delay2"
  map["hw_divider_divmod_u32_3"] = "delay3"
  map["__clzdi2_1"] = "clzdi_msw_nonzero"
  map["__ctzdi2_1"] = "ctzdi_lsw_zero"
  map["divmod_s32s32_unsafe_1"] = "idiv_by0"
  map["divmod_s32s32_unsafe_2"] = "idiv_0by0"
  map["divmod_u32u32_unsafe_1"] = "uidiv_by0"
  map["divmod_u32u32_unsafe_2"] = "uidiv_0by0"
  map["divmod_s64s64_unsafe_1"] = "divmod_s64s64_1"
  map["divmod_s64s64_unsafe_2"] = "divmod_s64s64_2"
  map["divmod_s64s64_unsafe_3"] = "divmod_s64s64_3"
  map["divmod_s64s64_unsafe_4"] = "divmod_s64s64_4"
  map["divmod_s64s64_unsafe_5"] = "divmod_s64s64_5"
  map["divmod_s64s64_unsafe_6"] = "divmod_s64s64_6"
  map["divmod_u64u64_unsafe_1"] = "divmod_u64u64_1"
  map["divmod_u64u64_unsafe_2"] = "divmod_u64u64_2"
  map["divmod_u64u64_unsafe_3"] = "divmod_u64u64_3"
  map["divmod_u64u64_unsafe_4"] = "divmod_u64u64_4"
  map["divmod_u64u64_unsafe_5"] = "divmod_u64u64_5"
  map["divmod_u64u64_unsafe_6"] = "divmod_u64u64_6"
  map["divmod_u64u64_unsafe_7"] = "divmod_u64u64_7"
  map["divmod_u64u64_unsafe_8"] = "divmod_u64u64_8"
  map["divmod_u64u64_unsafe_9"] = "divmod_u64u64_9"
  map["divmod_u64u64_unsafe_10"] = "divmod_u64u64_10"
  map["divmod_u64u64_unsafe_11"] = "divmod_u64u64_11"
  map["divmod_u64u64_unsafe_12"] = "divmod_u64u64_12"
  map["divmod_u64u64_unsafe_13"] = "divmod_u64u64_13"
  map["divmod_u64u64_unsafe_14"] = "divmod_u64u64_14"
  map["divmod_u64u64_unsafe_15"] = "divmod_u64u64_15"
  map["divmod_u64u64_unsafe_16"] = "divmod_u64u64_16"
  map["divmod_u64u64_unsafe_17"] = "divmod_u64u64_17"
  map["divmod_u64u64_unsafe_18"] = "divmod_u64u64_18"
  map["divmod_u64u64_unsafe_19"] = "divmod_u64u64_19"
  map["divmod_u64u64_unsafe_20"] = "divmod_u64u64_20"
  map["divmod_u64u64_unsafe_21"] = "divmod_u64u64_21"
  map["divmod_u64u64_unsafe_22"] = "divmod_u64u64_22"
  map["divmod_u64u64_unsafe_23"] = "divmod_u64u64_23"
  map["divmod_u64u64_unsafe_24"] = "divmod_u64u64_24"
  map["divmod_u64u64_unsafe_25"] = "divmod_u64u64_25"
  map["divmod_u64u64_unsafe_26"] = "divmod_u64u64_26"
  map["divmod_u64u64_unsafe_27"] = "divmod_u64u64_27"
  map["divmod_u64u64_unsafe_28"] = "divmod_u64u64_28"
  map["divmod_u64u64_unsafe_29"] = "divmod_u64u64_29"
  map["divmod_u64u64_unsafe_30"] = "divmod_u64u64_30"
  map["divmod_u64u64_unsafe_31"] = "divmod_u64u64_31"
  map["divmod_u64u64_unsafe_32"] = "divmod_u64u64_32"
  map["divmod_u64u64_unsafe_33"] = "divmod_u64u64_33"
  map["__aeabi_ddiv_2"] = "ddiv_dsub_nan_helper_1"
  map["__aeabi_ddiv_3"] = "ddiv_dsub_nan_helper_2"
  map["__aeabi_ui2d_1"] = "__aeabi_i2d_1"
  map["__aeabi_ui2d_2"] = "__aeabi_i2d_2"
  map["dcordic_vec_step_1"] = "dcordic_1"
  map["dcordic_vec_step_2"] = "dcordic_2"
  map["fix642double_shim_1"] = "x2double_shims_1"
  map["fix642double_shim_2"] = "x2double_shims_2"
  map["fix642double_shim_3"] = "x2double_shims_3"
  map["fix642double_shim_4"] = "x2double_shims_4"
  map["fix642double_shim_5"] = "x2double_shims_5"
  map["fix642double_shim_6"] = "x2double_shims_6"
  map["fix642double_shim_7"] = "x2double_shims_7"
  map["fix642double_shim_8"] = "x2double_shims_8"
  map["fix642double_shim_9"] = "x2double_shims_9"
  map["fix642double_shim_10"] = "x2double_shims_10"
  map["fix642double_shim_11"] = "x2double_shims_11"
  map["dcos_shim_1"] = "dsin_shim_1"
  map["__aeabi_fdiv_2"] = "fdiv_fsub_nan_helper_1"
  map["__aeabi_fdiv_3"] = "fdiv_fsub_nan_helper_2"
  map["sqrtf_1"] = "srqtf_1" # typos!
  map["sqrtf_2"] = "srqtf_2" # typos!
  map["ufix642float_shim_1"] = "sixtyfourbit_to_float_shims_1"
  map["ufix642float_shim_2"] = "sixtyfourbit_to_float_shims_2"
  map["ufix642float_shim_3"] = "sixtyfourbit_to_float_shims_3"
  map["ufix642float_shim_4"] = "sixtyfourbit_to_float_shims_4"
  map["f2fix_1"] = "float264_shims_1"
  map["f2fix_2"] = "float264_shims_2"
  map["_reset_handler_1"] = "next"
  map["_reset_handler_2"] = "done"
  map["_reset_handler_3"] = "infinite"
}

# Build database of labels on first pass, no output yet since may include forward references
{
  next_i = ++i
  test_function_introducer($0)
  if (match($0, /^ *([0-9]+):( +[^\/ ].*)$/, m)) {
    # If label is on same line as instruction then add line break as new label is probably too long to fit in margin
    row[i] = m[1] ":"
    next_i = i + 1
    row[next_i] = sprintf("%*s", length(m[1]), "") " " m[2]
  } else {
    row[i] = $0
  }
  if (match(row[i], /^ *([0-9]+):( +\/\/.*)?$/, m)) {
    ++max_label[current_func]
    label_line[current_func, max_label[current_func]] = i
    old_label[current_func, max_label[current_func]] = m[1]
  }
  i = next_i
}
  
# Now output the whole file whilst performing substitutions
END {
  current_func = ""
  for (j = 1; j <= i; ++j) {
    test_function_introducer(row[j])
    if (match(row[j], /^( +)b(l?)(|cc|cs|eq|ge|gt|hi|hs|le|lo|ls|lt|mi|ne|pl|vc|vs)( +)([0-9]+)(b|f)( *)(\/\/.*)?$/, m)) {
      if (length(m[7]) > 0) {
        old_comment_col = length(m[1] "b" m[2] m[3] m[4] m[5] m[6] m[7])
        new_comment_col = length(m[1] "b" m[2] m[3] m[4] lookup(j, current_func, m[5], m[6]))
        if (new_comment_col + 1 <= old_comment_col)
          print m[1] "b" m[2] m[3] m[4] lookup(j, current_func, m[5], m[6]) sprintf("%*s", old_comment_col - new_comment_col, "") m[8]
        else
          print m[1] "b" m[2] m[3] m[4] lookup(j, current_func, m[5], m[6]) "\n" sprintf("%*s", old_comment_col, "") m[8]
      } else {
        print m[1] "b" m[2] m[3] m[4] lookup(j, current_func, m[5], m[6])
      }
    } else if (match(row[j], /^( *)([0-9]+):( *)(\/\/.*)?$/, m)) {
      if (length(m[4]) > 0) {
        old_comment_col = length(m[1] m[2] ":" m[3])
        new_comment_col = length(lookup(j, current_func, m[2], "") ":")
        if (new_comment_col + 1 <= old_comment_col)
          print lookup(j, current_func, m[2], "") ":" sprintf("%*s", old_comment_col - new_comment_col, "") m[4]
        else
          print lookup(j, current_func, m[2], "") ":\n" sprintf("%*s", old_comment_col, "") m[4]
      } else {
        print lookup(j, current_func, m[2], "") ":"
      }
    } else {
      print row[j]
    }
  }
}
' $f > $f.tmp && mv $f.tmp $f; done

# Change to use UAL syntax for movs in second-stage bootloaders
sed -i -E 's/^( *)mov( +r[0-7], *#[^ ]+)( |$)/\1movs\2/' src/rp2_common/boot_stage2/*.S





git diff reference

