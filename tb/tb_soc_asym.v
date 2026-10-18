// tb_soc_asym.v : 非对称固件系统级验证（参数化复用tb_soc）
// 固化：固件=fir_demo_asym.hex（非对称系数演示版），黄金=golden_asym_q31.hex。
// 断言沿用tb_soc：UART四标记（含 ** FIR ASYM MODE ** 不影响原判定）+
// out_buf 1024样本与黄金比对<0.1% + 指标计数1024。
`timescale 1ns/1ps
module tb_soc_asym;
  tb_soc #(
    .FIRMWARE("sw/firmware/fir_demo/fir_demo_asym.hex"),
    .GOLDEN_FILE("tb/data/golden_asym_q31.hex")
  ) u_tb ();
endmodule
