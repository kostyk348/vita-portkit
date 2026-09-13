# vita-portkit — инструменты переноса ПК-игр на PS Vita

Цель: универсальный конвейер **x86_64 → ARM32 (PS Vita)** + переиспользуемая обвязка.

## Что уже проверено (факты)

| Слой | Статус | Доказательство |
|---|---|---|
| x86 → IR → SSA | ✅ работает | `sdre` лифтит реальные функции |
| IR → ARM32 emit | ✅ работает | `sdre --target arm` даёт настоящий ARM asm |
| ARM-ассемблер без кросс-тулчейна | ✅ работает | `clang --target=armv7-linux-gnueabihf -fuse-ld=lld` |
| Исполнение/верификация ARM | ✅ работает | `qemu-arm` (exit=42 на тесте) |
| **Семантика трансляции** | ✅ для простых функций | `mul5` → `lsl r7,r5,#2; add r8,r7,r4` = x*4+x = x*5 |
| SIMD (SSE → NEON) | ❌ нет | `movdqu/paddd` → комментарии |
| `lea` с масштабом | ❌ нет | `lea_indexed` opaque (`sdre/src/adapter/x86.rs:339`) |
| Флаги (CF/OF/SF/ZF) | ⚠️ частично | `test/cmp` без точной семантики |
| ABI (аргументы/возврат/стек) | ⚠️ частично | возврат в r0 есть, входные регистры — виртуальные |
| Рантайм (syscalls, malloc, threads) | ❌ нет | — |
| Платформенный шим (SDL2/GL/audio/input) | ❌ нет | — |
| vitaSDK | ❌ не установлен | `~/vitasdk` = только `vdpm` (нужен toolchain ~1 ГБ) |

## Архитектура (что должно получиться)

```
  [x86_64 ELF] --sdre--> [IR/SSA] --emit_arm--> [ARM32 asm]
        |                                            |
        |                                      [clang/lld]
        v                                            v
   данные/ресурсы                            [ARM32 ELF]
   (ftl.dat -> unpack_pkg)                          |
        |                                     +------+------+
        v                                     |  РАНТАЙМ    |  syscalls -> SceKernel
   [ftl_unpacked/]                            |  malloc     |  threads  -> SceThread
                                              |  fs         |
                                              +-------------+
                                                    |
                                              +-------------+
                                              |  ШИМ (SDL2) |  GL -> GLES2 (SceGxm)
                                              |  audio      |  SceAudio
                                              |  input      |  SceCtrl
                                              +-------------+
                                                    |
                                              [VPK для Vita]
```

## Этапы

**Ф1 — транслятор целых функций.** Довести `sdre`: `lea` со масштабом, точные флаги,
ABI (входные регистры/стек-фрейм/вызовы). Верификация: `verify_pipeline.sh` +
сравнение результатов x86 (нативно) и ARM (qemu-arm).

**Ф2 — SIMD.** SSE → NEON (ARMv7 NEON 128-бит): `movdqu/paddd/mulps` → `vld1/vadd/vmul`.

**Ф3 — рантайм.** Linux syscalls (`mmap/brk/open/read/clock_gettime`), malloc,
pthread → SceThread, файлы → наш `unpack_pkg` (данные игры читаются прямо из архива).

**Ф4 — платформенный шим.** `SDL2 + OpenGL` → `SDL2(vita) + GLES2 + SceAudio + SceCtrl`.
Переиспользуется всеми портами (это и есть "универсальная обвязка").

**Ф5 — пилот.** Сначала 32-битная цель (у 32-бит x86 указатели 4 байта → нет проблемы
64→32), затем более крупные.

## Главные риски (честно)

1. **64 → 32 бита.** FTL Linux — `x86_64` (указатели 8 байт), Vita — ARMv7 (4 байта).
   Варианты: (а) брать 32-битную сборку цели (у FTL есть Windows x86 `FTL.exe`);
   (б) эмулировать 64-бит (×2 медленнее). Рекомендация: **32-битные цели**.
2. **Производительность.** Cortex-A9 @444 МГц; транслированный код ×2–4 медленнее.
   2D-игры (FTL) — шанс есть, 3D — вряд ли.
3. **Прецеденты на Vita — source-порты**, не бинарная трансляция: re3/reVC (GTA),
   Sonic Mania, Ship of Harkinian. Т.е. реверс → реимплементация на C → нативная сборка.
   Бинарная трансляция x86→Vita — territory без готовых решений (это наш research).

## Быстрый старт

```bash
./verify_pipeline.sh test.c my_func     # x86 -> ARM + qemu-arm
```
