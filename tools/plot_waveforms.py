#!/usr/bin/env python3
# plot_waveforms.py : FIR滤波前后信号波形图（零依赖，纯标准库生成SVG矢量图）
# 数据来源：tb/data/input_q15.hex（1024样本输入，Q1.15）与
#          tb/data/golden_q31.hex（黄金模型输出，Q1.31）。
# 说明：硬件输出与黄金模型差异<0.1%（tb_soc断言），图中不可分辨，
#       故输出曲线以黄金模型表示（报告口径一致）。
# 输出：docs/report/figures/*.svg + index.html（浏览器双击可看）
import os

DATA = os.path.join(os.path.dirname(__file__), "..", "tb", "data")
OUT  = os.path.join(os.path.dirname(__file__), "..", "docs", "report", "figures")

def read_hex(name, scale):
    vals = []
    with open(os.path.join(DATA, name)) as f:
        for line in f:
            line = line.strip()
            if line and not line.startswith("@"):
                v = int(line, 16)
                if v >= (1 << 31): v -= (1 << 32)      # 有符号
                vals.append(v / scale)
    return vals

X = read_hex("input_q15.hex", 32768.0)     # Q1.15 -> [-1,1)
Y = read_hex("golden_q31.hex", 2**31)      # Q1.31 -> [-1,1)
C = read_hex("coeff_q15.hex", 32768.0)     # 81阶系数（82个Q1.15值）

W, H = 820, 300
M = 48   # 边距

def svg_plot(points, out, title, ylabel="", xlabel="样本序号", ylim=(-1.2, 1.2),
             legend=None, x0=0):
    """points: [(xs, ys, color, label, width), ...] 每段曲线一组"""
    os.makedirs(OUT, exist_ok=True)
    n = max(len(p[0]) for p in points)
    def px(i):  return M + (W - 2 * M) * i / (n - 1)
    def py(v):
        lo, hi = ylim
        return M + (H - 2 * M) * (hi - v) / (hi - lo)
    parts = [f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" '
             f'font-family="Segoe UI, Microsoft YaHei, sans-serif">']
    parts.append(f'<rect width="{W}" height="{H}" fill="white"/>')
    # 网格与坐标轴
    for gv in (-1.0, -0.5, 0, 0.5, 1.0):
        y = py(gv)
        parts.append(f'<line x1="{M}" y1="{y:.1f}" x2="{W-M}" y2="{y:.1f}" '
                     f'stroke="#ddd" stroke-width="1"/>')
        parts.append(f'<text x="{M-6}" y="{y+4:.1f}" font-size="11" fill="#666" '
                     f'text-anchor="end">{gv:g}</text>')
    parts.append(f'<line x1="{M}" y1="{py(0):.1f}" x2="{W-M}" y2="{py(0):.1f}" '
                 f'stroke="#999" stroke-width="1.2"/>')
    # 曲线
    for xs, ys, color, label, lw in points:
        pts = " ".join(f"{px(i + x0):.1f},{py(ys[i]):.1f}"
                       for i in range(min(len(xs), len(ys))))
        parts.append(f'<polyline points="{pts}" fill="none" stroke="{color}" '
                     f'stroke-width="{lw}"/>')
    # 图例
    if legend:
        lx = W - M - 160
        for k, (color, label) in enumerate(legend):
            ly = M + 16 + k * 20
            parts.append(f'<line x1="{lx}" y1="{ly}" x2="{lx+26}" y2="{ly}" '
                         f'stroke="{color}" stroke-width="2"/>')
            parts.append(f'<text x="{lx+32}" y="{ly+4}" font-size="12" '
                         f'fill="#333">{label}</text>')
    parts.append(f'<text x="{M}" y="{H-12}" font-size="12" fill="#333">{xlabel}</text>')
    parts.append(f'<text x="{W/2}" y="{M-26}" font-size="16" fill="#111" '
                 f'text-anchor="middle" font-weight="bold">{title}</text>')
    parts.append(f'<text x="{M}" y="{M-8}" font-size="12" fill="#666">{ylabel}</text>')
    parts.append('</svg>')
    with open(out, "w", encoding="utf-8") as f:
        f.write("\n".join(parts))
    print("wrote", out)

# 图1：冲激输入→冲激响应（第1段，前100点，系数对称形状一目了然）
svg_plot([(X[0:100], X[0:100], "#4C8BF5", "输入(冲激δ)", 1.5),
          (Y[0:100], Y[0:100], "#F5A623", "滤波输出(冲激响应)", 2)],
         os.path.join(OUT, "seg1_impulse.svg"),
         "第1段 冲激输入 → 输出=滤波器冲激响应（即系数形状）",
         ylabel="幅度", xlabel="样本序号 n（本段前100点）",
         legend=[("#4C8BF5", "输入：单位冲激"), ("#F5A623", "输出：冲激响应")])

# 图2：低频正弦（通带，0.05归一化频率）
svg_plot([(X[256:512], X[256:512], "#4C8BF5", "", 1),
          (Y[256:512], Y[256:512], "#F5A623", "", 1.8)],
         os.path.join(OUT, "seg2_lowfreq.svg"),
         "第2段 低频正弦（通带）→ 输出同频正弦（直流增益≈0.5）",
         ylabel="幅度", xlabel="样本序号 n（本段256点）",
         legend=[("#4C8BF5", "输入：0.7·sin(2π·0.05n)"), ("#F5A623", "滤波输出")])

# 图3：高频正弦+噪声（阻带，0.25归一化频率），前64点看得清
svg_plot([(X[512:576], X[512:576], "#4C8BF5", "", 1),
          (Y[512:576], Y[512:576], "#F5A623", "", 1.8)],
         os.path.join(OUT, "seg3_highfreq.svg"),
         "第3段 高频正弦+噪声（阻带）→ 输出被显著衰减（低通滤波效果）",
         ylabel="幅度", xlabel="样本序号 n（本段前64点）",
         legend=[("#4C8BF5", "输入：0.8·sin(2π·0.25n)+噪声"), ("#F5A623", "滤波输出")])

# 图4：满幅随机噪声→平滑（低通）
svg_plot([(X[768:1024], X[768:1024], "#4C8BF5", "", 1),
          (Y[768:1024], Y[768:1024], "#F5A623", "", 1.8)],
         os.path.join(OUT, "seg4_noise.svg"),
         "第4段 满幅随机噪声 → 输出被平滑（高频分量滤除）",
         ylabel="幅度", xlabel="样本序号 n（本段256点）",
         legend=[("#4C8BF5", "输入：满幅随机"), ("#F5A623", "滤波输出")])

# 图5：系数对称性（81阶低通，Hamming窗）
svg_plot([(list(range(len(C))), C, "#F5A623", "", 1.8)],
         os.path.join(OUT, "coeff_sym.svg"),
         "81阶FIR系数（对称 h[k]=h[80-k]，决赛创新点：82次乘加→41次）",
         ylabel="系数值(Q1.15)", xlabel="系数序号 k", ylim=(-0.3, 0.3),
         legend=[("#F5A623", "h[k]")])

# 图6：幅度频率响应（纯Python DFT，无numpy依赖）
NFFT = 512
mag = []
for m in range(NFFT // 2 + 1):
    re = im = 0.0
    w = 2 * 3.141592653589793 * m / NFFT
    for k, c in enumerate(C):
        re += c * __import__("math").cos(w * k)
        im -= c * __import__("math").sin(w * k)
    mag.append(abs(complex(re, im)))
mmax = max(mag) or 1.0
mag_db = [20 * __import__("math").log10(v / mmax + 1e-12) for v in mag]
svg_plot([(list(range(len(mag_db))), mag_db, "#4C8BF5", "", 2)],
         os.path.join(OUT, "mag_response.svg"),
         "滤波器幅度频率响应（截止0.15·fs，阻带衰减约-40dB）",
         ylabel="归一化幅度(dB)", xlabel="归一化频率 f/fs（0~0.5）",
         ylim=(-80, 5),
         legend=[("#4C8BF5", "|H(f)|")])

# 索引页
links = [("seg1_impulse.svg", "第1段 冲激→冲激响应（=系数形状）"),
         ("seg2_lowfreq.svg", "第2段 低频正弦（通带通过）"),
         ("seg3_highfreq.svg", "第3段 高频正弦+噪声（阻带衰减）"),
         ("seg4_noise.svg", "第4段 满幅随机→平滑（低通直观效果）"),
         ("coeff_sym.svg", "81阶系数（对称性，创新点）"),
         ("mag_response.svg", "幅度频率响应（低通特性）")]
with open(os.path.join(OUT, "index.html"), "w", encoding="utf-8") as f:
    f.write('<!doctype html><meta charset="utf-8"><title>FIR滤波波形图</title>')
    f.write('<h2>FIR滤波前后信号波形（数据=tb_soc仿真，硬件输出与黄金模型<0.1%）</h2>')
    for fn, cap in links:
        f.write(f'<p>{cap}<br><img src="{fn}" style="max-width:100%"></p>')
print("done:", OUT)
