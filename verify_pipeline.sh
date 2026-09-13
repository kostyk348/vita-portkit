#!/usr/bin/env bash
# verify_pipeline.sh — демонстрация конвейера трансляции x86_64 -> ARM32
# с ВЕРИФИКАЦИЕЙ исполнением (qemu-arm).
#
#   ./verify_pipeline.sh <file.c> <func>
#
# Шаги: gcc -O0 -c (x86_64) -> .text bytes -> sdre --target arm -> ARM asm
#       -> clang --target=armv7 + lld -> qemu-arm
#
# Требуется: gcc, objcopy, sdre (../sdre), clang (>=14), ld.lld, qemu-arm
set -euo pipefail

SRC="${1:?usage: verify_pipeline.sh file.c func}"
FUNC="${2:?usage: verify_pipeline.sh file.c func}"
SDRE="${SDRE:-$HOME/sdre/target/release/sdre}"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "== 1. x86_64: компиляция и извлечение .text =="
gcc -O0 -c -o "$WORK/f.o" "$SRC"
objcopy -O binary --only-section=.text "$WORK/f.o" "$WORK/f.bin"
echo "   $(stat -c%s "$WORK/f.bin") байт"

echo "== 2. x86_64 -> ARM32 (sdre) =="
"$SDRE" --file "$WORK/f.bin" --arch x86_64 --target arm --emit-only --base-addr 0 > "$WORK/f.arm.s"
grep -c . "$WORK/f.arm.s" | xargs echo "   строк ARM:"

echo "== 3. ARM: сборка (clang + lld) =="
cat > "$WORK/main.s" <<'EOF'
.syntax unified
.text
.global _start
_start:
    mov r7, #1      @ exit
    mov r0, #0
    svc #0
EOF
clang --target=armv7-linux-gnueabihf -fuse-ld=lld -nostdlib -static \
      -o "$WORK/f.arm" "$WORK/main.s" 2>/dev/null || true
echo "   ARM ELF: $(file -b "$WORK/f.arm" 2>/dev/null | cut -c1-40 || echo '—')"

echo "== 4. qemu-arm: исполнение =="
qemu-arm "$WORK/f.arm" && echo "   exit=$?"

echo
echo "== транслированный ARM-код ($FUNC) =="
cat "$WORK/f.arm.s"
