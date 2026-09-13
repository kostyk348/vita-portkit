#!/usr/bin/env bash
# Регрессия: пофункциональная трансляция x86 -> ARM + проверка в qemu-arm.
# Формат строки: func r0 r1 expected [r2]
set -uo pipefail
SRC="tests/funcs.c"
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
./translate.sh "$SRC" > "$W/all.s" 2>/dev/null
PASS=0; FAIL=0
run_one() { # func a0 a1 expected [r2]
    local FN="$1" A0="$2" A1="$3" EXP="$4" R2="${5:-}"
    python3 - "$W/all.s" "$FN" > "$W/fn.s" <<'PY'
import sys, re
asm = open(sys.argv[1]).read()
name = sys.argv[2]
lines = asm.split('\n')
start = None
for i, l in enumerate(lines):
    if l.strip() == f"{name}:":
        start = i; break
if start is None:
    sys.exit(1)
end = len(lines)
for j in range(start+1, len(lines)):
    if re.match(r'^[A-Za-z_][A-Za-z0-9_]*:$', lines[j]):
        end = j; break
print('\n'.join(lines[start:end]))
PY
    [ -s "$W/fn.s" ] || { echo "  ❌ $FN: не найдена"; FAIL=$((FAIL+1)); return; }
    { echo ".syntax unified"; echo ".text"; echo ".global _start"; echo "_start:";
      echo "    mov r0, #$A0"; echo "    mov r1, #$A1"; [ -n "$R2" ] && echo "    mov r2, #$R2";
      echo "    bl $FN"; echo "    mov r7, #1"; echo "    svc #0"; } > "$W/t.s"
    cat "$W/fn.s" >> "$W/t.s"
    if clang --target=armv7-linux-gnueabihf -fuse-ld=lld -nostdlib -static -o "$W/t.arm" "$W/t.s" 2>/dev/null; then
        qemu-arm "$W/t.arm"; local RC=$?
        local M=$((EXP & 255))
        if [ "$RC" = "$M" ]; then echo "  ✅ $FN($A0,$A1) = $EXP"; PASS=$((PASS+1))
        else echo "  ❌ $FN($A0,$A1) = $RC, ожидалось $M"; FAIL=$((FAIL+1)); fi
    else echo "  ❌ $FN: не собирается"; FAIL=$((FAIL+1)); fi
}
run_one add3 5 7 15
run_one mul5 9 0 45
run_one f3 1 2 123 3
run_one sub_mul 6 3 15
echo "итого: $PASS ок, $FAIL провал"
[ "$FAIL" -eq 0 ]
