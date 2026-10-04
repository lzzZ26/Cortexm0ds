# fir_demo makefile（沿袭官方 hello/makefile 的 all_gcc 流程，路径改引用仓库根）
REF       = ../../..
SOFTWARE  = $(REF)/software
DEVICE    = $(SOFTWARE)/cmsis/Device/ARM/CMSDK_CM0
CORE_DIR  = $(SOFTWARE)/cmsis/CMSIS/Include
STARTUP   = $(DEVICE)/Source/GCC/startup_CMSDK_CM0.s
SYSTEM    = $(DEVICE)/Source/system_CMSDK_CM0.c
LINKER    = $(SOFTWARE)/common/scripts/cmsdk_cm0.ld

CC        = arm-none-eabi-gcc
OBJDUMP   = arm-none-eabi-objdump
OBJCOPY   = arm-none-eabi-objcopy
TESTNAME  = fir_demo

all:
	$(CC) -g -O3 -mthumb -mcpu=cortex-m0 \
		$(STARTUP) \
		$(TESTNAME).c \
		$(SOFTWARE)/common/retarget/retarget.c \
		$(SOFTWARE)/common/retarget/uart_stdout.c \
		$(SYSTEM) \
		-I $(DEVICE)/Include -I $(CORE_DIR) \
		-I $(SOFTWARE)/common/retarget -I . \
		-L $(SOFTWARE)/common/scripts \
		-D__STACK_SIZE=0x1000 -D__HEAP_SIZE=0x1000 \
		-T $(LINKER) -o $(TESTNAME).o
	$(OBJDUMP) -S $(TESTNAME).o > $(TESTNAME).lst
	$(OBJCOPY) -S $(TESTNAME).o -O binary $(TESTNAME).bin
	$(OBJCOPY) -S $(TESTNAME).o -O verilog $(TESTNAME).hex

clean:
	rm -rf *.o *.lst *.bin *.hex
