#=======================================================================
# UCB CS250 Makefile fragment for benchmarks
#-----------------------------------------------------------------------
#
# Each benchmark directory should have its own fragment which 
# essentially lists what the source files are and how to link them
# into an riscv and/or host executable. All variables should include 
# the benchmark name as a prefix so that they are unique.
#

fib_c_src = \
	fib.c \
	syscalls.c \

fib_riscv_src = \
	crt.S \

fib_c_objs     = $(patsubst %.c, %.o, $(fib_c_src))
fib_riscv_objs = $(patsubst %.S, %.o, $(fib_riscv_src))


fib_host_bin = fib.host
$(fib_host_bin): $(fib_c_src)
	$(HOST_COMP) $^ -o $(bmarks_build_bin_dir)/$(fib_host_bin)

fib_riscv_bin = fib.riscv
$(fib_riscv_bin): $(fib_c_objs) $(fib_riscv_objs)
	cd $(bmarks_build_obj_dir); $(RISCV_LINK) $(fib_c_objs) $(fib_riscv_objs) -o $(bmarks_build_bin_dir)/$(fib_riscv_bin) $(RISCV_LINK_OPTS)

