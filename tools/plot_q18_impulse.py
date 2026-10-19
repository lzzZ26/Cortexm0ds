#!/usr/bin/env python3
# plot_q18_impulse.py : Q18验收图——对称/非对称系数冲激响应（RTL仿真输出）
# 输入：tb/data/coeff_q15.hex、coeff_asym_q15.hex；
#       sim_out/q18_impulse_sym.csv、sim_out/q18_impulse.csv
# 输出：docs/report/figures/q18_impulse_sym.svg
#       docs/report/figures/q18_impulse_asym.svg
#       docs/report/figures/q18_impulse_compare.svg（上下对比）
# 零依赖，纯标准库；浏览器直接打开。
import os

ROOT = os.path.join(os.path.dirname(__file__), "..")
DATA = os.path.join(ROOT, "tb", "data")
SIM  = os.path.join(ROOT, "sim_out")
OUT  = os.path.join(ROOT, "docs", "report", "figures")


def read_coeff(name):
    vals = []
    with open(os.path.join(DATA, name)) as f:
        for line in f:
            line = line.strip()
            if line:
                v = int(line, 16)
                if v >= 0x8000:
                    v -= 0x10000
                vals.append(v / 32768.0)
    return vals


def read_csv(path):
    ys = []
    with open(path) as f:
        next(f)
        for line in f:
            line = line.strip()
            if not line:
                continue
            _, h = line.split(",")
            v = int(h, 16)
            if v >= 0x80000000:
                v -= 0x100000000
            ys.append(v / float(2 ** 31))
    return ys


def chart(x0, y0, w, h, coeff, ys, title, subtitle, legend=True):
    """在 (x0,y0) 起、w×h 的区域画一张图，返回SVG片段列表。"""
    ml, mr, mt, mb = 60, 20, 48, 42
    # 自动量程：按本组系数/输出的最大绝对值（两侧对比图各自量程，形状更清楚）
    vmax = max([abs(v) for v in coeff] + [abs(v) for v in ys] + [0.01]) * 1.15
    n = len(ys)

    def px(i): return x0 + ml + (w - ml - mr) * i / float(n - 1)
    def py(v): return y0 + mt + (h - mt - mb) * (vmax - v) / (2 * vmax)

    p = []
    p.append(f'<text x="{x0 + w/2:.0f}" y="{y0+20}" font-family="sans-serif" '
             f'font-size="15" text-anchor="middle" fill="#111">{title}</text>')
    p.append(f'<text x="{x0 + w/2:.0f}" y="{y0+37}" font-family="sans-serif" '
             f'font-size="11" text-anchor="middle" fill="#555">{subtitle}</text>')

    for k in range(-4, 5):
        v = vmax * k / 4.0
        yy = py(v)
        p.append(f'<line x1="{x0+ml}" y1="{yy:.1f}" x2="{x0+w-mr}" y2="{yy:.1f}" '
                 f'stroke="#ececec" stroke-width="1"/>')
        p.append(f'<text x="{x0+ml-6}" y="{yy+3:.1f}" font-family="sans-serif" '
                 f'font-size="9" text-anchor="end" fill="#666">{v:.3f}</text>')
    zero = py(0)
    p.append(f'<line x1="{x0+ml}" y1="{zero:.1f}" x2="{x0+w-mr}" y2="{zero:.1f}" '
             f'stroke="#999" stroke-width="1"/>')
    for i in range(0, n, 10):
        p.append(f'<line x1="{px(i):.1f}" y1="{y0+h-mb}" x2="{px(i):.1f}" '
                 f'y2="{y0+h-mb+4}" stroke="#666" stroke-width="1"/>')
        p.append(f'<text x="{px(i):.1f}" y="{y0+h-mb+16}" font-family="sans-serif" '
                 f'font-size="9" text-anchor="middle" fill="#666">{i}</text>')
    p.append(f'<text x="{x0+w/2:.0f}" y="{y0+h-8}" font-family="sans-serif" '
             f'font-size="10" text-anchor="middle" fill="#333">抽头序号 n</text>')

    # 系数浅蓝竖线
    for i, c in enumerate(coeff):
        p.append(f'<line x1="{px(i):.1f}" y1="{zero:.1f}" x2="{px(i):.1f}" '
                 f'y2="{py(c):.1f}" stroke="#9ecae1" stroke-width="3"/>')
    # 仿真输出红线
    pts = " ".join(f"{px(i):.1f},{py(y):.1f}" for i, y in enumerate(ys))
    p.append(f'<polyline points="{pts}" fill="none" stroke="#d62728" stroke-width="1.5"/>')
    for i, y in enumerate(ys):
        p.append(f'<circle cx="{px(i):.1f}" cy="{py(y):.1f}" r="1.6" fill="#d62728"/>')

    # y[0]/y[81]标注（数值从数据计算）
    for i in (0, n - 1):
        y = ys[i]
        tx = px(i) + (8 if i == 0 else -8)
        anchor = "start" if i == 0 else "end"
        p.append(f'<line x1="{px(i):.1f}" y1="{py(y):.1f}" x2="{px(i):.1f}" '
                 f'y2="{py(y)-22:.1f}" stroke="#d62728" stroke-width="1" '
                 f'stroke-dasharray="3,2"/>')
        p.append(f'<text x="{tx:.1f}" y="{py(y)-26:.1f}" font-family="sans-serif" '
                 f'font-size="10" text-anchor="{anchor}" fill="#d62728">'
                 f'y[{i}]={y:+.4f}</text>')

    if legend:
        p.append(f'<line x1="{x0+w-210}" y1="{y0+mt+4}" x2="{x0+w-184}" y2="{y0+mt+4}" '
                 f'stroke="#9ecae1" stroke-width="4"/>')
        p.append(f'<text x="{x0+w-177}" y="{y0+mt+8}" font-family="sans-serif" '
                 f'font-size="10" fill="#333">系数 c[n]</text>')
        p.append(f'<line x1="{x0+w-210}" y1="{y0+mt+20}" x2="{x0+w-184}" y2="{y0+mt+20}" '
                 f'stroke="#d62728" stroke-width="2"/>')
        p.append(f'<text x="{x0+w-177}" y="{y0+mt+24}" font-family="sans-serif" '
                 f'font-size="10" fill="#333">仿真输出 y[n]</text>')
    return p


def write_svg(path, w, h, body):
    svg = [f'<svg xmlns="http://www.w3.org/2000/svg" width="{w}" height="{h}" '
           f'viewBox="0 0 {w} {h}">',
           f'<rect x="0" y="0" width="{w}" height="{h}" fill="#ffffff"/>']
    svg += body
    svg.append("</svg>")
    os.makedirs(OUT, exist_ok=True)
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(svg) + "\n")
    print("生成完成:", path)


def main():
    c_sym = read_coeff("coeff_q15.hex")
    c_asym = read_coeff("coeff_asym_q15.hex")
    y_sym = read_csv(os.path.join(SIM, "q18_impulse_sym.csv"))
    y_asym = read_csv(os.path.join(SIM, "q18_impulse.csv"))

    base = ("输入=冲激 0x7FFF；硬件输出 y[n] 应等于 c[n]×0x7FFF；"
            "前82点与黄金模型逐位相等")

    body = chart(0, 0, 900, 400, c_sym, y_sym,
                 "对称系数冲激响应（RTL仿真 fir_core_para，82抽头）",
                 base + "；对称：y[0]≈y[81]", legend=False)
    write_svg(os.path.join(OUT, "q18_impulse_sym.svg"), 900, 400, body)

    body = chart(0, 0, 900, 400, c_asym, y_asym,
                 "非对称系数冲激响应（RTL仿真 fir_core_para，82抽头）",
                 base + "；非对称：y[0]≠y[81]", legend=False)
    write_svg(os.path.join(OUT, "q18_impulse_asym.svg"), 900, 400, body)

    body = []
    body += chart(0, 0, 900, 380, c_sym, y_sym,
                  "对称系数（对照组）",
                  "冲激响应左右镜像：y[0]≈y[81]")
    body += chart(0, 380, 900, 380, c_asym, y_asym,
                  "非对称系数（Q18证据）",
                  "冲激响应左右明显不同：y[0]≠y[81]")
    write_svg(os.path.join(OUT, "q18_impulse_compare.svg"), 900, 760, body)

    print("sym  y[0]=%+.4f y[81]=%+.4f" % (y_sym[0], y_sym[81]))
    print("asym y[0]=%+.4f y[81]=%+.4f" % (y_asym[0], y_asym[81]))


if __name__ == "__main__":
    main()
