#!/usr/bin/env bash
# package_src.sh : 源码包打包脚本（T19交付物）
# 用法: bash tools/package_src.sh   → 生成 deliverables/源代码包.zip
# 内容: rtl/ tb/ sw/firmware/fir_demo/ tools/ fpga/ docs/ Makefile.fir .gitignore
#       剔除: 仿真产物/固件编译产物/.git/官方只读文件（core/mcu_system等按
#       官方许可不随包分发，README注明从ARM官网获取）
set -euo pipefail
cd "$(dirname "$0")/.."
OUT=deliverables
STAGE="$OUT/src_stage"
rm -rf "$STAGE"
mkdir -p "$STAGE"

# 本项目新增文件（不含官方core/ mcu_system/ software/ doc/）
cp -r rtl tb sw/firmware tools fpga docs Makefile.fir .gitignore "$STAGE/"
# 讲解文档统一从验收材料复制（源文档已归档到验收材料/讲解文档）
cp -r "验收材料/讲解文档" "$STAGE/讲解文档"
# 剔除冗余：superpowers为团队过程文档（含内部台账），不入交付包；
# 讲解文档统一放在 验收材料/讲解文档，打包为 讲解文档/
rm -rf "$STAGE/docs/superpowers"
find "$STAGE" -name "*.o" -o -name "*.bin" -o -name "*.lst" -o -name "*.hex" -o -name "*.vvp" -o -name "*.vcd" | xargs rm -f
rm -rf "$STAGE/sim_out" "$STAGE/.vs"
# 官方文件引用说明（不随包分发，见README）
echo "官方Cortex-M0 DesignStart工程（core/ mcu_system/ software/ doc/）不随包分发，请从ARM官网下载：https://www.arm.com/resources/free-evaluation-arm-cpus" > "$STAGE/官方工程获取.txt"

cp "验收材料/讲解文档/交付物清单.md" "$STAGE/README.md"
# 打包：优先zip，缺则用PowerShell Compress-Archive（Windows自带）
if command -v zip >/dev/null 2>&1; then
  ( cd "$STAGE" && zip -r "../源代码包.zip" . -x "*.zip" )
else
  rm -f "$OUT/源代码包.zip"
  python - <<'PY'
import os, zipfile
stage = os.path.join("deliverables", "src_stage")
out = os.path.join("deliverables", "源代码包.zip")
with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
    for root, dirs, files in os.walk(stage):
        for f in files:
            full = os.path.join(root, f)
            z.write(full, os.path.relpath(full, stage))
PY
fi
rm -rf "$STAGE"
echo "OK: $OUT/源代码包.zip"
