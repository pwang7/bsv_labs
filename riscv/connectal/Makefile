CONNECTALDIR ?= $(abspath ../../connectal-master)
BSVBASEDIR = $(abspath ..)/src
BASEDIR = $(abspath .)

# Define HW->SW / SW->HW interfaces
# S2H_INTERFACES = MyDutRequest:MyDut.request
S2H_INTERFACES = \
	StartRequest:MyDut.start \
	MemInitRequest:MyDut.init
H2S_INTERFACES = MyDut:MyDutIndication

# FILES
CPPFILES = Main.cpp Platform.cpp
BSVFILES = MyDut.bsv
BSVDIR = $(BSVBASEDIR):$(BSVBASEDIR)/includes

export SOFTWARE_SOCKET_NAME=/tmp/connectal$(USER)

# Connectal Flags
CONNECTALFLAGS += -D $(VPROC) --bsvpath $(BSVDIR)
CONNECTALFLAGS += --bscflags " -D $(VPROC) -steps-max-intervals 50 +RTS -K256M -RTS"
CONNECTALFLAGS += --bscflags " -u -keep-fires -aggressive-conditions -show-schedule "
CONNECTALFLAGS += -D IMPORT_HOSTIF -D XILINX_SYS_CLK
CONNECTALFLAGS += --mainclockperiod 15

# PIN_TYPE = Top_Pins
# PIN_TYPE_INCLUDE = Ifc
# AUTOTOP = --interface pins:ConnectalWrapper.pins

include $(CONNECTALDIR)/Makefile.connectal

.PHONY: simulation clean run_simulation
.DEFAULT_GOAL := simulation

run_simulation:
	ls ../programs/build/*/bin/*.riscv | xargs -I % sh -c "echo % && cp % ./program && bluesim/bin/ubuntu.exe"

simulation:
	rm -rf $(BASEDIR)/bluesim
	$(MAKE) build.bluesim

clean:
	rm -rf bluesim program
