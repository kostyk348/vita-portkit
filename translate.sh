#!/usr/bin/env bash
# translate.sh — x86_64 (.o) -> ARM32: трансляция + резолв вызовов + ABI-обёртка.
#   ./translate.sh <file.c>            # все функции .text
#   ./translate.sh <file.c> <func>     # только функция (секция .text.<func>)
set -euo pipefail

SRC="${1:?usage: translate.sh file.c [func]}"
FUNC="${2:-}"
SDRE="${SDRE:-$HOME/sdre/target/release/sdre}"
W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT

if [ -n "$FUNC" ]; then
    gcc -O1 -fno-inline -ffunction-sections -c -o "$W/f.o" "$SRC"; SEC=".text.$FUNC"
else
    gcc -O1 -fno-inline -c -o "$W/f.o" "$SRC"; SEC=".text"
fi
objcopy -O binary --only-section="$SEC" "$W/f.o" "$W/f.bin"
objdump -dr -M intel --section="$SEC" "$W/f.o" > "$W/dis.txt"
nm -S --defined-only "$W/f.o" | awk '$3=="T"||$3=="t" {print $1, $4}' > "$W/funcs.txt"
timeout 60 "$SDRE" --file "$W/f.bin" --arch x86_64 --target arm --emit-only --base-addr 0 > "$W/t.s"

python3 - "$W/t.s" "$W/dis.txt" "$W/funcs.txt" <<'PY'
import re, sys
asm = open(sys.argv[1]).read()

# 1. карта релокаций: цель bl (reloc_offset+4) -> символ
relocs, cur = {}, None
for line in open(sys.argv[2]):
    m = re.match(r'\s*([0-9a-f]+):\s', line)
    if m: cur = int(m.group(1), 16)
    r = re.search(r'R_X86_64_(?:PLT32|PC32)\s+(\S+)', line)
    if r and cur is not None:
        relocs[f"{cur+4:x}"] = r.group(1).split('-')[0].lstrip('.')

# 2. функции: адрес -> имя (границы для ABI-обёртки и метки вызовов)
funcs = {}
for l in open(sys.argv[3]):
    p = l.split()
    if len(p) >= 2:
        funcs[p[0].lstrip('0') or '0'] = p[1]

# 3. bl .L_<addr> -> bl <symbol>
asm = re.sub(r'bl \.L_([0-9a-f]+)',
             lambda m: f"bl {relocs[m.group(1)]}" if m.group(1) in relocs else f"bl .L_{m.group(1)}",
             asm)

# 4. ABI-обёртка: только настоящие функции (метки из nm)
out, in_fn = [], False
for l in asm.split('\n'):
    if 'bx lr' in l: continue
    m = re.match(r'^\.L_([0-9a-f]+):$', l)
    key = (m.group(1).lstrip('0') or '0') if m else None
    if m and key in funcs:
        if in_fn: out.append('    pop {r4-r10, pc}')
        out.append(f"{funcs[key]}:")
        out.append(l); out.append('    push {r4-r10, lr}'); in_fn = True
    else:
        out.append(l)
if in_fn: out.append('    pop {r4-r10, pc}')
print('\n'.join(out))
PY
