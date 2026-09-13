#!/usr/bin/env bash
# translate.sh — x86_64 (.o) -> ARM32, ПОФУНКЦИОННО.
# Каждая функция лифтится своим графом (reg_map не протекает между функциями),
# вызовы разрешаются через релокации, каждая функция получает ABI-обёртку.
#   ./translate.sh <file.c>
set -euo pipefail

SRC="${1:?usage: translate.sh file.c}"
SDRE="${SDRE:-$HOME/sdre/target/release/sdre}"
W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT

gcc -O1 -fno-inline -ffunction-sections -c -o "$W/f.o" "$SRC"
nm -S --defined-only "$W/f.o" | awk '$3=="T"||$3=="t" {print $1, $4}' | sort > "$W/fn.txt"

echo ".syntax unified"
echo ".text"

while read -r ADDR NAME; do
    SEC=".text.$NAME"
    objcopy -O binary --only-section="$SEC" "$W/f.o" "$W/f.bin" 2>/dev/null || continue
    [ -s "$W/f.bin" ] || continue
    objdump -dr -M intel --section="$SEC" "$W/f.o" > "$W/dis.txt" 2>/dev/null || true
    timeout 60 "$SDRE" --file "$W/f.bin" --arch x86_64 --target arm --emit-only --base-addr 0 > "$W/t.s" 2>/dev/null || continue

    python3 - "$W/t.s" "$W/dis.txt" "$NAME" <<'PY'
import re, sys
asm = open(sys.argv[1]).read()
dis, name = sys.argv[2], sys.argv[3]

# релокации вызовов: цель bl = reloc_offset + 4 -> символ
relocs, cur = {}, None
for line in open(dis):
    m = re.match(r'\s*([0-9a-f]+):\s', line)
    if m: cur = int(m.group(1), 16)
    r = re.search(r'R_X86_64_(?:PLT32|PC32)\s+(\S+)', line)
    if r and cur is not None:
        relocs[f"{cur+4:x}"] = r.group(1).split('-')[0].lstrip('.')

asm = re.sub(r'bl \.L_([0-9a-f]+)',
             lambda m: f"bl {relocs[m.group(1)]}" if m.group(1) in relocs else f"bl .L_{m.group(1)}",
             asm)

lines = [l for l in asm.split('\n') if l.strip()]
# убрать старые метки .L_0: и заменить на имя функции
out = [f"{name}:"]
body = [l for l in lines if not re.match(r'^\.L_[0-9a-f]+:$', l)]
# внутренние метки .L_xx: оставляем (они локальны), но с уникальным префиксом
body = [re.sub(r'^(\.L_[0-9a-f]+:)$', rf'{name}\1', l) if re.match(r'^\.L_[0-9a-f]+:$', l) else l for l in body]
# ABI-обёртка
needs_wrap = any(('bl ' in l) or ('push {' in l) for l in body)
if needs_wrap:
    body = [l for l in body if 'bx lr' not in l]
    out.append('    push {r4-r10, lr}')
    out.extend(body)
    out.append('    pop {r4-r10, pc}')
else:
    out.extend(body)
# внутренние ссылки bl .L_xx -> bl name.L_xx (если остались локальные)
out = [re.sub(r'\bbl \.L_([0-9a-f]+)\b', rf'bl {name}.L_\1', l) if '.L_' in l and 'bl .L_' in l else l for l in out]
print('\n'.join(out))
PY
done < "$W/fn.txt"
