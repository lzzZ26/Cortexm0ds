// tb_decode.v : 地址译码全覆盖测试——每个地址必须恰好选通一个从机（或默认从机）
`timescale 1ns/1ps
module tb_decode;
  reg  [31:0] w_addr, r_addr;
  wire flash_arsel, sram_awsel, sram_arsel, apbsys_awsel, apbsys_arsel;
  wire gpio0_awsel, gpio0_arsel, gpio1_awsel, gpio1_arsel;
  wire fir_awsel, fir_arsel, dma_awsel, dma_arsel, defslv_awsel, defslv_arsel;

  ic_axi_addr_decode u_dec (
    .w_addr(w_addr), .r_addr(r_addr),
    .flash_arsel(flash_arsel),
    .sram_awsel(sram_awsel), .sram_arsel(sram_arsel),
    .apbsys_awsel(apbsys_awsel), .apbsys_arsel(apbsys_arsel),
    .gpio0_awsel(gpio0_awsel), .gpio0_arsel(gpio0_arsel),
    .gpio1_awsel(gpio1_awsel), .gpio1_arsel(gpio1_arsel),
    .fir_awsel(fir_awsel), .fir_arsel(fir_arsel),
    .dma_awsel(dma_awsel), .dma_arsel(dma_arsel),
    .defslv_awsel(defslv_awsel), .defslv_arsel(defslv_arsel));

  reg [31:0] addr;
  reg [15:0] hi16;
  integer i;

  task check_case;
    input [31:0] a;
    input        exp_flash, exp_sram, exp_apb, exp_g0, exp_g1, exp_fir, exp_dma, exp_def;
    begin
      w_addr = a; r_addr = a; #1;
      if (flash_arsel !== exp_flash) $fatal(1, "FAIL: addr=%h flash_arsel", a);
      if (sram_arsel  !== exp_sram)  $fatal(1, "FAIL: addr=%h sram", a);
      if (apbsys_arsel!== exp_apb)   $fatal(1, "FAIL: addr=%h apbsys", a);
      if (gpio0_arsel !== exp_g0)    $fatal(1, "FAIL: addr=%h gpio0", a);
      if (gpio1_arsel !== exp_g1)    $fatal(1, "FAIL: addr=%h gpio1", a);
      if (fir_arsel   !== exp_fir)   $fatal(1, "FAIL: addr=%h fir", a);
      if (dma_arsel   !== exp_dma)   $fatal(1, "FAIL: addr=%h dma", a);
      if (defslv_arsel!== exp_def)   $fatal(1, "FAIL: addr=%h defslv", a);
    end
  endtask

  initial begin
    #10;
    check_case(32'h0000_0000, 1,0,0,0,0,0,0,0);   // Flash
    check_case(32'h0000_FFFF, 1,0,0,0,0,0,0,0);
    check_case(32'h2000_0000, 0,1,0,0,0,0,0,0);   // SRAM
    check_case(32'h2000_FFFF, 0,1,0,0,0,0,0,0);
    check_case(32'h4000_0000, 0,0,1,0,0,0,0,0);   // APB子系统
    check_case(32'h4000_FFFF, 0,0,1,0,0,0,0,0);
    check_case(32'h4001_0000, 0,0,0,1,0,0,0,0);   // GPIO0
    check_case(32'h4001_1000, 0,0,0,0,1,0,0,0);   // GPIO1
    check_case(32'h4002_0000, 0,0,0,0,0,1,0,0);   // FIR
    check_case(32'h4002_0FFF, 0,0,0,0,0,1,0,0);
    check_case(32'h4003_0000, 0,0,0,0,0,0,1,0);   // DMA配置
    check_case(32'h4003_0FFF, 0,0,0,0,0,0,1,0);
    check_case(32'h5000_0000, 0,0,0,0,0,0,0,1);   // 默认从机（DECERR）
    check_case(32'h4004_0000, 0,0,0,0,0,0,0,1);
    check_case(32'h1000_0000, 0,0,0,0,0,0,0,1);
    // 遍历：所有64K块必须"恰好选通一个"
    for (i = 0; i < 65536; i = i + 1) begin
      hi16 = i;
      addr = {hi16, 16'h0000};
      w_addr = addr; r_addr = addr; #1;
      if ((flash_arsel + sram_arsel + apbsys_arsel + gpio0_arsel + gpio1_arsel +
           fir_arsel + dma_arsel + defslv_arsel) !== 1'b1)
        $fatal(1, "FAIL: 块%h 选通数不为1", hi16);
    end
    $display("PASS: 地址译码全覆盖（每块恰好一个从机）");
    $finish;
  end
endmodule
