#!/usr/bin/env python3
"""Оценка стоимости транслированного ARM-кода по таймингам Cortex-A9 (PS Vita).

Модель Cortex-A9 (dual-issue, 8-stage, частичный OoO):
  ALU (add/sub/and/orr/eor/mov/cmp/shift): 1 цикл, до 2 за такт
  MOVW/MOVT: 1 цикл
  LDR/STR (L1 hit): issue 1, latency ~4, throughput ~2 (один LSU)
  LDRB/STRB: то же
  MUL (32x32): latency 3, throughput 1 (одна умножительная труба)
  DIV: ~20+ циклов (дорого)
  B/BL: 1 цикл + штраф промаха предсказания (~8-10)
  BX LR: 1-3
  NEON/VFP (vadd/vld1/vmul): 1-2 цикла

Считаем нижнюю оценку (без промахов кэша) и «реалистичную» (+ промахи/латентности).
"""
import re, sys

ALU = re.compile(r'^\s*(add|sub|and|orr|eor|mov|mvn|cmp|tst|rsb|adc|sbc|lsl|lsr|asr|movw|movt|sxtb|sxth|uxtb|uxth|clz|rev|neg)\b')
LOAD = re.compile(r'^\s*(ldr|ldrb|ldrh|ldrsb|ldrsh|str|strb|strh)\b')
MUL = re.compile(r'^\s*(mul|mla|mls|smull|umull)\b')
DIV = re.compile(r'^\s*(sdiv|udiv)\b')
BRANCH = re.compile(r'^\s*(b|bl|bx|beq|bne|bgt|blt|bge|ble|bhi|bls|bcs|bcc|bmi|bpl|bvs|bvc|cbz|cbnz|tbb|tbh)\b')
NEON = re.compile(r'^\s*(v[a-z0-9]+|q[a-z]+)\b')
LABEL = re.compile(r'^\s*\.L_|^\s*@|^\s*$|^\s*#|^\s*//')

def estimate(path):
    alu = load = mul = div = br = neon = 0
    for line in open(path):
        if LABEL.match(line): continue
        if ALU.match(line): alu += 1
        elif LOAD.match(line): load += 1
        elif MUL.match(line): mul += 1
        elif DIV.match(line): div += 1
        elif BRANCH.match(line): br += 1
        elif NEON.match(line): neon += 1
    # нижняя оценка: ALU dual-issue (2/такт), остальное по 1
    lower = (alu + 1) // 2 + load + mul * 3 + div * 20 + br
    # реалистичная: +латентности загрузок (load-to-use ~2 доп. такта на зависимость)
    realistic = lower + load * 2 + br * 4  # ~50% промахов предсказания
    return dict(alu=alu, load=load, mul=mul, div=div, br=br, neon=neon,
                lower=lower, realistic=realistic)

if __name__ == '__main__':
    for p in sys.argv[1:]:
        e = estimate(p)
        print(f"{p}:")
        print(f"  ALU={e['alu']} LOAD/STR={e['load']} MUL={e['mul']} DIV={e['div']} BRANCH={e['br']} NEON={e['neon']}")
        print(f"  циклов (нижняя оценка): {e['lower']}   реалистично: {e['realistic']}")
