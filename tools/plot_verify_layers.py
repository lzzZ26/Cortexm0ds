#!/usr/bin/env python3
# plot_verify_layers.py : 三层验证总览图（零依赖 SVG）
# 输出：docs/report/figures/verify_three_layers.svg
import os

OUT = os.path.join(os.path.dirname(__file__), "..", "docs", "report", "figures",
                   "verify_three_layers.svg")

W, H = 1600, 900
PANEL_Y = 170
PANEL_H = 560
PX = [40, 560, 1080]
PW = 480

COLORS = [
    ("#e8f1fb", "#2f6fb3"),   # 单元
    ("#e9f7ef", "#2e8b57"),   # 集成
    ("#fdf2e3", "#c47b1a"),   # 系统
]

TITLES = ["① 单元 / 模块验证", "② 集成验证（不含 CPU）", "③ 系统测试（含 CPU）"]

BODY = [
    [
        ("代表 TB", "tb_fir_core_para / tb_fir_core_sym"),
        ("", "tb_fir_core / tb_fir_top / tb_fir_top_dual"),
        ("", "tb_dma_channel / tb_axi_rom / tb_decode"),
        ("关键结果", "三套系数黄金回归 <0.1%（对称/非对称/大系数）"),
        ("", "吞吐 1.0 样本/拍；随机反压；中止 CLR 无污染"),
        ("", "协议检查器零违规"),
        ("状态", "PASS"),
    ],
    [
        ("代表 TB", "tb_integ / tb_arb / tb_dma_top / tb_dma_chain"),
        ("", "VIP 替代 CPU，真实互连拓扑"),
        ("关键结果", "SRAM 16 拍 INCR 往返"),
        ("", "82 系数配置 + 1024 样本滤波"),
        ("", "对称 + 非对称两轮黄金比对 <0.1%"),
        ("", "DMA 单拍搬运；协议零违规"),
        ("状态", "PASS"),
    ],
    [
        ("代表 TB", "tb_soc / tb_soc_asym / tb_soc_smoke"),
        ("", "tb_soc_smoke_rom（FPGA ROM 路径）"),
        ("关键结果", "UART 回显 64 字符"),
        ("", "6 通道 DMA 自检；软硬协同"),
        ("", "CPU 配系数 + DMA 搬运 + 读回比对"),
        ("", "1024 样本黄金 <0.1%；四标记齐全"),
        ("状态", "PASS"),
    ],
]


def esc(s):
    return s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")


parts = []
parts.append(f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" '
             f'viewBox="0 0 {W} {H}">')
parts.append(f'<rect width="{W}" height="{H}" fill="#ffffff"/>')
parts.append('<text x="800" y="58" font-family="sans-serif" font-size="30" '
             'font-weight="bold" text-anchor="middle" fill="#111">'
             '三层验证总览：17 个回归目标全部 PASS</text>')
parts.append('<text x="800" y="92" font-family="sans-serif" font-size="17" '
             'text-anchor="middle" fill="#555">'
             '单元/模块 → 集成（不含 CPU）→ 系统（含 CPU）；协议检查器零违规；'
             '误差按相对均方根 &lt;0.1%（逐样本 0.0977% 点态上界）</text>')

for i in range(3):
    x = PX[i]
    bg, fg = COLORS[i]
    parts.append(f'<rect x="{x}" y="{PANEL_Y}" width="{PW}" height="{PANEL_H}" '
                 f'rx="12" fill="{bg}" stroke="{fg}" stroke-width="2"/>')
    parts.append(f'<rect x="{x}" y="{PANEL_Y}" width="{PW}" height="56" rx="12" '
                 f'fill="{fg}"/>')
    parts.append(f'<rect x="{x}" y="{PANEL_Y+44}" width="{PW}" height="12" '
                 f'fill="{fg}"/>')
    parts.append(f'<text x="{x + PW/2}" y="{PANEL_Y+37}" font-family="sans-serif" '
                 f'font-size="22" font-weight="bold" text-anchor="middle" '
                 f'fill="#ffffff">{esc(TITLES[i])}</text>')

    y = PANEL_Y + 100
    for label, text in BODY[i]:
        if label:
            parts.append(f'<text x="{x+28}" y="{y}" font-family="sans-serif" '
                         f'font-size="17" font-weight="bold" fill="{fg}">'
                         f'{esc(label)}</text>')
            y += 32
        parts.append(f'<text x="{x+28}" y="{y}" font-family="sans-serif" '
                     f'font-size="16" fill="#222">{esc(text)}</text>')
        y += 30

# 底部 Q18 证据条
by = PANEL_Y + PANEL_H + 40
parts.append(f'<rect x="40" y="{by}" width="{W-80}" height="110" rx="10" '
             f'fill="#f5f5f5" stroke="#bbb"/>')
parts.append(f'<text x="70" y="{by+34}" font-family="sans-serif" font-size="19" '
             f'font-weight="bold" fill="#111">Q18（赛题答疑第 18 条）可视化证据</text>')
parts.append(f'<text x="70" y="{by+66}" font-family="sans-serif" font-size="16" '
             f'fill="#222">对称系数：y[0] = y[81] = 0x0004FFF6（左右镜像）'
             f'　|　非对称系数：y[0] = 0x16C1D27C，y[81] = 0xA633B39A（左右明显不同）</text>')
parts.append(f'<text x="70" y="{by+94}" font-family="sans-serif" font-size="15" '
             f'fill="#555">对应图：docs/report/figures/q18_impulse_compare.svg'
             f'（冲激响应，82 个抽头）</text>')

parts.append("</svg>")
os.makedirs(os.path.dirname(OUT), exist_ok=True)
with open(OUT, "w", encoding="utf-8", newline="\n") as f:
    f.write("\n".join(parts) + "\n")
print("生成完成:", OUT)
