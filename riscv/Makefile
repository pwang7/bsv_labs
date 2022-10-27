TMPDIR = tmpDir
SRCDIR = $(abspath ./src)
SIMDIR = -simdir $(TMPDIR) -bdir $(TMPDIR) -info-dir $(TMPDIR) -vdir $(TMPDIR)
BSCFLAGS = -u -aggressive-conditions -keep-fires -show-schedule
BSVDIR = -p $(SRCDIR)/includes:$(SRCDIR):+

.PHONY: clean compile
.DEFAULT_GOAL := compile

compile:
	mkdir -p $(TMPDIR)
	bsc $(BSCFLAGS) -sim $(SIMDIR) $(BSVDIR) -g mkProc $(SRCDIR)/OneCycle.bsv

clean:
	rm -rf $(TMPDIR) sim*
