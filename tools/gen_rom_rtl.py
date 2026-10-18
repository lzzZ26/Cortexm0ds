#!/usr/bin/env python3
# gen_rom_rtl.py : 由固件hex生成纯RTL case-ROM模块（无厂商IP/原语，官方答疑#5）
#
# 输入：objcopy -O verilog 生成的字节流hex（每行若干字节token，小端字序；
#       与 rtl/fpga/axi_rom.v 的 $readmemh 装载口径一致——先按字节流装入，
#       再每4字节拼一个小端32位字）。
# 输出：一个纯组合逻辑 case-ROM 模块（字地址→32位数据，未映射地址=0）。
#       用于PDS综合不支持initial/$readmemh初始化时的备选路径（接口不变）。
#
# 用法：
#   python tools/gen_rom_rtl.py sw/firmware/fir_demo/fir_demo.hex \
#          -o rtl/fpga/rom_case.v
import argparse


def load_bytes(path):
    """读objcopy -O verilog的hex：返回字节列表（忽略注释/@地址记录）。"""
    bs = []
    with open(path, "r", encoding="utf-8", errors="ignore") as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("//"):
                continue
            if line.startswith("@"):        # @地址记录：本生成器按顺序紧凑排布
                continue
            for tok in line.split():
                bs.append(int(tok, 16) & 0xFF)
    return bs


def main():
    ap = argparse.ArgumentParser(description="hex -> 纯RTL case-ROM")
    ap.add_argument("hexfile", help="objcopy -O verilog 字节流hex")
    ap.add_argument("-o", "--out", required=True, help="输出Verilog文件")
    ap.add_argument("-n", "--name", default="rom_case", help="模块名（默认rom_case）")
    ap.add_argument("--waw", type=int, default=14,
                    help="字地址位宽（默认14=64KB字节空间/4）")
    args = ap.parse_args()

    bs = load_bytes(args.hexfile)
    words = []
    for i in range(0, len(bs), 4):
        chunk = bs[i:i + 4] + [0] * (4 - len(bs[i:i + 4]))
        words.append(chunk[0] | (chunk[1] << 8) | (chunk[2] << 16) | (chunk[3] << 24))

    aw = args.waw
    digits = (aw + 3) // 4
    lines = []
    lines.append("// 由 tools/gen_rom_rtl.py 生成，勿手改")
    lines.append("// 纯RTL case-ROM（无厂商IP/原语，官方答疑#5）：")
    lines.append("// 字地址→32位数据（小端装载口径同axi_rom），未映射地址=0。")
    lines.append("// 来源: %s（%d字节 → %d字，%d字非零）"
                 % (args.hexfile, len(bs), len(words), sum(1 for w in words if w)))
    lines.append("`timescale 1ns/1ps")
    lines.append("module %s #(parameter AW = %d)(" % (args.name, aw))
    lines.append("    input  wire [AW-1:0] addr,   // 字地址")
    lines.append("    output reg  [31:0]   data")
    lines.append(");")
    lines.append("  always @* begin")
    lines.append("    case (addr)")
    for i, w in enumerate(words):
        if w == 0:
            continue                        # default=0，跳过零字减小体积
        lines.append("      %d'h%0*X: data = 32'h%08X;" % (aw, digits, i, w))
    lines.append("      default: data = 32'h00000000;")
    lines.append("    endcase")
    lines.append("  end")
    lines.append("endmodule")
    with open(args.out, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(lines) + "\n")
    print("生成完成: %s（模块 %s，%d字，非零 %d字）"
          % (args.out, args.name, len(words), sum(1 for w in words if w)))


if __name__ == "__main__":
    main()
