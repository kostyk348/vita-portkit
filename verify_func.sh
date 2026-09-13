#!/usr/bin/env bash
# verify_func.sh — ВЕРИФИКАЦИЯ трансляции функции: x86_64 -> ARM32 -> исполнение.
#   ./verify_func.sh <file.c> <func> <r0> <r1> <expected_exit> [func_index] [r2]
# Компилирует C для x86_64 (-O0), транслирует в ARM (sdre), заворачивает в harness
# (r0/r1 = аргументы), собирает clang+lld, запускает qemu-arm и сверяет exit code.
set -euo pipefail
SRC="${1:?usage: verify_func.sh f.c func r0 r1 expected}"
FUNC="${2:?}"; A0="${3:?}"; A1="${4:?}"; EXPECT="${5:?}"; IDX="${6:-0}"; R2="${7:-}"
SDRE="${SDRE:-$HOME/sdre/target/release/sdre}"
W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT

gcc -O1 -c -o "$W/f.o" "$SRC"
objcopy -O binary --only-section=.text "$W/f.o" "$W/f.bin"
"$SDRE" --file "$W/f.bin" --arch x86_64 --target arm --emit-only --base-addr 0 > "$W/t.s"
# адрес целевой функции и следующей (границы в выводе)
nm -S --defined-only "$W/f.o" | awk '$3=="T"||$3=="t" {print $1, $4}' | sort > "$W/fn.txt"

# первая функция из вывода sdre (до пустой строки) + обёртка
python3 - "$W" "$A0" "$A1" "$IDX" "$R2" "$FUNC" <<'PY'
import sys, os, re
w, a0, a1, idx, r2, func = sys.argv[1], sys.argv[2], sys.argv[3], int(sys.argv[4]), sys.argv[5], sys.argv[6]
asm = open(os.path.join(w,'t.s')).read()
# границы функций по меткам .L_<addr> (адреса из nm)
fns = []
for line in open(os.path.join(w,'fn.txt')):
    p = line.split()
    if len(p) >= 2:
        fns.append((int(p[0], 16), p[1]))
fns.sort()
# выбрать функцию: по имени, иначе по индексу
if any(n == func for _, n in fns):
    fns_idx = [i for i, (_, n) in enumerate(fns) if n == func][0]
else:
    fns_idx = idx
addr = fns[fns_idx][0]
next_addr = fns[fns_idx+1][0] if fns_idx+1 < len(fns) else None
lines = asm.split('\n')
start = None
for i, l in enumerate(lines):
    if re.match(rf'^\.L_{addr:x}:$', l):
        start = i; break
if start is None:
    body = [l for l in lines if l.strip()][:12]
else:
    end = len(lines)
    if next_addr is not None:
        for j in range(start+1, len(lines)):
            if re.match(rf'^\.L_{next_addr:x}:$', lines[j]):
                end = j; break
    body = lines[start:end]
# ABI-обёртка: callee-saved + lr, возврат через pop {pc} (делается здесь,
# т.к. sdre эмитит по регионам и не знает границ функции)
if any(('bl ' in l) or ('push {' in l) for l in body):
    body = [l for l in body if 'bx lr' not in l]
    body = ['    push {r4-r10, lr}'] + body + ['    pop {r4-r10, pc}']
r2line = f"mov r2, #{r2}" if r2 else ""
open(os.path.join(w,'h.s'),'w').write(f""".syntax unified
.text
.global _start
_start:
    mov r0, #{a0}
    mov r1, #{a1}
    {r2line}
    bl fn_t
    mov r7, #1
    svc #0
fn_t:
""" + "\n".join(body) + "\n")
PY
clang --target=armv7-linux-gnueabihf -fuse-ld=lld -nostdlib -static -o "$W/h.arm" "$W/h.s"
set +e
qemu-arm "$W/h.arm"; RC=$?
set -e
echo "--- транслированный ARM ($FUNC) ---"; cat "$W/t.s"
MASKED=$((EXPECT & 255))
[ "$EXPECT" -gt 255 ] && echo "(exit-код 8-битный: $EXPECT & 255 = $MASKED)"
echo "exit=$RC, ожидалось $MASKED"
if [ "$RC" = "$MASKED" ]; then echo "✅ ТРАНСЛЯЦИЯ ВЕРНА"; else echo "❌ РАСХОЖДЕНИЕ"; exit 1; fi
