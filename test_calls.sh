#!/usr/bin/env bash
# Тест вызовов функций: x86 -> ARM (пофункционально) -> qemu-arm.
set -uo pipefail
SRC="${1:-tests/calls.c}"
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
PASS=0; FAIL=0
run() { # $1=arg $2=expected
    ./translate.sh "$SRC" > "$W/t.s" 2>/dev/null
    { echo ".syntax unified"; echo ".text"; echo ".global _start"; echo "_start:";
      echo "    mov r0, #$1"; echo "    bl caller"; echo "    mov r7, #1"; echo "    svc #0"; } > "$W/f.s"
    cat "$W/t.s" >> "$W/f.s"
    if clang --target=armv7-linux-gnueabihf -fuse-ld=lld -nostdlib -static -o "$W/f.arm" "$W/f.s" 2>/dev/null; then
        qemu-arm "$W/f.arm"; RC=$?
        if [ "$RC" = "$2" ]; then echo "  ✅ caller($1) = $2"; PASS=$((PASS+1))
        else echo "  ❌ caller($1) = $RC, ожидалось $2"; FAIL=$((FAIL+1)); fi
    else echo "  ❌ не собирается"; FAIL=$((FAIL+1)); fi
}
# caller(a) = helper(a) + helper(a+1) = (7a+1) + (7(a+1)+1) = 14a+9
run 1 23
run 3 51
run 5 79
echo "вызовы: $PASS ок, $FAIL провал"
[ "$FAIL" -eq 0 ]
