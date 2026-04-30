#!/bin/sh

set -e
PS4='+ $LINENO: '
#git checkout -f portability-v4-filters
#git checkout --detach
#
#git checkout HEAD^^^^^^^^^^^^^^^^^^^^^^^^^^
##git diff portability-v4-filters^^^^^^^^^^^^^^^^^^^^^^^^^
##exit 1







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

# Insert space before left-aligned macro invocations wrapped in #define macros too

for f in $(find src -name \*.S); do sed -i -E 's/^PICO_RUNTIME_INIT_FUNC_RUNTIME/ &/' $f; done

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

# Ensure all function entry points are declared using a macro
#
# Every function should use regular_func or loacl_func or new macro local_func,
# which are similar but for weak or file-scope functions.
#
# A few cases were too complicated to script conversionn and so have been
# addressed using the patch.
#
# In some cases there were superfluous .thumb_func directives and in another
# one was present in RISC-V-only code where it shouldn't have been. These are
# addressed either implicitly by using the macros which are correct or by
# patching.

git apply << EOF
--- a/src/rp2040/pico_platform/include/pico/asm_helper.S
+++ b/src/rp2040/pico_platform/include/pico/asm_helper.S
@@ -29,6 +29,12 @@
 \x:
 .endm

+.macro local_func x
+.type \x,%function
+.thumb_func
+\x:
+.endm
+
 .macro weak_func x
 .weak \x
 .type \x,%function
@@ -92,6 +98,11 @@ regular_func                    macro           x
 x:
                                 endm

+local_func                      macro           x
+                                thumb
+x:
+                                endm
+
 weak_func                       macro           x
                                 pubweak         x
                                 thumb
--- a/src/rp2350/boot_stage2/asminclude/boot2_helpers/read_flash_sreg.S
+++ b/src/rp2350/boot_stage2/asminclude/boot2_helpers/read_flash_sreg.S
@@ -12,10 +12,10 @@
 // Pass status read cmd into r0/a0.
 // Returns status value in r0/a0.

-.global read_flash_sreg
-.type read_flash_sreg,%function
+ regular_func read_flash_sreg
+
 #ifdef __riscv
-read_flash_sreg:
+
     // wait_qmi_ready does not clobber t1, so use this rather than stack.
     mv t1, ra
     sw a0, QMI_DIRECT_TX_OFFSET(a3)
@@ -30,8 +30,6 @@ read_flash_sreg:

 #else

-.thumb_func
-read_flash_sreg:
     push {lr}
     str r0, [r3, #QMI_DIRECT_TX_OFFSET]
     // Dummy byte:
--- a/src/rp2350/pico_platform/include/pico/asm_helper.S
+++ b/src/rp2350/pico_platform/include/pico/asm_helper.S
@@ -42,6 +42,14 @@
 \x:
 .endm

+.macro local_func x
+.type \x,%function
+#ifndef __riscv
+.thumb_func
+#endif
+\x:
+.endm
+
 .macro weak_func x
 .weak \x
 .type \x,%function
@@ -111,6 +119,11 @@ regular_func                    macro           x
 x:
                                 endm

+local_func                      macro           x
+                                thumb
+x:
+                                endm
+
 weak_func                       macro           x
                                 pubweak         x
                                 thumb
--- a/src/rp2_common/pico_crt0/crt0.S
+++ b/src/rp2_common/pico_crt0/crt0.S
@@ -246,14 +246,11 @@ __default_isrs_start:
 .macro decl_isr name
 #if !PICO_MINIMAL_STORED_VECTOR_TABLE | PICO_NO_FLASH
 // We declare a weak label, so user can override
-.weak \name
+ weak_func \name
 #else
 // We declare a strong global label, so user can't override (their version would not automatically be used)
-.global \name
+ regular_func \name
 #endif
-.type \name,%function
-.thumb_func
-\name:
 .endm

 .macro if_irq_decl num func
--- a/src/rp2_common/pico_crt0/crt0_riscv.S
+++ b/src/rp2_common/pico_crt0/crt0_riscv.S
@@ -218,9 +218,7 @@ __default_isrs_start:
     decl_isr isr_irq\n
 .elseif \n < NUM_IRQS
     // We declare a strong label, so user can't override, since there is no vtable entry
-    .type isr_irq\n,%function
-    .thumb_func
-    isr_irq\n:
+    local_func isr_irq\n
 .endif
 .endm

--- a/src/rp2_common/pico_float/float_common_m33.S
+++ b/src/rp2_common/pico_float/float_common_m33.S
@@ -103,7 +103,6 @@ fix642float_softfp:
  b 3b

 // convert signed 32-bit fix to float, rounding; number of r0 bits after point in r1
-.thumb_func

 #if defined(__ARM_PCS_VFP)
  regular_func fix2float
--- a/src/rp2_common/pico_float/float_sci_m33_vfp.S
+++ b/src/rp2_common/pico_float/float_sci_m33_vfp.S
@@ -490,7 +490,6 @@ k_sc4:
  b 1f

  wrapper_func cosf
-.thumb_func
 #if defined(__ARM_PCS_VFP)
  vmov r0,s0
 #endif
--- a/src/rp2_common/pico_platform_panic/custom_panic_function.S
+++ b/src/rp2_common/pico_platform_panic/custom_panic_function.S
@@ -13,9 +13,7 @@
 #define PICO_PANIC_FUNCTION_IS_EMPTY (__CONCAT(PICO_PANIC_FUNCTION, 1))
 .text
 // Use a forwarding method here as it is a little simpler than renaming the symbol as it is used from assembler
-.weak panic // also allow override
-.type panic,%function
-panic:
+ weak_func panic // also allow override
 #ifdef __riscv
     // we seem to need to help gdb out with call frame on RISC-V
     .cfi_sections .debug_frame
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

for f in $(find src -name \*.S ! -name asm_helper.S); do sed -i -E '
s/^( *[[:alnum:]_]+:)? *\.byte +/\1    dc8 /;
s/^( *[[:alnum:]_]+:)? *\.hword +/\1    dc16 /;
s/^( *[[:alnum:]_]+:)? *\.long +/\1    dc32 /;
s/^( *[[:alnum:]_]+:)? *\.word +/\1    dc32 /;
s/^( *[[:alnum:]_]+:)? *\.quad +/\1    dc64 /;
s/^( *[[:alnum:]_]+:)? *\.float +/\1    dc32f /;
s/^( *[[:alnum:]_]+:)? *\.asciz +(.*)/\1    dc8 \2, 0/;
s/^( *[[:alnum:]_]+:)? *\.space +/\1 ds /;
' $f; done

# Replace .align and .p2align directives with IAR alignrom directive

for f in $(find src test -name \*.S ! -name asm_helper.S); do sed -i -E '
s/^ *\.align *(\\?[[:alnum:]]+)/ alignrom \1/;
s/^ *\.p2align *(\\?[[:alnum:]]+)/ alignrom \1/;
' $f; done

# Replace .equ directive with IAR equ directive

for f in $(find src -name \*.S); do sed -i -E 's/^ *\.equ *([[:alnum:]_]+)( *, *)(.*)/\1 equ \3/' $f; done

# Replace .end directive with IAR end directive
#
# Also ensure it is present in all files except for those where an include is
# active (which is faulted by IAR).

for f in $(find src test -name \*.S); do gawk '
{
  # Buffer whole file
  line[NR] = $0
}
END {
  requires_end = ARGV[1] ~ /compile_time_choice\.S/ || ARGV[1] !~ /boot_stage2/ && ARGV[1] !~ /_helper\.S/ && ARGV[1] !~ /\.inc\.S/
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

for f in $(find src -name \*.S); do sed -i -E 's/^ *\.global *([[:alnum:]_]+)/ public \1/' $f; done

# Replace .macro and .endm directives with IAR macro/endm directives

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
    print part[1] " macro"
  } else if (parts == 2) {
    print part[1] " macro " part[2]
  } else {
    printf("%s macro %s", part[1], part[2])
    for (i = 3; i <= parts; ++i)
      printf(", %s", part[i])
    print ""
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
# definition, and sometimes a trailing '\()', but IAR does not.
#
# When pasting a macro argument into a laregr token, IAR requires the
# use of __CONCAT.

git apply << 'EOF'
--- a/src/rp2_common/pico_crt0/crt0_riscv.S
+++ b/src/rp2_common/pico_crt0/crt0_riscv.S
@@ -168,7 +168,7 @@ check_irq_before_exit:
  public __soft_vector_table
 __soft_vector_table:
 vtable_irq_n macro n
-    dc32 isr_irq\n
+    dc32 __CONCAT(isr_irq,\n)
  endm

 .altmacro
@@ -215,10 +215,10 @@ decl_isr_bkpt macro name
 // Declare all the ISR labels
 decl_isr_n macro n
 .if \n < PICO_NUM_VTABLE_IRQS
-    decl_isr isr_irq\n
+    decl_isr __CONCAT(isr_irq,\n)
 .elseif \n < NUM_IRQS
     // We declare a strong label, so user can't override, since there is no vtable entry
-    local_func isr_irq\n
+    local_func __CONCAT(isr_irq,\n)
 .endif
  endm

--- a/src/rp2_common/pico_double/double_aeabi_dcp.S
+++ b/src/rp2_common/pico_double/double_aeabi_dcp.S
@@ -49,7 +49,7 @@ saving_func macro type, func, opt_label1='-', opt_label2='-'
  regular_func \opt_label2
 .endif
   // This is the actual entry point:
-\type\()_func \func
+  __CONCAT(\type\(),_func) \func
   PCMP apsr_nzcv
   bmi 1b
 1:
--- a/src/rp2_common/pico_double/double_sci_m33.S
+++ b/src/rp2_common/pico_double/double_sci_m33.S
@@ -36,7 +36,7 @@ movlong macro rx, n
  endm

 hardabi_wrapper_func macro type, func, argn
-\type\()_func \func
+ __CONCAT(\type\(),_func) \func
 #if defined(__ARM_PCS_VFP)
 .ifgt \argn - 0
  vmov r0,r1,d0
@@ -48,10 +48,10 @@ hardabi_wrapper_func macro type, func, argn
 .error "Unsupported argn: \argn"
 .endif
  push {lr}
- bl \func\()_entry
+ bl __CONCAT(\func\(),_entry)
  vmov d0,r0,r1
  pop {pc}
-\func\()_entry:
+__CONCAT(\func\(),_entry:)
 #endif
  endm

--- a/src/rp2_common/pico_float/float_aeabi_dcp.S
+++ b/src/rp2_common/pico_float/float_aeabi_dcp.S
@@ -51,7 +51,7 @@ saving_func macro type, func, opt_label1='-', opt_label2='-'
  regular_func \opt_label2
 .endif
   // This is the actual entry point:
-\type\()_func \func
+  __CONCAT(\type\(),_func) \func
   PCMP apsr_nzcv
   bmi 1b
 1:
--- a/src/rp2_common/pico_platform_compiler/include/pico/platform/compiler.h
+++ b/src/rp2_common/pico_platform_compiler/include/pico/platform/compiler.h
@@ -233,6 +233,9 @@ __force_inline static void __compiler_memory_barrier(void) {
 #error Unsupported toolchain
 #endif

+#define __CONCAT1(a, b) a ## b
+#define __CONCAT(a, b)  __CONCAT1(a, b)
+
 #if defined(__IASMARM__) || defined(PICO_USE_ARM_LINK)
 #define WRAPPER_FUNC_NAME(x) $Sub$$##x
 #else
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
  while (match(main, /^([^\\]*)\\([[:alpha:]_][[:alnum:]_]*)\\\(\)(.*)$/, m)) {
    main = m[1] m[2] m[3]
    if (ws != "")
      ws = "    " ws
  }
  while (match(main, /^([^\\]*)\\([[:alpha:]_][[:alnum:]_]*)(.*)$/, m)) {
    main = m[1] m[2] m[3]
    if (ws != "")
      ws = " " ws
  }
  print main ws comment
}
' $f > $f.tmp && mv $f.tmp $f; done

# Replace .section, .data and .text directives with IAR equivalents

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
    if (m[1] == "name") {
      cd = "DATA"
      align = "align"
    }
  } else if (match($0, /^ *\.section ([[:alnum:]_.]+), "a"$/, m)) {
    # Sections with simple names and explicit "a" flag
    root = 1
    name  = m[1]
    flags = "a"
    cd = m[1] == ".binary_info_header" ? "CONST" : "DATA"
    if (m[1] == "name")
      align = "align"
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
  if (name ~ /\(/ || name == "name")
    print " section BACKTICK_QUOTED(" name "):" cd (root ? ":ROOT(" : ":NOROOT(") align ")"
  else
    print " section `" name "`:" cd (root ? ":ROOT(" : ":NOROOT(") align ")"
}
' $f > $f.tmp && mv $f.tmp $f; done

# Replace .set directive with IAR set directive

for f in $(find src -name \*.S); do sed -i -E 's/^ *\.set *([[:alnum:]_]+), */\1 set /' $f; done

# Replace .rept/.endr directives with IAR rept/endr directives

for f in $(find src -name \*.S); do sed -i -E 's/^ *\.(rept|endr)\>/ \1/' $f; done

# Replace .if/.ifgt/.elseif/.else/.endif directives with IAR if/elseif/else/endif directives

git apply << EOF
--- a/src/rp2_common/pico_double/double_sci_m33.S
+++ b/src/rp2_common/pico_double/double_sci_m33.S
@@ -38,13 +38,13 @@ movlong macro rx, n
 hardabi_wrapper_func macro type, func, argn
  __CONCAT(type,_func) func
 #if defined(__ARM_PCS_VFP)
-.ifgt argn - 0
+.if argn > 0
  vmov r0,r1,d0
 .endif
-.ifgt argn - 1
+.if argn > 1
  vmov r2,r3,d1
 .endif
-.ifgt argn - 2
+.if argn > 2
 .error "Unsupported argn: argn"
 .endif
  push {lr}
EOF

for f in $(find src -name \*.S); do sed -i -E 's/^ *\.(if|elseif|else|endif)\>/ \1/' $f; done

# Replace .ltorg directive with IAR ltorg directive

for f in $(find src -name \*.S); do sed -i -E 's/^ *\.ltorg\>/ ltorg/' $f; done

# Replace .extern directive with IAR extern directive

for f in $(find src -name \*.S); do sed -i -E 's/^ *\.extern\>/ extern/' $f; done

# Remove .org directive
 #
 # IAR doesn't seem to have an equivalent of this. Unclear if it's actually needed?

for f in $(find src -name \*.S); do sed -i -E '/^ *\.org\>/d' $f; done

# Use 'r12' instead of 'ip' because the latter isn't recognised by IAR

for f in $(find src -name \*.S); do sed -i -E 's/\<ip\>/r12/g' $f; done

# Explicitly include all registers in asrs/lsls/lsrs instructions
#
# The Armv7-AR and Armv8-M ARMs permit the first register to be inferred in
# these instructions, which is presumably why GAS allows it. However, the
# Armv6-M ARM does not, and the IAR assembler follows these stricter rules
# (though only for 16-bit encodings, i.e. those that use r0-r7). We also
# need to match usage within macros where the register names can be any
# symbol and we can't assume they're in the range r0-r7.

for f in $(find src -name \*.S); do gawk '
{
  if (!match($0, /^[/ ]+(asrs|lsls|lsrs) +r(8|9|10|11|12|14),/) && \
       match($0, /^([/ ]+)(asrs|lsls|lsrs)( +)([[:alnum:]_]+, *)(r[0-7]|#[[:alnum:]_]+)( *)(\/\/.*)?$/, m)) {
    if (length(m[6]) > 0) {
      old_comment_col = length(m[1] m[2] m[3] m[4] m[5] m[6])
      new_comment_col = length(m[1] m[2] m[3] m[4] m[4] m[5])
      if (new_comment_col + 1 <= old_comment_col)
        print m[1] m[2] m[3] m[4] m[4] m[5] sprintf("%*s", old_comment_col - new_comment_col, "") m[7]
      else
        print m[1] m[2] m[3] m[4] m[4] m[5] "\n" sprintf("%*s", old_comment_col, "") m[7]
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

for f in $(find src -name \*.S); do sed -i -E '
s/( shimmable_table_tail_call [[:alnum:]_]+) /\1, /;
s/( saving_func [[:alnum:]_]+)( +[[:alnum:]_]+)$/\1,\2/;
s/( saving_func [[:alnum:]_]+)( +[[:alnum:]_]+)( +[[:alnum:]_]+)$/\1,\2,\3/;
s/( saving_func [[:alnum:]_]+)( +[[:alnum:]_]+)( +[[:alnum:]_]+)( +[[:alnum:]_]+)$/\1,\2,\3,\4/;
s/( hardabi_wrapper_func [[:alnum:]_]+)( +[[:alnum:]_]+)( +[[:alnum:]_]+)$/\1,\2,\3/;
s/( if_irq_word [[:alnum:]_]+)( +[[:alnum:]_]+)$/\1,\2/;
s/( if_irq_decl [[:alnum:]_]+)( +[[:alnum:]_]+)$/\1,\2/;
' $f; done

# IAR doesn't support variadic macros
#
# This was only used in macro "saving_func", albeit duplicated across two
# files. Split into three macros each depending on number of arguments.

git apply << EOF
--- a/src/rp2_common/pico_double/double_aeabi_dcp.S
+++ b/src/rp2_common/pico_double/double_aeabi_dcp.S
@@ -30,7 +30,7 @@ double_wrapper_section macro func

 // ============== STATE SAVE AND RESTORE ===============

-saving_func macro type, func, opt_label1='-', opt_label2='-'
+saving_func macro type, func
   // Note we are usually 32-bit aligned already at this point, as most of the
   // function bodies contain exactly two 16-bit instructions: bmi and bx lr.
   // We want the PCMP word-aligned.
@@ -42,12 +42,47 @@ saving_func macro type, func, opt_label1='-', opt_label2='-'
   push {lr}              // 16-bit instruction
   bl generic_save_state  // 32-bit instruction
   b 1f                   // 16-bit instruction
-.ifnc opt_label1,'-'
- regular_func opt_label1
- endif
-.ifnc opt_label2,'-'
- regular_func opt_label2
- endif
+  // This is the actual entry point:
+  __CONCAT(type,_func) func
+  PCMP apsr_nzcv
+  bmi 1b
+1:
+ endm
+
+saving_func2 macro type, func, label1
+  // Note we are usually 32-bit aligned already at this point, as most of the
+  // function bodies contain exactly two 16-bit instructions: bmi and bx lr.
+  // We want the PCMP word-aligned.
+ alignrom 2
+  // When the engaged flag is set, branch back here to invoke save routine and
+  // hook lr with the restore routine, then fall back through to the entry
+  // point. The engaged flag will be clear when checked a second time.
+1:
+  push {lr}              // 16-bit instruction
+  bl generic_save_state  // 32-bit instruction
+  b 1f                   // 16-bit instruction
+ regular_func label1
+  // This is the actual entry point:
+  __CONCAT(type,_func) func
+  PCMP apsr_nzcv
+  bmi 1b
+1:
+ endm
+
+saving_func3 macro type, func, label1, label2
+  // Note we are usually 32-bit aligned already at this point, as most of the
+  // function bodies contain exactly two 16-bit instructions: bmi and bx lr.
+  // We want the PCMP word-aligned.
+ alignrom 2
+  // When the engaged flag is set, branch back here to invoke save routine and
+  // hook lr with the restore routine, then fall back through to the entry
+  // point. The engaged flag will be clear when checked a second time.
+1:
+  push {lr}              // 16-bit instruction
+  bl generic_save_state  // 32-bit instruction
+  b 1f                   // 16-bit instruction
+ regular_func label1
+ regular_func label2
   // This is the actual entry point:
   __CONCAT(type,_func) func
   PCMP apsr_nzcv
--- a/src/rp2_common/pico_float/float_aeabi_dcp.S
+++ b/src/rp2_common/pico_float/float_aeabi_dcp.S
@@ -32,7 +32,7 @@ float_wrapper_section macro func

 // ============== STATE SAVE AND RESTORE ===============

-saving_func macro type, func, opt_label1='-', opt_label2='-'
+saving_func macro type, func
   // Note we are usually 32-bit aligned already at this point, as most of the
   // function bodies contain exactly two 16-bit instructions: bmi and bx lr.
   // We want the PCMP word-aligned.
@@ -44,12 +44,47 @@ saving_func macro type, func, opt_label1='-', opt_label2='-'
   push {lr}              // 16-bit instruction
   bl generic_save_state  // 32-bit instruction
   b 1f                   // 16-bit instruction
-.ifnc opt_label1,'-'
- regular_func opt_label1
- endif
-.ifnc opt_label2,'-'
- regular_func opt_label2
- endif
+  // This is the actual entry point:
+  __CONCAT(type,_func) func
+  PCMP apsr_nzcv
+  bmi 1b
+1:
+ endm
+
+saving_func2 macro type, func, label1
+  // Note we are usually 32-bit aligned already at this point, as most of the
+  // function bodies contain exactly two 16-bit instructions: bmi and bx lr.
+  // We want the PCMP word-aligned.
+ alignrom 2
+  // When the engaged flag is set, branch back here to invoke save routine and
+  // hook lr with the restore routine, then fall back through to the entry
+  // point. The engaged flag will be clear when checked a second time.
+1:
+  push {lr}              // 16-bit instruction
+  bl generic_save_state  // 32-bit instruction
+  b 1f                   // 16-bit instruction
+ regular_func label1
+  // This is the actual entry point:
+  __CONCAT(type,_func) func
+  PCMP apsr_nzcv
+  bmi 1b
+1:
+ endm
+
+saving_func3 macro type, func, label1, label2
+  // Note we are usually 32-bit aligned already at this point, as most of the
+  // function bodies contain exactly two 16-bit instructions: bmi and bx lr.
+  // We want the PCMP word-aligned.
+ alignrom 2
+  // When the engaged flag is set, branch back here to invoke save routine and
+  // hook lr with the restore routine, then fall back through to the entry
+  // point. The engaged flag will be clear when checked a second time.
+1:
+  push {lr}              // 16-bit instruction
+  bl generic_save_state  // 32-bit instruction
+  b 1f                   // 16-bit instruction
+ regular_func label1
+ regular_func label2
   // This is the actual entry point:
   __CONCAT(type,_func) func
   PCMP apsr_nzcv
EOF

for f in $(find src -name \*.S); do sed -i -E '
s/( saving_func)( [[:alnum:]_]+, +[[:alnum:]_]+, +[[:alnum:]_]+)$/\12\2/;
s/( saving_func)( [[:alnum:]_]+, +[[:alnum:]_]+, +[[:alnum:]_]+, +[[:alnum:]_]+)$/\13\2/;
' $f; done

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
--- a/src/rp2040/pico_platform/include/pico/asm_helper.S
+++ b/src/rp2040/pico_platform/include/pico/asm_helper.S
@@ -17,6 +17,7 @@
 // setup to the pico_default_asm macro for inline assembly in C code.
 .macro pico_default_asm_setup
 .text
+.altmacro
 .syntax unified
 .cpu cortex-m0plus
 .thumb
@@ -142,6 +143,18 @@ __pre_init                      macro           func, priority_string
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
--- a/src/rp2350/pico_platform/include/pico/asm_helper.S
+++ b/src/rp2350/pico_platform/include/pico/asm_helper.S
@@ -25,6 +25,7 @@
 // setup to the pico_default_asm macro for inline assembly in C code.
 .macro pico_default_asm_setup
 .text
+.altmacro
 #ifndef __riscv
 .syntax unified
 .cpu cortex-m33
@@ -163,6 +164,18 @@ __pre_init                      macro           func, priority_string
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
--- a/src/rp2_common/pico_divider/divider_hardware.S
+++ b/src/rp2_common/pico_divider/divider_hardware.S
@@ -46,10 +46,22 @@ div_section macro name

 // wait 8-n cycles for the hardware divider
 wait_div macro n
- rept (8-n) / 2
-    b 9f
-9:
- endr
+ if (8-n >= 8)
+ b l\@_1
+ endif
+l\@_1:
+ if (8-n >= 6)
+ b l\@_2
+ endif
+l\@_2:
+ if (8-n >= 4)
+ b l\@_3
+ endif
+l\@_3:
+ if (8-n >= 2)
+ b l\@_4
+ endif
+l\@_4:
  if (8-n) % 2
     nop
  endif
--- a/src/rp2_common/pico_double/double_aeabi_dcp.S
+++ b/src/rp2_common/pico_double/double_aeabi_dcp.S
@@ -38,15 +38,15 @@ saving_func macro type, func
   // When the engaged flag is set, branch back here to invoke save routine and
   // hook lr with the restore routine, then fall back through to the entry
   // point. The engaged flag will be clear when checked a second time.
-1:
+l\@_1:
   push {lr}              // 16-bit instruction
   bl generic_save_state  // 32-bit instruction
-  b 1f                   // 16-bit instruction
+  b l\@_2                // 16-bit instruction
   // This is the actual entry point:
   __CONCAT(type,_func) func
   PCMP apsr_nzcv
-  bmi 1b
-1:
+  bmi l\@_1
+l\@_2:
  endm

 saving_func2 macro type, func, label1
@@ -57,16 +57,16 @@ saving_func2 macro type, func, label1
   // When the engaged flag is set, branch back here to invoke save routine and
   // hook lr with the restore routine, then fall back through to the entry
   // point. The engaged flag will be clear when checked a second time.
-1:
+l\@_1:
   push {lr}              // 16-bit instruction
   bl generic_save_state  // 32-bit instruction
-  b 1f                   // 16-bit instruction
+  b l\@_2                // 16-bit instruction
  regular_func label1
   // This is the actual entry point:
   __CONCAT(type,_func) func
   PCMP apsr_nzcv
-  bmi 1b
-1:
+  bmi l\@_1
+l\@_2:
  endm

 saving_func3 macro type, func, label1, label2
@@ -77,17 +77,17 @@ saving_func3 macro type, func, label1, label2
   // When the engaged flag is set, branch back here to invoke save routine and
   // hook lr with the restore routine, then fall back through to the entry
   // point. The engaged flag will be clear when checked a second time.
-1:
+l\@_1:
   push {lr}              // 16-bit instruction
   bl generic_save_state  // 32-bit instruction
-  b 1f                   // 16-bit instruction
+  b l\@_2                // 16-bit instruction
  regular_func label1
  regular_func label2
   // This is the actual entry point:
   __CONCAT(type,_func) func
   PCMP apsr_nzcv
-  bmi 1b
-1:
+  bmi l\@_1
+l\@_2:
  endm

 saving_func_return macro
--- a/src/rp2_common/pico_float/float_aeabi_dcp.S
+++ b/src/rp2_common/pico_float/float_aeabi_dcp.S
@@ -40,15 +40,15 @@ saving_func macro type, func
   // When the engaged flag is set, branch back here to invoke save routine and
   // hook lr with the restore routine, then fall back through to the entry
   // point. The engaged flag will be clear when checked a second time.
-1:
+l\@_1:
   push {lr}              // 16-bit instruction
   bl generic_save_state  // 32-bit instruction
-  b 1f                   // 16-bit instruction
+  b l\@_2                // 16-bit instruction
   // This is the actual entry point:
   __CONCAT(type,_func) func
   PCMP apsr_nzcv
-  bmi 1b
-1:
+  bmi l\@_1
+l\@_2:
  endm

 saving_func2 macro type, func, label1
@@ -59,16 +59,16 @@ saving_func2 macro type, func, label1
   // When the engaged flag is set, branch back here to invoke save routine and
   // hook lr with the restore routine, then fall back through to the entry
   // point. The engaged flag will be clear when checked a second time.
-1:
+l\@_1:
   push {lr}              // 16-bit instruction
   bl generic_save_state  // 32-bit instruction
-  b 1f                   // 16-bit instruction
+  b l\@_2                // 16-bit instruction
  regular_func label1
   // This is the actual entry point:
   __CONCAT(type,_func) func
   PCMP apsr_nzcv
-  bmi 1b
-1:
+  bmi l\@_1
+l\@_2:
  endm

 saving_func3 macro type, func, label1, label2
@@ -79,17 +79,17 @@ saving_func3 macro type, func, label1, label2
   // When the engaged flag is set, branch back here to invoke save routine and
   // hook lr with the restore routine, then fall back through to the entry
   // point. The engaged flag will be clear when checked a second time.
-1:
+l\@_1:
   push {lr}              // 16-bit instruction
   bl generic_save_state  // 32-bit instruction
-  b 1f                   // 16-bit instruction
+  b l\@_2                // 16-bit instruction
  regular_func label1
  regular_func label2
   // This is the actual entry point:
   __CONCAT(type,_func) func
   PCMP apsr_nzcv
-  bmi 1b
-1:
+  bmi l\@_1
+l\@_2:
  endm

 saving_func_return macro
EOF

for f in $(find src -name \*.S); do gawk '
function test_macro_introducer(row) {
  if (match(row, /^([[:alnum:]_]+) +macro /, m)) {
    current_macro = m[1]
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
# This is because numeric labels are not supported by IAR. Labels are named
# monotonically increasing through each source file, with prefix "label_".

git apply << EOF
--- a/src/rp2_common/hardware_irq/irq_handler_chain.S
+++ b/src/rp2_common/hardware_irq/irq_handler_chain.S
@@ -56,7 +56,7 @@ next_slot_number set 1
  endif
     // next is the 8 bit unsigned priority
     dc8 0x00
-1:
+
     // and finally the handler function pointer for Arm:
 #ifndef __riscv
     dc32 0x0000000
EOF

for f in $(find src -name \*.S); do gawk '
# Skip RISC-V-only files
ARGV[1] ~ /riscv\.S/ {
  print
  next
}

# Maintain a stack of "suspended" flags which suppresses processing
# within a #ifdef __riscv or the #else clause of #ifndef __riscv
BEGIN {
  depth = 0
  suspended[depth] = 0
  else_suspended[depth] = 0
}

function test_riscv(row) {
  if (match(row, /^ *#ifdef +__riscv$/)) {
    ++depth
    suspended[depth] = 1
    else_suspended[depth] = suspended[depth-1]
  } else if (match(row, /^ *#ifndef +__riscv$/)) {
    ++depth
    suspended[depth] = suspended[depth-1]
    else_suspended[depth] = 1
  } else if (match(row, /^ *#if/)) {
    ++depth
    suspended[depth] = suspended[depth-1]
    else_suspended[depth] = suspended[depth-1]
  } else if (match(row, /^ *#else$/)) {
    suspended[depth] = else_suspended[depth]
  } else if (match(row, /^ *#endif$/)) {
    --depth
  }
}

function lookup(line, old, dir) {
  if (dir == "f") {
    for (new = 1; new <= max_label; ++new) {
      if (old_label[new] == old && label_line[new] > line) {
        result = new
        break
      }
    }
    if (new > max_label) {
      print "Can'\''t find label " old " forward from line " ARGV[1] ":" line > "/dev/stderr"
      exit 1
    }
  } else {
    for (new = max_label; new >= 1 ; --new) {
      if (old_label[new] == old && label_line[new] <= line) {
        result = new
        break
      }
    }
    if (new == 0) {
      print "Can'\''t find label " old " backward from line " ARGV[1] ":" line > "/dev/stderr"
      exit 1
    }
  }
  result = "label_" result
  return result
}

# Build database of labels on first pass, no output yet since may include forward references
{
  next_i = ++i
  test_riscv($0)
  if (suspended[depth]) {
    row[i] = $0
    i = next_i
    next
  }
  if (match($0, /^( *[0-9]+):( +[^\/ ].*)$/, m)) {
    # If label is on same line as instruction then add line break as new label is probably too long to fit in margin
    row[i] = m[1] ":"
    next_i = i + 1
    row[next_i] = sprintf("%*s", length(m[1]), "") " " m[2]
  } else {
    row[i] = $0
  }
  if (match(row[i], /^ *([0-9]+):( +\/\/.*)?$/, m)) {
    ++max_label
    label_line[max_label] = i
    old_label[max_label] = m[1]
  }
  i = next_i
}
  
# Now output the whole file whilst performing substitutions
END {
  for (j = 1; j <= i; ++j) {
    test_riscv(row[j])
    if (suspended[depth]) {
      print row[j]
      continue
    }
    if (match(row[j], /^( +)b(l?)(|cc|cs|eq|ge|gt|hi|hs|le|lo|ls|lt|mi|ne|pl|vc|vs)( +)([0-9]+)(b|f)( *)(\/\/.*)?$/, m)) {
      if (length(m[7]) > 0) {
        old_comment_col = length(m[1] "b" m[2] m[3] m[4] m[5] m[6] m[7])
        new_comment_col = length(m[1] "b" m[2] m[3] m[4] lookup(j, m[5], m[6]))
        if (new_comment_col + 1 <= old_comment_col)
          print m[1] "b" m[2] m[3] m[4] lookup(j, m[5], m[6]) sprintf("%*s", old_comment_col - new_comment_col, "") m[8]
        else
          print m[1] "b" m[2] m[3] m[4] lookup(j, m[5], m[6]) "\n" sprintf("%*s", old_comment_col, "") m[8]
      } else {
        print m[1] "b" m[2] m[3] m[4] lookup(j, m[5], m[6])
      }
    } else if (match(row[j], /^( +cbn?z +r[0-7], *)([0-9]+)(b|f)( *)(\/\/.*)?$/, m)) {
      if (length(m[4]) > 0) {
        old_comment_col = length(m[1] m[2] m[3] m[4])
        new_comment_col = length(m[1] lookup(j, m[2], m[3]))
        if (new_comment_col + 1 <= old_comment_col)
          print m[1] lookup(j, m[2], m[3]) sprintf("%*s", old_comment_col - new_comment_col, "") m[5]
        else
          print m[1] lookup(j, m[2], m[3])  "\n" sprintf("%*s", old_comment_col, "") m[5]
      } else {
        print m[1] lookup(j, m[2], m[3])
      }
    } else if (match(row[j], /^( *)([0-9]+):( *)(\/\/.*)?$/, m)) {
      if (length(m[4]) > 0) {
        old_comment_col = length(m[1] m[2] ":" m[3])
        new_comment_col = length(lookup(j, m[2], "") ":")
        if (new_comment_col + 1 <= old_comment_col)
          print lookup(j, m[2], "") ":" sprintf("%*s", old_comment_col - new_comment_col, "") m[4]
        else
          print lookup(j, m[2], "") ":\n" sprintf("%*s", old_comment_col, "") m[4]
      } else {
        print lookup(j, m[2], "") ":"
      }
    } else {
      print row[j]
    }
  }
}
' $f > $f.tmp && mv $f.tmp $f; done

# Change to use UAL syntax for movs in second-stage bootloaders
sed -i -E 's/^( *)mov( +r[0-7], *#[^ ]+)( |$)/\1movs\2/' src/*/boot_stage2/*.S

# Remove stray .altmacro directive

sed -i -E '/^ *\.altmacro\>/d' src/rp2_common/pico_crt0/crt0.S






#git diff reference

