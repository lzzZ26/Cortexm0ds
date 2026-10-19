// tb_fir_para_impulse_sym.v : 对称系数冲激响应波形（参数化复用基础TB）
// 用途：与 tb_fir_para_impulse（非对称）对照——对称系数下冲激响应左右镜像
//       （y[0]≈y[81]），非对称下明显不同。
`timescale 1ns/1ps
module tb_fir_para_impulse_sym;
  tb_fir_para_impulse #(
    .COEFF_FILE ("tb/data/coeff_q15.hex"),
    .GOLDEN_FILE("tb/data/golden_q31.hex"),
    .VCD_FILE   ("sim_out/q18_impulse_sym.vcd"),
    .CSV_FILE   ("sim_out/q18_impulse_sym.csv"),
    .TAG        ("sym")
  ) u_tb ();
endmodule
