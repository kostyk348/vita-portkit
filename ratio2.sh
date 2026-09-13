#!/bin/bash
# точный коэффициент: одна функция -> её секция -> x86 vs ARM (все строки)
SRC="$1"; FUNC="$2"
W=$(mktemp -d)
gcc -O1 -ffunction-sections -c -o "$W/f.o" "$SRC"
X86=$(objdump -d -M intel "$W/f.o" | awk "/<$FUNC>:/,/^$/" | grep -cE "^\s+[0-9a-f]+:")
objcopy -O binary --only-section=".text.$FUNC" "$W/f.o" "$W/f.bin" 2>/dev/null
B=$(stat -c%s "$W/f.bin")
ARM=$(timeout 20 ~/sdre/target/release/sdre --file "$W/f.bin" --arch x86_64 --target arm --emit-only --base-addr 0 2>/dev/null | grep -cE "^\s+(mov|add|sub|mul|and|orr|cmp|b|ldr|str|ldrb|strb|lsl|lsr|asr|bx|movw|movt|sxtb|sxth|uxtb|uxth|mvn|rsb|eor|tst|ldrsb|ldrh|strh|sdiv|udiv|mla|movs|negs|adc|sbc|clz|rev)")
echo "$FUNC: x86=$X86  ARM=$ARM  (x$(python3 -c "print(f'{$ARM/max($X86,1):.2f}')"))"
rm -rf "$W"
