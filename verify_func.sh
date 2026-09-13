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

# первая функция из вывода sdre (до пустой строки) + обёртка
python3 - "$W" "$A0" "$A1" "$IDX" "$R2" <<'PY'
import sys, os
w, a0, a1, idx, r2 = sys.argv[1], sys.argv[2], sys.argv[3], int(sys.argv[4]), sys.argv[5]
chunks = [c for c in open(os.path.join(w,'t.s')).read().split('\n\n') if c.strip()]
body = chunks[idx].split('\n')
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
