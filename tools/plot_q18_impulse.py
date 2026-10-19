#!/usr/bin/env python3
# plot_q18_impulse.py : Q18验收图——非对称系数冲激响应（RTL仿真输出）
# 输入：tb/data/coeff_asym_q15.hex（系数）、sim_out/q18_impulse.csv（硬件仿真输出）
# 输出：docs/report/figures/q18_impulse_asym.svg（零依赖，浏览器可看）
import os

ROOT = os.path.join(os.path.dirname(__file__), "..")
COEF = os.path.join(ROOT, "tb", "data", "coeff_asym_q15.hex")
CSV  = os.path.join(ROOT, "sim_out", "q18_impulse.csv")
OUT  = os.path.join(ROOT, "docs", "report", "figures", "q18_impulse_asym.svg")

def read_coeff():
    vals = []
    with open(COEF) as f:
        for line in f:
            line = line.strip()
            if line:
                v = int(line, 16)
                if v >= 0x8000:
                    v -= 0x10000
                vals.append(v / 32768.0)
    return vals

def read_csv():
    ys = []
    with open(CSV) as f:
        next(f)
        for line in f:
            line = line.strip()
            if not line:
                continue
            n, h = line.split(",")
            v = int(h, 16)
            if v >= 0x80000000:
                v -= 0x100000000
            ys.append(v / float(2 ** 31))
    return ys

C = read_coeff()
Y = read_csv()
N = len(Y)

W, H = 900, 420
ML, MR, MT, MB = 70, 30, 70, 60

def px(n):  return ML + (W - ML - MR) * n / float(N - 1)
def py(v):
    lo, hi = -1.05, 1.05
    return MT + (H - MT - MB) * (hi - v) / (hi - lo)

parts = []
parts.append(f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" '
             f'viewBox="0 0 {W} {H}">')
parts.append(f'<rect x="0" y="0" width="{W}" height="{H}" fill="#ffffff"/>')
parts.append('<text x="450" y="30" font-family="sans-serif" font-size="18" '
             'text-anchor="middle" fill="#111">Q18 验收：非对称系数冲激响应'
             '（RTL仿真 fir_core_para，82抽头）</text>')
parts.append('<text x="450" y="50" font-family="sans-serif" font-size="12" '
             'text-anchor="middle" fill="#555">'
             '输入=冲激 0x7FFF；硬件输出 y[n]（红）应等于 c[n]×0x7FFF；'
             '左右明显不对称；前82点与 golden_asym 逐位相等</text>')

# 网格与坐标轴
lo, hi = -1.05, 1.05
for k in range(-10, 11, 2):
    v = k / 10.0
    yy = py(v)
    parts.append(f'<line x1="{ML}" y1="{yy:.1f}" x2="{W-MR}" y2="{yy:.1f}" '
                 f'stroke="#e5e5e5" stroke-width="1"/>')
    parts.append(f'<text x="{ML-8}" y="{yy+4:.1f}" font-family="sans-serif" '
                 f'font-size="10" text-anchor="end" fill="#666">{v:.1f}</text>')
zero = py(0)
parts.append(f'<line x1="{ML}" y1="{zero:.1f}" x2="{W-MR}" y2="{zero:.1f}" '
             f'stroke="#999" stroke-width="1"/>')
for n in range(0, N, 10):
    parts.append(f'<line x1="{px(n):.1f}" y1="{H-MB}" x2="{px(n):.1f}" '
                 f'y2="{H-MB+5}" stroke="#666" stroke-width="1"/>')
    parts.append(f'<text x="{px(n):.1f}" y="{H-MB+18}" font-family="sans-serif" '
                 f'font-size="10" text-anchor="middle" fill="#666">{n}</text>')
parts.append(f'<text x="{W/2}" y="{H-18}" font-family="sans-serif" font-size="12" '
             f'text-anchor="middle" fill="#333">抽头序号 n</text>')
parts.append(f'<text x="18" y="{H/2}" font-family="sans-serif" font-size="12" '
             f'text-anchor="middle" fill="#333" '
             f'transform="rotate(-90 18 {H/2})">幅度（Q1.15 / Q1.31 归一化）</text>')

# 系数：浅蓝竖线（从0到系数值）
for n, c in enumerate(C):
    parts.append(f'<line x1="{px(n):.1f}" y1="{zero:.1f}" x2="{px(n):.1f}" '
                 f'y2="{py(c):.1f}" stroke="#9ecae1" stroke-width="3"/>')

# 硬件输出：红线+圆点
pts = " ".join(f"{px(n):.1f},{py(y):.1f}" for n, y in enumerate(Y))
parts.append(f'<polyline points="{pts}" fill="none" stroke="#d62728" stroke-width="1.6"/>')
for n, y in enumerate(Y):
    parts.append(f'<circle cx="{px(n):.1f}" cy="{py(y):.1f}" r="1.8" fill="#d62728"/>')

# 标注 y[0] / y[81]
for n, lab in ((0, "y[0]=0x16C1D27C"), (81, "y[81]=0xA633B39A")):
    y = Y[n]
    tx = px(n) + (10 if n == 0 else -10)
    anchor = "start" if n == 0 else "end"
    parts.append(f'<line x1="{px(n):.1f}" y1="{py(y):.1f}" '
                 f'x2="{px(n):.1f}" y2="{py(y)-28:.1f}" stroke="#d62728" '
                 f'stroke-width="1" stroke-dasharray="3,2"/>')
    parts.append(f'<text x="{tx:.1f}" y="{py(y)-32:.1f}" font-family="sans-serif" '
                 f'font-size="11" text-anchor="{anchor}" fill="#d62728">{lab}</text>')

# 图例
parts.append(f'<line x1="{W-250}" y1="{MT+6}" x2="{W-220}" y2="{MT+6}" '
             f'stroke="#9ecae1" stroke-width="4"/>')
parts.append(f'<text x="{W-212}" y="{MT+10}" font-family="sans-serif" '
             f'font-size="11" fill="#333">系数 c[n]（Q1.15）</text>')
parts.append(f'<line x1="{W-250}" y1="{MT+26}" x2="{W-220}" y2="{MT+26}" '
             f'stroke="#d62728" stroke-width="2"/>')
parts.append(f'<text x="{W-212}" y="{MT+30}" font-family="sans-serif" '
             f'font-size="11" fill="#333">仿真输出 y[n]</text>')

parts.append("</svg>")
os.makedirs(os.path.dirname(OUT), exist_ok=True)
with open(OUT, "w", encoding="utf-8", newline="\n") as f:
    f.write("\n".join(parts) + "\n")
print("生成完成:", OUT)
print("y[0]=%.4f y[40]=%.4f y[81]=%.4f" % (Y[0], Y[40], Y[81]))
