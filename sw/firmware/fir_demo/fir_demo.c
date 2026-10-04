// fir_demo.c : 初赛/决赛演示固件
// 流程：UART2横幅 → UART0回显64字符 → 6通道DMA自检（含中断） →
//       FIR软硬协同（CPU配系数+DMA搬输入/收输出）→ 结束
// 指标（吞吐/延迟/带宽）由TB侧监视FIR从机握手统计，固件不打印周期。
//
// 与计划原文的偏离（见SDD台账）：
// 1. 不用fir_ref.h的double FIR重算——M0软浮点跑82x1024次乘加仿真不可接受。
//    误差校验在TB侧完成：TB读SRAM的out_buf与任务5黄金模型golden_q31.hex
//    逐样本比对并断言相对误差<0.1%（RTL级误差验证已由T6/T7/T8黄金回归
//    严格覆盖）。固件CPU侧的长循环校验实测会触发CPU停发取指
//    （无LOCKUP/HALT/SLEEP，多次形态二分未定位根因，见台账），故避开。
// 2. DMA中断在IRQ15（CMSDK_CM0.h: DMA_IRQn=15，官方axi2apb注释[15]=DMA槽位）；
//    startup向量表该槽符号名是DMA_Handler（lst实测0x7C槽），以此命名。
// 3. UART0回显用3.125M波特（BAUDDIV=16，正常模式非HSTM），BFM同波特。
// 4. FIR输入打包为int32数组（低16位=Q1.15样本），DMA FIXED_DST按FSIZE=2
//    （4字节/拍，整字=1样本）送fir_top DIN（其取W_DATA[15:0]作样本）。
//    不能用FSIZE=1：2字节/拍会把高16位零当作独立拍，样本流被零交错
//    破坏（静音段看不出来，正弦/噪声段输出全错，实测定位）。
// 5. stdout全用UartPutc级手工输出——newlib printf的__sfvwrite_r在M0上
//    极慢（实测每行打印毫秒级），且UartEndSimulation的while(STATE&1)
//    在HSTM下可能死等TXFULL，均绕开。
#include "CMSDK_CM0.h"
#include "core_cm0.h"
#include "uart_stdout.h"
#include "fir_golden.h"

#define FIR_BASE   0x40020000u
#define FIR_CTRL   (*(volatile unsigned int *)(FIR_BASE + 0x00))
#define FIR_STATUS (*(volatile unsigned int *)(FIR_BASE + 0x04))
#define FIR_DIN    (*(volatile unsigned int *)(FIR_BASE + 0x08))
#define FIR_DOUT   (*(volatile unsigned int *)(FIR_BASE + 0x0C))
#define FIR_COEF(n) (*(volatile unsigned int *)(FIR_BASE + 0x10 + 4*(n)))

#define DMA_BASE   0x40030000u
#define DMA_CH(n,off) (*(volatile unsigned int *)(DMA_BASE + 0x20*(n) + (off)))
#define DMA_INT_STATUS (*(volatile unsigned int *)(DMA_BASE + 0x100))
#define DMA_INT_CLR    (*(volatile unsigned int *)(DMA_BASE + 0x104))

#define UART0_BASE 0x40004000u
#define UART0_DATA  (*(volatile unsigned int *)(UART0_BASE + 0x00))
#define UART0_STATE (*(volatile unsigned int *)(UART0_BASE + 0x04))
#define UART0_CTRL  (*(volatile unsigned int *)(UART0_BASE + 0x08))
#define UART0_BAUDDIV (*(volatile unsigned int *)(UART0_BASE + 0x10))

#define DMA_IRQn 15u          /* CMSDK_CM0.h: DMA_IRQn=15（axi2apb注释[15]=DMA槽位） */

volatile unsigned int g_dma_irqs = 0;

/* DMA中断处理（IRQ15） */
void DMA_Handler(void)
{
    unsigned int st = DMA_INT_STATUS;
    DMA_INT_CLR = st;
    g_dma_irqs |= st;
}

/* UART0轮询收发（回显测试用；STATE位：bit0=TXFULL bit1=RXFULL） */
static int uart0_rx_full(void) { return (UART0_STATE & 0x2u) != 0; }
static int uart0_tx_full(void) { return (UART0_STATE & 0x1u) != 0; }
static char uart0_getc(void)  { return (char)UART0_DATA; }
static void uart0_putc(char c) { while (uart0_tx_full()); UART0_DATA = (unsigned int)c; }

/* stdout手工输出（绕开newlib printf，见头注释5） */
static void uart_puts(const char *s)
{
    while (*s) UartPutc(*s++);
}
static void uart_put_hex(unsigned int v)
{
    unsigned int i, d;
    for (i = 0; i < 8; i++) {
        d = (v >> (28 - 4 * i)) & 0xFu;
        UartPutc((char)(d < 10 ? '0' + d : 'a' + d - 10));
    }
}
static void uart_put_dec(unsigned int v)
{
    char buf[10];
    int n = 0;
    do { buf[n++] = (char)('0' + (v % 10)); v = v / 10; } while (v);
    while (n) UartPutc(buf[--n]);
}

/* 轮询等DMA通道集合完成：以中断handler累积的g_dma_irqs为准——
   handler会清INT_STATUS，直接轮询INT_STATUS会与handler竞争（清了永远
   等不到0x3F，实测5ms轮询超时） */
static int dma_wait(unsigned int chmask, unsigned int timeout)
{
    unsigned int t = 0;
    while (((g_dma_irqs & chmask) != chmask) && (t < timeout)) t++;
    if (t >= timeout) return -1;
    return 0;
}

int main(void)
{
    static unsigned int in_buf[FIR_N];       /* 低16位=Q1.15样本（DMA源，int32打包） */
    static unsigned int out_buf[FIR_N];      /* FIR Q1.31输出（DMA目的） */
    static unsigned int test_src[384];       /* 自检源：冻结图案6×256B */
    static volatile unsigned int *d;
    unsigned int i;
    int ok, w;

    UartStdOutInit();
    /* UART0先于横幅初始化：TB以横幅作为"UART0已就绪"握手信号，
       横幅后立即发回显字符，故BAUDDIV/CTRL必须先写完 */
    UART0_BAUDDIV = 16;
    UART0_CTRL = 0x3;                         /* TXEN|RXEN（不用HSTM） */
    uart_puts("\nFIR-SoC Demo\n");

    /* ---- 1) UART0回显：3.125M波特正常模式，回显64字符 ---- */
    for (i = 0; i < 64; i++) {
        while (!uart0_rx_full());
        uart0_putc(uart0_getc());
    }
    uart_puts("** ECHO PASS **\n");

    /* ---- 2) 6通道DMA自检：各拷256字节（源=固件冻结图案，目的0x20008000+）----
       源必须是冻结图案：早期版以.data区（0x20000000起）为源，其中含g_dma_irqs
       等活变量——DMA拷贝期间handler更新g_dma_irqs，DST快照与核对时的SRC
       终值不同，核对必然失败（布局敏感：golden_sram占位时g_dma_irqs落在
       窗口外恰好不触发；重写后其地址0x464落入ch4源窗口0x400-0x4FF） */
    for (i = 0; i < 384; i++) test_src[i] = 0xA5A50000u + i;   /* 已知图案 */
    for (i = 0; i < 6; i++) {
        DMA_CH(i, 0x00) = (unsigned int)&test_src[i * 64];     /* SRC（冻结） */
        DMA_CH(i, 0x04) = 0x20008000u + i * 256;               /* DST */
        DMA_CH(i, 0x08) = 256;                                 /* LEN字节（INCR） */
        DMA_CH(i, 0x0C) = 0x0023u;                             /* GO|IRQ_EN|BURST=1（2拍） */
    }
    NVIC_EnableIRQ((IRQn_Type)DMA_IRQn);             /* 中断演示（DMA_Handler） */
    if (dma_wait(0x3Fu, 1000000u)) {
        uart_puts("** DMA FAIL(T) irqs="); uart_put_hex(g_dma_irqs); uart_puts("\n");
        return 1;
    }
    ok = 1;
    for (i = 0; i < 6 && ok; i++) {
        d = (volatile unsigned int *)(0x20008000u + i * 256);
        for (w = 0; w < 64; w++) if (d[w] != test_src[i * 64 + w]) ok = 0;
    }
    if (!ok) {
        uart_puts("** DMA FAIL(V) irqs="); uart_put_hex(g_dma_irqs); uart_puts("\n");
        return 1;
    }
    uart_puts("** DMA PASS **\n");

    /* ---- 3) FIR软硬协同：CPU配系数 → DMA搬输入/收输出 ---- */
    FIR_CTRL = 1;                               /* CLR */
    for (i = 0; i < FIR_TAPS; i++)
        FIR_COEF(i) = (unsigned short)fir_coeff[i];
    for (i = 0; i < FIR_N; i++)
        in_buf[i] = (unsigned short)fir_input[i];    /* 低16位=样本 */

    /* 固件不用SysTick计时：官方加密核的VAL读回异常（24位计数器不可能
       出现的差值，实测打印2^32-t1垃圾），指标由TB侧监视FIR从机握手统计 */

    g_dma_irqs = 0;      /* 配置GO前清零：仅累计本次传输的完成。若在dma_wait入口
                           清零，先GO的ch0可能已done、其irq被抹掉（bit0永不出现，
                           dma_wait死等）；若完全不清，自检段的完成残留会导致
                           提前返回（读到DMA未写完的out_buf，R数据=X） */
    DMA_CH(0, 0x00) = (unsigned int)&in_buf[0];     /* SRAM→FIR DIN */
    DMA_CH(0, 0x04) = FIR_BASE + 0x08;
    DMA_CH(0, 0x08) = FIR_N;                        /* FIXED_DST：拍数 */
    DMA_CH(0, 0x0C) = 0x020Bu;                      /* GO|IRQ_EN|FIXED_DST|BURST=0|FSIZE=2(整字/拍)
                                                       BURST必须0：多拍FIXED写会填满DIN（核因DOUT满冻结）
                                                       后W_READY停等且持有DMA授权→ch1饿死→死锁（T14实证
                                                       8拍挂死；性能修复需DMA双主口，见指标记录备注） */
    /* 等ch0喂入第一拍再GO ch1：FIR的DOUT读在FIFO空时保持R_VALID=0等数据，
       若ch1先读到空FIFO，其R挂起经仲裁器R通道串行化挡住ch0的写（死锁，实测） */
    for (i = 0; (FIR_STATUS & 1u) && (i < 1000000u); i++);
    DMA_CH(1, 0x00) = FIR_BASE + 0x0C;              /* FIR DOUT→SRAM */
    DMA_CH(1, 0x04) = (unsigned int)&out_buf[0];
    DMA_CH(1, 0x08) = FIR_N;
    DMA_CH(1, 0x0C) = 0x0207u;                      /* GO|IRQ_EN|FIXED_SRC|BURST=0|FSIZE=2(4字节/拍)
                                                       BURST必须0：多拍FIXED读会追上核产出率（DOUT空）
                                                       后R_VALID停等且持有DMA授权→ch0饿死→死锁（同上） */
    if (dma_wait(0x3u, 100000000u)) { uart_puts("** FIR DMA TIMEOUT **\n"); return 1; }

    /* 误差校验与指标测量在TB侧完成（TB读SRAM的out_buf与golden_q31.hex
       比对<0.1%；吞吐/延迟/带宽由TB监视FIR从机握手统计，见T14） */
    uart_puts("out="); uart_put_hex((unsigned int)&out_buf[0]); uart_puts("\n");
    uart_puts("** FIR DONE **\n");

    /* 不需要UartEndSimulation的0x04结束符（TB按输出标记判定），
       且其while(STATE&1)在HSTM下可能死等TXFULL */
    while (1);
    return 0;
}
