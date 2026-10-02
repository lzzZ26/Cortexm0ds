# Makefile.fir —— 本项目仿真入口（官方makefile保持不动，故用独立文件名）
# 用法：mingw32-make -f Makefile.fir <目标>
MAKE ?= mingw32-make

# 官方基线（跑官方makefile的compile+run）
baseline:
	$(MAKE) compile
	vvp -n run.out | tail -5
