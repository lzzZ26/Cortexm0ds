# Makefile.fir —— 本项目仿真入口（官方makefile保持不动，故用独立文件名）
# 用法：mingw32-make -f Makefile.fir <目标>
MAKE ?= mingw32-make

# 官方基线（跑官方makefile的compile+run）
baseline:
	$(MAKE) compile
	vvp -n run.out | tail -5

IV     = iverilog
VVP    = vvp
TB_DIR = tb
OUT    = sim_out
RTL    = rtl/ic/ic_axi_master_arb.v rtl/ic/ic_axi_addr_decode.v

$(OUT):
	mkdir -p $(OUT)

# 用法: make sim_tb_vip_smoke  （编译+运行，自检失败即非零退出）
sim_%: $(OUT)
	$(IV) -g2001 -o $(OUT)/$*.vvp -s $* -I$(TB_DIR)/common $(TB_DIR)/$*.v \
	     $(TB_DIR)/common/axi_master_vip.v $(TB_DIR)/common/axi_slave_mem.v \
	     $(TB_DIR)/common/axi_checker.v $(TB_DIR)/common/uart_bfm.v \
	     $(TB_DIR)/common/tb_clkreset.v $(RTL)
	$(VVP) -n $(OUT)/$*.vvp
