#!/usr/bin/env python3
"""
修改 Android boot.img v0 的 cmdline 字段 (offset 0x40, 512 bytes).
用途: 给 pmOS boot.img 添加调试参数 (earlycon/console/loglevel/pmos.debug-shell).

用法:
  python3 modify-bootimg-cmdline.py <input.img> <output.img> "<new cmdline>"

注意:
- 仅修改 cmdline 字段, kernel/ramdisk/second 数据完全不变.
- 不重新计算 id 字段 (bootloader 不校验 id).
- 新 cmdline 会被 0x00 padding 到 512 bytes.
"""
import sys
import struct

def main():
    if len(sys.argv) != 4:
        print(f"用法: {sys.argv[0]} <input.img> <output.img> \"<new cmdline>\"", file=sys.stderr)
        sys.exit(1)

    input_path = sys.argv[1]
    output_path = sys.argv[2]
    new_cmdline = sys.argv[3].encode("utf-8")

    if len(new_cmdline) >= 512:
        print(f"[ERROR] 新 cmdline 太长: {len(new_cmdline)} bytes (max 511)", file=sys.stderr)
        sys.exit(1)

    with open(input_path, "rb") as f:
        data = bytearray(f.read())

    # 验证 magic
    magic = bytes(data[0:8])
    if magic != b"ANDROID!":
        print(f"[ERROR] 不是 Android boot.img (magic={magic!r})", file=sys.stderr)
        sys.exit(1)

    # 读取原 cmdline
    orig_cmdline = bytes(data[0x40:0x40+512]).rstrip(b"\x00").decode("utf-8", errors="replace")
    print(f"原 cmdline ({len(orig_cmdline)} bytes): {orig_cmdline}", file=sys.stderr)

    # 读取 header_version
    header_version = struct.unpack_from("<I", data, 0x28)[0]
    print(f"header_version: {header_version}", file=sys.stderr)
    if header_version != 0:
        print(f"[WARN] header_version={header_version} (脚本只测试过 v0)", file=sys.stderr)

    # 修改 cmdline
    cmdline_padded = new_cmdline + b"\x00" * (512 - len(new_cmdline))
    data[0x40:0x40+512] = cmdline_padded

    print(f"新 cmdline ({len(new_cmdline)} bytes): {new_cmdline.decode()}", file=sys.stderr)

    # 写入
    with open(output_path, "wb") as f:
        f.write(data)

    print(f"已写入: {output_path}", file=sys.stderr)

if __name__ == "__main__":
    main()
