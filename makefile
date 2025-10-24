######################## Parameters#############################
# Object Verilog Files'catalog
	MODULES = ./core/cortexm0_dap/cortexm0dap.v \
			  ./core/cortexm0_integration/cortexm0_wic.v \
			  ./core/cortexm0_integration/cortexm0_systick.v \
			  ./core/cortexm0_integration/cortexm0integration.v \
			  ./core/cortexm0ds/ahb2axi4_if.v \
			  ./core/cortexm0ds/ahb2axi4_ahb.v \
			  ./core/cortexm0ds/ahb2axi4_axi.v \
			  ./core/cortexm0ds/ahb2axi4_burst.v \
			  ./core/cortexm0ds/cortexm0ds.v \
			  ./core/cortexm0ds/cortexm0ds_logic.v \
			  ./core/models/cm0_dbg_reset_sync.v \
			  ./mcu_system/cmsdk_axi_gpio/cmsdk_axi_gpio.v \
			  ./mcu_system/cmsdk_axi_gpio/cmsdk_axi_to_iop.v \
			  ./mcu_system/cmsdk_axi_gpio/cmsdk_iop_gpio.v \
			  ./mcu_system/cmsdk_axi_memory/cmsdk_axi_flash.v \
			  ./mcu_system/cmsdk_axi_memory/cmsdk_axi_sram.v \
			  ./mcu_system/cmsdk_axi_memory/cmsdk_axi_ram_beh.v \
			  ./mcu_system/cmsdk_axi_slave_mux/cmsdk_axi_addr_decode.v \
			  ./mcu_system/cmsdk_axi_slave_mux/cmsdk_axi_slave_mux.v \
			  ./mcu_system/cmsdk_axi2apb_subsystem/cmsdk_axi2apb_subsystem.v \
			  ./mcu_system/cmsdk_axi2apb_subsystem/cmsdk_apb_test_slave.v \
			  ./mcu_system/cmsdk_axi2apb_subsystem/cmsdk_irq_sync.v \
			  ./mcu_system/cmsdk_axi_to_apb/axi2apb_if.v \
			  ./mcu_system/cmsdk_axi_to_apb/axi2apb_axi.v \
			  ./mcu_system/cmsdk_axi_to_apb/axi2apb_apb.v \
			  ./mcu_system/cmsdk_apb_dualtimers/cmsdk_apb_dualtimers.v \
			  ./mcu_system/cmsdk_apb_dualtimers/cmsdk_apb_dualtimers_frc.v \
			  ./mcu_system/cmsdk_apb_slave_mux/cmsdk_apb_slave_mux.v \
			  ./mcu_system/cmsdk_apb_timer/cmsdk_apb_timer.v \
			  ./mcu_system/cmsdk_apb_uart/cmsdk_apb_uart.v \
			  ./mcu_system/cmsdk_apb_watchdog/cmsdk_apb_watchdog.v \
			  ./mcu_system/cmsdk_apb_watchdog/cmsdk_apb_watchdog_frc.v \
			  ./mcu_system/cmsdk_mcu_system/cmsdk_axi_default_slave.v \
			  ./mcu_system/cmsdk_mcu_system/cmsdk_axi_sysctrl.v \
			  ./mcu_system/cmsdk_mcu_system/cmsdk_axi_sysrom_table.v \
			  ./mcu_system/cmsdk_mcu_system/cmsdk_mcu_system.v \
			  ./mcu/cmsdk_mcu.v \
			  ./mcu/cmsdk_mcu_clkctrl.v \
			  ./mcu/cmsdk_mcu_pin_mux.v \
			  ./mcu/models/cmsdk_clock_gate.v \
			  ./tb/cmsdk_clkreset.v \
			  ./tb/cmsdk_uart_capture.v \
			  ./tb/tb_cmsdk_mcu.v

#			  ./tb/test/AHB_Lite_Master_IF_B.v \
#			  ./tb/test/Master_Controller_HB.v \
#			  ./tb/test/cortexm0ds_test.v \

# Include Path ===============
	INCPATH = -I./core/cortexm0ds/ \
			  -I./core/cortexm0_integration/ \
			  -I./core/cortexm0_dap/ \
			  -I./core/models/ \
			  -I./mcu_system/cmsdk_axi_to_apb/ \
			  -I./mcu_system/cmsdk_axi_memory/ \
			  -I./mcu_system/cmsdk_apb_dualtimers \
			  -I./mcu_system/cmsdk_apb_watchdog \
			  -I./mcu/ \
			  -I./tb/
	
# Top level module ===============
	TopModule = tb_cmsdk_mcu

# elf File's name(.out) 
	ElfFile = run.out
	
# wave File's name(.vcd .gtkw)
	VcdFile = ../../../../../../Download/wave2.vcd
	GtkwFile = signal.gtkw
	
################################################################

# make all
all: compile run wave

# only make compile
compile:
	iverilog -o $(ElfFile) -s $(TopModule) $(INCPATH) $(MODULES)
	
# only make visual(make .elf file to the vcd file)
run:
	vvp -n $(ElfFile)

# only open the wave
wave:
	gtkwave $(VcdFile) $(GtkwFile)

# clear middle files
clean:
	rm -rf *.out