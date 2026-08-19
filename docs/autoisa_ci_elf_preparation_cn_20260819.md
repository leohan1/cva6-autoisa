# AutoISA 最小 ELF 准备记录

日期：2026-08-19

## 1. 工具链

- 发行版：xPack GNU RISC-V Embedded GCC 15.2.0-1（Windows x64）
- 编译器：`riscv-none-elf-gcc 15.2.0`
- 官方归档：`xpack-riscv-none-elf-gcc-15.2.0-1-win32-x64.zip`
- SHA-256：`85ef714dacd273b1dadf4af4892774520ac01915bfa6da816a56e7e41591e09e`
- 本机位置：`tools/xpack-riscv-none-elf-gcc-15.2.0-1/`

`tools/` 已由仓库 `.gitignore` 排除，工具链二进制不会进入 Git。其他机器可以
通过 `--toolchain`、`AUTOISA_RISCV_TOOLCHAIN`、同名本地 `tools/` 目录或 `PATH`
提供兼容工具链。

## 2. 工程自检入口

```powershell
python ci/autoisa/check_riscv_toolchain.py
```

自检会执行以下步骤：

1. 查找完整的 GCC、objcopy、objdump 和 readelf；
2. 用 `rv32imac_zicsr/ilp32`、无标准库模式编译并链接最小 D0 程序；
3. 验证输出是 ELF32 RISC-V；
4. 验证二进制包含 D0 指令字 `0x007302db`；
5. 保存 ELF、binary 和反汇编到被忽略的 `ci/autoisa/build/software/`。

## 3. 最小程序

`tests/autoisa/software/minimal_d0.S` 使用生成的 Layout V2 汇编常量，编码：

```text
D0 / L_2R1W_GPR32: x5 = x6 + x7
x6 = 11, x7 = 31, expected x5 = 42
instruction word = 0x007302db
```

程序提供 `tohost`：结果正确写入 1，失败写入 3。当前准备门只验证软件产物；
下一步把该 ELF 装入 Ariane testbench，才能验证真实取指、CV-X-IF、退休和写回。

## 4. 当日结果

```text
PASS: riscv-none-elf-gcc 15.2.0
PASS: rv32imac_zicsr/ilp32 compile and link
PASS: ELF32 RISC-V header
PASS: D0 encoding 0x007302db present
```
