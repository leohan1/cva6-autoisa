#!/usr/bin/env bash
set -euo pipefail

: "${RISCV:?RISCV must name the toolchain installation directory}"

export PATH="$RISCV/bin:/bin:$PATH"
export LIBRARY_PATH="$RISCV/lib"
export LD_LIBRARY_PATH="$RISCV/lib"
export C_INCLUDE_PATH="$RISCV/include"
export CPLUS_INCLUDE_PATH="$RISCV/include"

TOOLCHAIN_VERSION=13.2.0-2
TOOLCHAIN_ARCHIVE="xpack-riscv-none-elf-gcc-${TOOLCHAIN_VERSION}-linux-x64.tar.gz"
TOOLCHAIN_URL="https://github.com/xpack-dev-tools/riscv-none-elf-gcc-xpack/releases/download/v${TOOLCHAIN_VERSION}/${TOOLCHAIN_ARCHIVE}"
TOOLCHAIN_SHA256=52545afb900200fbf65fe05f7ce7090b8a42c64091f4f5d43cae6bb68ea2434a

mkdir -p "$RISCV"

if [ ! -x "$RISCV/bin/riscv-none-elf-gcc" ]; then
    download_dir="$(mktemp -d)"
    trap 'rm -rf "$download_dir"' EXIT
    archive_path="$download_dir/$TOOLCHAIN_ARCHIVE"

    curl --fail --location \
        --retry 5 --retry-all-errors --retry-delay 5 \
        --connect-timeout 30 \
        --output "$archive_path" \
        "$TOOLCHAIN_URL"
    echo "$TOOLCHAIN_SHA256  $archive_path" | sha256sum --check --strict
    tar -xzf "$archive_path" --strip-components=1 -C "$RISCV"
fi

if [ ! -x "$RISCV/bin/riscv-none-elf-gcc" ]; then
    echo "ERROR: RISC-V toolchain installation is incomplete" >&2
    exit 1
fi

# CVA6's legacy BSPs use both historical prefixes. xPack ships the standard
# riscv-none-elf prefix, so provide compatibility links without duplicating
# the toolchain.
for tool_path in "$RISCV"/bin/riscv-none-elf-*; do
    tool_name="${tool_path##*/riscv-none-elf-}"
    ln -sfn "riscv-none-elf-$tool_name" \
        "$RISCV/bin/riscv32-unknown-elf-$tool_name"
    ln -sfn "riscv-none-elf-$tool_name" \
        "$RISCV/bin/riscv64-unknown-elf-$tool_name"
done

"$RISCV/bin/riscv-none-elf-gcc" --version
