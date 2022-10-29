BSVBASEDIR=$(abspath ..)
BASEDIR=$(abspath .)
CONNECTALDIR=$(abspath ../../connectal)

# Define HW->SW / SW->HW interfaces
S2H_INTERFACES = MyDutRequest:MyDut.request
H2S_INTERFACES = MyDut:MyDutIndication

# FILES
BSVFILES = MyDut.bsv
CPPFILES = connectal_test.cpp
# BSVDIR = $(BSVBASEDIR)/common:$(BSVBASEDIR)/fft:$(BSVBASEDIR)/fir:$(BSVBASEDIR)/pitch
BSVDIR = $(BSVBASEDIR)/common

# Connectal Flags
CONNECTALFLAGS += --mainclockperiod 15
CONNECTALFLAGS += --bsvpath $(BSVDIR) --bscflags " -u --keep-fires -aggressive-conditions -show-schedule "

PITCH_SHIFT_FACTOR = 2.0 # The pitch shift factor

include $(CONNECTALDIR)/Makefile.connectal

.PHONY: simulation fpga fpgaUpdateSW run_simulation run_fpga program_fpga run_fpgaSW
.DEFAULT_GOAL := simulation

simulation:
	rm -rf $(BASEDIR)/bluesim
	$(MAKE) build.bluesim

fpga:
	rm -rf $(BASEDIR)/vc707g2
	$(MAKE) build.vc707g2

fpgaUpdateSW:
	rm -f $(BASEDIR)/vc707g2/bin/ubuntu.exe $(BASEDIR)/vc707g2/jni/ubuntu.exe
	make -C $(BASEDIR)/vc707g2 ubuntu.exe

run_simulation:
	cp ../data/mitrib.pcm in.pcm
	$(BASEDIR)/bluesim/bin/ubuntu.exe $(PITCH_SHIFT_FACTOR)
	cmp out.pcm ../data/mitrib_pa8_2_2.pcm
#	$(BASEDIR)/bluesim/bin/ubuntu.exe ${ARG1}

run_fpga:
	lockfile -5 -r 3 -l 120 -s 2 /tmplock/fpgalock
	$(BASEDIR)/vc707g2/bin/ubuntu.exe ${ARG1}
	rm -f /tmplock/fpgalock

program_fpga:
	lockfile -5 -r 3 -l 120 -s 2 /tmplock/fpgalock
	fpgajtag $(BASEDIR)/vc707g2/bin/mkTop.bin.gz
	rm -f /tmplock/fpgalock

run_fpgaSW:
	lockfile -5 -r 3 -l 120 -s 2 /tmplock/fpgalock
	NOPROGRAM=1 $(BASEDIR)/vc707g2/bin/ubuntu.exe ${ARG1}
	rm -f /tmplock/fpgalock

