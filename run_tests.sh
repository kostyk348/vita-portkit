#!/usr/bin/env bash
# Регрессионный набор: трансляция x86 -> ARM + проверка в qemu-arm.
# Формат строки: func r0 r1 expected [index]
set -uo pipefail
SRC="tests/funcs.c"
PASS=0; FAIL=0
while read -r FUNC A0 A1 EXPECT IDX R2; do
    [ -z "$FUNC" ] && continue
    OUT=$(./verify_func.sh "$SRC" "$FUNC" "$A0" "$A1" "$EXPECT" "$IDX" "${R2:-}" 2>&1)
    if echo "$OUT" | grep -q "ТРАНСЛЯЦИЯ ВЕРНА"; then
        echo "  ✅ $FUNC($A0,$A1) = $EXPECT"; PASS=$((PASS+1))
    else
        echo "  ❌ $FUNC($A0,$A1) ожидалось $EXPECT"; echo "$OUT" | grep -E "exit=" | tail -1; FAIL=$((FAIL+1))
    fi
done <<'CASES'
add3 5 7 15 0
mul5 9 0 45 1
f3 1 2 123 2 3
sub_mul 6 3 15 3
CASES
echo "итого: $PASS ок, $FAIL провал"
[ "$FAIL" -eq 0 ]
