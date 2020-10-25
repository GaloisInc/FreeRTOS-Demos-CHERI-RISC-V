RISCV_XLEN ?= 64
RISCV_LIB  ?= elf
CCPATH =

configCPU_CLOCK_HZ ?=
configPERIPH_CLOCK_HZ ?=
configMTIME_HZ ?=

BSP ?= spike-rv32imac-ilp32
BSP_CONFIGS = $(word $2,$(subst -, ,$(BSP)))

PLATFORM ?=$(call BSP_CONFIGS,$*,1)
ARCH ?=$(call BSP_CONFIGS,$*,2)
ABI ?=$(call BSP_CONFIGS,$*,3)

MEM_START?=0x80000000

TARGET =$(CCPATH)riscv${RISCV_XLEN}-unknown-${RISCV_LIB}

TOOLCHAIN ?=gcc
SYSROOT   ?=
LIBS_PATH ?=
CFLAGS    ?=
LDFLAGS   ?=
LIBS      ?=
COMPARTMENTS = comp1.wrapped.o comp2.wrapped.o
CFLAGS = -DconfigCOMPARTMENTS_NUM=2

CFLAGS += -DconfigMAXLEN_COMPNAME=32

CFLAGS += -D__freertos__=1

EXTENSION ?=
CHERI_CLEN ?= 2*$(RISCV_XLEN)
# CHERI is only supported by LLVM/Clang
ifeq ($(EXTENSION),cheri)
TOOLCHAIN = llvm
endif

ifeq ($(TOOLCHAIN),llvm)
CC      = clang -target $(TARGET)
GCC     = $(TARGET)-$(CC)
OBJCOPY = llvm-objcopy
OBJDUMP = llvm-objdump
AR      = llvm-ar
RANLIB  = llvm-ranlib
CFLAGS  += -mno-relax -mcmodel=medium --sysroot=$(SYSROOT)
LDFLAGS += --sysroot=$(SYSROOT) -lclang_rt.builtins-riscv$(RISCV_XLEN)
LIBS	  += -lc
else
CC       = $(TARGET)-gcc
OBJCOPY  = $(TARGET)-objcopy
OBJDUMP  = $(TARGET)-objdump
AR       = $(TARGET)-ar
RANLIB   = $(TARGET)-ranlib
LIBS    += -lc -lgcc
CFLAGS  += -mcmodel=medany
LDFLAGS =
endif

# Use main_blinky as demo source and target file name if not specified
PROG 	?= main_blinky
PLATFORM ?= spike
CRT0	= bsp/boot.S

# For debugging
$(info $$PROG is [${PROG}])

FREERTOS_SOURCE_DIR	= ../../Source
FREERTOS_PLUS_SOURCE_DIR = ../../../FreeRTOS-Plus/Source
FREERTOS_TCP_SOURCE_DIR = $(FREERTOS_PLUS_SOURCE_DIR)/FreeRTOS-Plus-TCP
FREERTOS_PROTOCOLS_DIR = ./protocols

WARNINGS= -Wall -Wextra -Wshadow -Wpointer-arith -Wbad-function-cast -Wcast-align -Wsign-compare \
		-Waggregate-return -Wstrict-prototypes -Wmissing-prototypes -Wmissing-declarations -Wunused


# Root of RISC-V tools installation
RISCV ?= /opt/riscv

FREERTOS_SRC = \
	$(FREERTOS_SOURCE_DIR)/croutine.c \
	$(FREERTOS_SOURCE_DIR)/list.c \
	$(FREERTOS_SOURCE_DIR)/queue.c \
	$(FREERTOS_SOURCE_DIR)/tasks.c \
	$(FREERTOS_SOURCE_DIR)/timers.c \
	$(FREERTOS_SOURCE_DIR)/event_groups.c \
	$(FREERTOS_SOURCE_DIR)/stream_buffer.c \
	$(FREERTOS_SOURCE_DIR)/portable/MemMang/heap_4.c # TODO TEST

APP_SOURCE_DIR	= ../Common/Minimal

PORT_SRC = $(FREERTOS_SOURCE_DIR)/portable/GCC/RISC-V/port.c
ifeq ($(EXTENSION),cheri)
PORT_ASM = $(FREERTOS_SOURCE_DIR)/portable/GCC/RISC-V/chip_specific_extensions/CHERI/portASM.S
else
PORT_ASM = $(FREERTOS_SOURCE_DIR)/portable/GCC/RISC-V/portASM.S
endif

INCLUDES = \
	-I. \
	-I./bsp \
	-I$(FREERTOS_SOURCE_DIR)/include \
	-I../Common/include \
	-I$(FREERTOS_SOURCE_DIR)/portable/GCC/RISC-V

ASFLAGS  += -g -march=$(ARCH) -mabi=$(ABI)  -Wa,-Ilegacy -I$(FREERTOS_SOURCE_DIR)/portable/GCC/RISC-V/chip_specific_extensions/RV32I_CLINT_no_extensions -DportasmHANDLE_INTERRUPT=external_interrupt_handler \
	-DconfigPORT_ALLOW_APP_EXCEPTION_HANDLERS=1

CFLAGS += $(WARNINGS) $(INCLUDES)
CFLAGS += -g -O0 -march=$(ARCH) -mabi=$(ABI)

DEMO_SRC = main.c \
	demo/$(PROG).c

APP_SRC = \
	bsp/bsp.c \
	bsp/plic_driver.c \
	bsp/syscalls.c \

FREERTOS_LIBDL_DIR = ../../../FreeRTOS-Labs/Source/FreeRTOS-libdl

LIBDL_SRC = $(FREERTOS_LIBDL_DIR)/libdl/dlfcn.c \
            $(FREERTOS_LIBDL_DIR)/libdl/fastlz.c \
            $(FREERTOS_LIBDL_DIR)/libdl/rtl-alloc-heap.c \
            $(FREERTOS_LIBDL_DIR)/libdl/rtl-allocator.c \
            $(FREERTOS_LIBDL_DIR)/libdl/rtl-alloc-lock.c \
            $(FREERTOS_LIBDL_DIR)/libdl/rtl-bit-alloc.c \
            $(FREERTOS_LIBDL_DIR)/libdl/rtl-chain-iterator.c \
            $(FREERTOS_LIBDL_DIR)/libdl/rtl-elf.c \
            $(FREERTOS_LIBDL_DIR)/libdl/rtl-error.c \
            $(FREERTOS_LIBDL_DIR)/libdl/rtl-mdreloc-riscv.c \
            $(FREERTOS_LIBDL_DIR)/libdl/rtl-obj-cache.c \
            $(FREERTOS_LIBDL_DIR)/libdl/rtl-obj-comp.c \
            $(FREERTOS_LIBDL_DIR)/libdl/rtl-obj.c \
            $(FREERTOS_LIBDL_DIR)/libdl/rtl-string.c \
            $(FREERTOS_LIBDL_DIR)/libdl/rtl-sym.c \
            $(FREERTOS_LIBDL_DIR)/libdl/rtl-trace.c \
            $(FREERTOS_LIBDL_DIR)/libdl/rtl-unresolved.c \
            $(FREERTOS_LIBDL_DIR)/libdl/rtl-unwind-dw2.c \
            $(FREERTOS_LIBDL_DIR)/libdl/rtl-freertos-compartments.c \
            $(FREERTOS_LIBDL_DIR)/libdl/rtl.c
CFLAGS += -I$(FREERTOS_LIBDL_DIR)/include

FREERTOS_LIBCHERI_DIR = ../../../FreeRTOS-Labs/Source/FreeRTOS-libcheri
LIBCHERI_SRC = $(FREERTOS_LIBCHERI_DIR)/cheri/cheri-riscv.c

FREERTOS_IP_SRC = \
    $(FREERTOS_TCP_SOURCE_DIR)/FreeRTOS_IP.c \
    $(FREERTOS_TCP_SOURCE_DIR)/FreeRTOS_ARP.c \
    $(FREERTOS_TCP_SOURCE_DIR)/FreeRTOS_DHCP.c \
    $(FREERTOS_TCP_SOURCE_DIR)/FreeRTOS_DNS.c \
    $(FREERTOS_TCP_SOURCE_DIR)/FreeRTOS_Sockets.c \
    $(FREERTOS_TCP_SOURCE_DIR)/FreeRTOS_TCP_IP.c \
    $(FREERTOS_TCP_SOURCE_DIR)/FreeRTOS_UDP_IP.c \
    $(FREERTOS_TCP_SOURCE_DIR)/FreeRTOS_TCP_WIN.c \
    $(FREERTOS_TCP_SOURCE_DIR)/FreeRTOS_Stream_Buffer.c \
    $(FREERTOS_TCP_SOURCE_DIR)/portable/BufferManagement/BufferAllocation_2.c \
    $(FREERTOS_TCP_SOURCE_DIR)/portable/NetworkInterface/virtio/NetworkInterface.c \
    bsp/rand.c

FREERTOS_IP_INCLUDE = \
    -I$(FREERTOS_TCP_SOURCE_DIR) \
    -I$(FREERTOS_TCP_SOURCE_DIR)/include \
    -I$(FREERTOS_TCP_SOURCE_DIR)/portable/Compiler/GCC

FREERTOS_LIBVIRTIO_DIR = ../../../FreeRTOS-Labs/Source/FreeRTOS-libvirtio
LIBVIRTIO_SRC = \
   $(FREERTOS_LIBVIRTIO_DIR)/virtio.c \
   $(FREERTOS_LIBVIRTIO_DIR)/virtio-net.c \
   $(FREERTOS_LIBVIRTIO_DIR)/helpers.c

LIBVIRTIO_INCLUDE = -I$(FREERTOS_LIBVIRTIO_DIR)

FREERTOS_IP_DEMO_SRC = \
    demo/TCPEchoClient_SingleTasks.c \
    demo//SimpleUDPClientAndServer.c \
    demo/SimpleTCPEchoServer.c

ifeq ($(EXTENSION),cheri)
DEMO_SRC += $(LIBCHERI_SRC)
CFLAGS += -I$(FREERTOS_LIBCHERI_DIR)/include
CFLAGS += -Werror=cheri-prototypes
endif

ifeq ($(PROG),main_blinky)
	CFLAGS += -DmainDEMO_TYPE=1
else
ifeq ($(PROG),main_tests)
	CFLAGS += -DmainDEMO_TYPE=3
else
ifeq ($(PROG),main_compartment_test)
	CFLAGS += -DmainDEMO_TYPE=4
DEMO_SRC += demo/compartments/loader.c
DEMO_SRC += comp_strtab_generated.c
DEMO_SRC += $(LIBDL_SRC)

else
ifeq ($(PROG),main_peekpoke)
	CFLAGS += -DmainDEMO_TYPE=5
    CFLAGS += -DmainCREATE_PEEKPOKE_SERVER_TASK=1
    CFLAGS += -DmainCREATE_HTTP_SERVER=1
    CFLAGS += -DipconfigUSE_HTTP=1
    CFLAGS += '-DconfigHTTP_ROOT="/notused"'
    CFLAGS += -DffconfigMAX_FILENAME=4096
    INCLUDES += \
        $(FREERTOS_IP_INCLUDE) \
        -I$(FREERTOS_PROTOCOLS_DIR)/include
    FREERTOS_SRC += \
        $(FREERTOS_IP_SRC) \
        $(FREERTOS_PROTOCOLS_DIR)/Common/FreeRTOS_TCP_server.c \
        $(FREERTOS_PROTOCOLS_DIR)/HTTP/FreeRTOS_HTTP_server.c \
        $(FREERTOS_PROTOCOLS_DIR)/HTTP/FreeRTOS_HTTP_commands.c \
        $(FREERTOS_PROTOCOLS_DIR)/HTTP/peekpoke.c
    DEMO_SRC += $(FREERTOS_IP_DEMO_SRC)

else
	$(info unknown demo: $(PROG))
endif # main_blinky
endif # main_tests
endif # main_compartment_test
endif # main_tcpip

# PLATFORM Variants
ifeq ($(PLATFORM),spike)
	CFLAGS += -DPLATFORM_SPIKE=1
	APP_SRC += bsp/htif.c
else
ifeq ($(PLATFORM),piccolo)
	CFLAGS += -DPLATFORM_PICCOLO=1
	APP_SRC += bsp/uart16550.c
else
ifeq ($(PLATFORM),sail)
	CFLAGS += -DPLATFORM_SAIL=1
	APP_SRC += bsp/htif.c
else
ifeq ($(PLATFORM),qemu_virt)
	CFLAGS += -DPLATFORM_QEMU_VIRT=1
	CFLAGS += -DVTNET_LEGACY_TX=1
	CFLAGS += -DVIRTIO_USE_MMIO=1
	APP_SRC += bsp/uart16550.c
	APP_SRC += bsp/sifive_test.c
	FREERTOS_SRC += $(LIBVIRTIO_SRC)
	INCLUDES += $(LIBVIRTIO_INCLUDE)
else
ifeq ($(PLATFORM),rvbs)
	CFLAGS += -DPLATFORM_RVBS=1
else
ifeq ($(PLATFORM),gfe)
	CFLAGS += -DPLATFORM_GFE=1
MEM_START=0xC0000000
APP_SRC += \
	bsp/uart16550.c
else
	$(info unknown platform: $(PLATFORM))
endif
endif
endif
endif
endif
endif

ifeq ($(EXTENSION),cheri)
	CFLAGS += -DCONFIG_ENABLE_CHERI=1
	CFLAGS += -DCONFIG_CHERI_CLEN=$(CHERI_CLEN)
endif

ARFLAGS=crsv

# If configCPU_CLOCK_HZ is not empty, pass it as a definition
ifneq ($(configCPU_CLOCK_HZ),)
CFLAGS += -DconfigCPU_CLOCK_HZ=$(configCPU_CLOCK_HZ)
endif
# If configMTIME_HZ is not empty, pass it as a definition
ifneq ($(configMTIME_HZ),)
CFLAGS += -DconfigMTIME_HZ=$(configMTIME_HZ)
endif
# If configPERIPH_CLOCK_HZ is not empty, pass it as a definition
ifneq ($(configPERIPH_CLOCK_HZ),)
CFLAGS += -DconfigPERIPH_CLOCK_HZ=$(configPERIPH_CLOCK_HZ)
endif

CFLAGS += $(WARNINGS) $(INCLUDES)
CFLAGS += -O0 -g -march=$(ARCH) -mabi=$(ABI)

#
# Define all object files.
#
RTOS_OBJ = $(FREERTOS_SRC:.c=.o)
APP_OBJ  = $(APP_SRC:.c=.o)
PORT_OBJ = $(PORT_SRC:.c=.o)
DEMO_OBJ = $(DEMO_SRC:.c=.o)
PORT_ASM_OBJ = $(PORT_ASM:.S=.o)
CRT0_OBJ = $(CRT0:.S=.o)
OBJS = $(CRT0_OBJ) $(PORT_ASM_OBJ) $(PORT_OBJ) $(RTOS_OBJ) $(DEMO_OBJ) $(APP_OBJ)

LDFLAGS	+= -T link.ld.generated -nostartfiles -nostdlib -Wl,--defsym=MEM_START=$(MEM_START) -defsym=_STACK_SIZE=4K -march=$(ARCH) -mabi=$(ABI)

$(info ASFLAGS=$(ASFLAGS))
$(info LDLIBS=$(LDLIBS))
$(info CFLAGS=$(CFLAGS))
$(info LDFLAGS=$(LDFLAGS))
$(info ARFLAGS=$(ARFLAGS))

%.o: %.c
	@echo "    CC $<"
	@$(CC) -c $(CFLAGS) -o $@ $<

%.o: %.S
	@echo "    CC $<"
	@$(CC) $(ASFLAGS) -c $(CFLAGS) -o $@ $<

all: $(PROG).elf

gen_freertos_header:
	@echo Generating FreeRTOSConfig.h header for $(PLATFORM) platform
	@sed -e 's/PLATFORM/$(PLATFORM)/g' < FreeRTOSConfig.h.in > FreeRTOSConfig.h

$(PROG).elf  : gen_freertos_header $(OBJS) Makefile
	@echo Building FreeRTOS/RISC-V for PLATFORM=$(PLATFORM) ARCH=$(ARCH) ABI=$(ABI)
	@echo Linking....
	@echo $(CFLAGS) > comp.cflags
	$(CC) -o $@ -fuse-ld=lld $(LDFLAGS) $(OBJS) $(LIBS) -v
	#@$(OBJDUMP) -S $(PROG).elf > $(PROG).asm
	@echo Completed $@

clean :
	@rm -f $(OBJS)
	@rm -f $(PROG).elf
	@rm -f $(PROG).map
	@rm -f $(PROG).asm