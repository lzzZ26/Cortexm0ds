#!/usr/bin/env python3
# gen_fir_golden.py : FIR黄金模型生成器
# 黄金口径：系数与输入先量化到Q1.15（与硬件一致），用双精度算FIR，
#           结果再量化到Q1.31。硬件与黄金之差=纯实现误差（累加/舍入/饱和）。
import math, random, os

TAPS = 82
N    = 1024
FC   = 0.15                      # 归一化截止频率

def sinc(x):
    return 1.0 if abs(x) < 1e-12 else math.sin(math.pi * x) / (math.pi * x)

def hamming(k, n):
    return 0.54 - 0.46 * math.cos(2.0 * math.pi * k / (n - 1))

def design_lowpass(taps, fc):
    c = []
    for k in range(taps):
        x = k - (taps - 1) / 2.0
        c.append(2.0 * fc * sinc(2.0 * fc * x) * hamming(k, taps))
    return c

def q(v, bits):                  # double -> 定点有符号整数（饱和+舍入）
    m = 2 ** (bits - 1)
    i = int(round(v * m))
    return max(-m, min(m - 1, i))

def fir_ref(c, x):
    y = []
    for n in range(len(x)):
        acc = 0.0
        for k in range(TAPS):
            if n - k >= 0:
                acc += c[k] * x[n - k]
        y.append(acc)
    return y

def gen_extra_set(tag, coeffs, xq):
    """非对称黄金一套：系数量化Q1.15→双精度FIR（同一四段输入）→Q1.31落盘"""
    cq = [q(v, 16) for v in coeffs]
    yq = [q(v, 32) for v in fir_ref([v / 32768.0 for v in cq],
                                   [v / 32768.0 for v in xq])]
    with open(f"tb/data/coeff_{tag}_q15.hex", "w") as f:
        f.write("\n".join(f"{v & 0xFFFF:04X}" for v in cq) + "\n")
    with open(f"tb/data/golden_{tag}_q31.hex", "w") as f:
        f.write("\n".join(f"{v & 0xFFFFFFFF:08X}" for v in yq) + "\n")
    return cq, yq

def main():
    random.seed(20261002)
    # 1) 系数：窗函数法低通，归一化使直流增益≈0.5（留6dB饱和余量）
    c = design_lowpass(TAPS, FC)
    dc = sum(c)
    if abs(dc) > 1e-9:
        c = [v * 0.5 / dc for v in c]
    # 2) 输入：四段拼接
    x = []
    x += [1.0] + [0.0] * (N // 4 - 1)                                    # 冲激
    x += [0.7 * math.sin(2 * math.pi * 0.05 * n) for n in range(N // 4)] # 低频正弦
    x += [0.8 * math.sin(2 * math.pi * 0.25 * n) + 0.1 * random.uniform(-1, 1)
          for n in range(N // 4)]                                        # 高频正弦+噪声
    x += [0.9 * random.uniform(-1, 1) for _ in range(N // 4)]            # 满幅随机
    # 3) 量化到Q1.15（硬件口径）
    cq = [q(v, 16) for v in c]
    xq = [q(v, 16) for v in x]
    # 4) 双精度FIR（用量化值）→ 量化到Q1.31
    yq = [q(v, 32) for v in fir_ref([v / 32768.0 for v in cq],
                                   [v / 32768.0 for v in xq])]
    # 5) 非对称黄金两套（设计决策4：同一四段输入分别生成）：
    #    ①随机系数（固定seed均匀分布，任意非对称——通用核合规主路径）
    random.seed(20261019)
    c_asym = [random.uniform(-1.0, 1.0) for _ in range(TAPS)]
    #    ②大系数集（直流增益>1，专压饱和路径：全正0.5..1.0，和≈61）
    random.seed(20261020)
    c_gain = [random.uniform(0.5, 1.0) for _ in range(TAPS)]
    cq_asym = None
    for tag, cset in (("asym", c_asym), ("gain", c_gain)):
        cq_set, _ = gen_extra_set(tag, cset, xq)
        if tag == "asym":
            cq_asym = cq_set
    # 6) 落盘
    os.makedirs("tb/data", exist_ok=True)
    os.makedirs("sw/firmware/fir_demo", exist_ok=True)
    with open("tb/data/coeff_q15.hex", "w") as f:
        f.write("\n".join(f"{v & 0xFFFF:04X}" for v in cq) + "\n")
    with open("tb/data/input_q15.hex", "w") as f:
        f.write("\n".join(f"{v & 0xFFFF:04X}" for v in xq) + "\n")
    with open("tb/data/golden_q31.hex", "w") as f:
        f.write("\n".join(f"{v & 0xFFFFFFFF:08X}" for v in yq) + "\n")
    with open("sw/firmware/fir_demo/fir_golden.h", "w") as f:
        f.write("// 由 tools/gen_fir_golden.py 生成，勿手改\n")
        f.write("#define FIR_TAPS %d\n#define FIR_N %d\n" % (TAPS, N))
        f.write("static const short fir_coeff[FIR_TAPS] = {%s};\n" % ",".join(map(str, cq)))
        f.write("static const short fir_coeff_asym[FIR_TAPS] = {%s};\n" % ",".join(map(str, cq_asym)))
        f.write("static const short fir_input[FIR_N] = {%s};\n" % ",".join(map(str, xq)))
        f.write("static const int   fir_golden[FIR_N] = {%s};\n" % ",".join(map(str, yq)))
    print("生成完成: coeff_q15.hex / input_q15.hex / golden_q31.hex / fir_golden.h")
    print("系数示例(前4):", cq[:4], " 输入示例(前4):", xq[:4], " 期望输出示例(前4):", yq[:4])
    print("生成完成: coeff_asym_q15.hex / golden_asym_q31.hex / "
          "coeff_gain_q15.hex / golden_gain_q31.hex")

if __name__ == "__main__":
    main()
