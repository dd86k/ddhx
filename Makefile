# Makefile alternative to DUB for ddhx
#
# Portable across GNU make and BSD makes (FreeBSD/NetBSD/OpenBSD).
# Uses `!=` for shell assignment (supported by BSD makes and GNU make >=4.0)
# instead of GNU-only `ifeq`/`endif` conditionals and `$(wildcard ...)`.

DC ?= dmd
PREFIX ?= /usr/local
BINDIR ?= $(PREFIX)/bin

SRCS != find src -name '*.d'
TEST_SRCS_INPUT = $(SRCS) tests/input.d
TEST_SRCS_COLOR = $(SRCS) tests/color.d
TEST_SRCS_SIZE  = $(SRCS) tests/size.d
BENCH_SRCS = $(SRCS) benchmark/src/main.d

# Compiler-specific flag mapping. DMD flags are the baseline; LDC and GDC
# equivalents are selected by matching $(DC) against the compiler binary name.
# Strip any directory prefix so absolute paths (e.g. /usr/pkg/gcc15/bin/gdc) match.
DC_NAME       != basename "$(DC)"
OFLAG         != case "$(DC_NAME)" in gdc*|*-gdc|*-gdc-*) echo "-o" ;; *) echo "-of=" ;; esac
RELEASE_FLAGS != case "$(DC_NAME)" in ldc2) echo "-O2 -release -boundscheck=off" ;; dmd) echo "-O -release -boundscheck=off" ;; *) echo "-O2 -frelease -fbounds-check=off" ;; esac
DEBUG_FLAGS   != case "$(DC_NAME)" in ldc2) echo "-g -d-debug" ;; dmd) echo "-g -debug" ;; *) echo "-g -fdebug" ;; esac
DEBUGV_FLAGS  != case "$(DC_NAME)" in ldc2) echo "-g -d-debug -d-version=verbose --vgc --vtls" ;; dmd) echo "-g -debug -version=verbose -vgc -vtls" ;; *) echo "-g -fdebug -fversion=verbose" ;; esac
NATIVE_FLAGS  != case "$(DC_NAME)" in ldc2) echo "-O2 -release -boundscheck=off -mcpu=native" ;; dmd) echo "-O -release -boundscheck=off -mcpu=native" ;; *) echo "-O2 -frelease -fbounds-check=off -march=native" ;; esac
STATIC_FLAG   != case "$(DC_NAME)" in ldc2) echo "--static" ;; dmd) echo "-L=-static" ;; *) echo "-Wl,-static -static -static-libgcc" ;; esac
UNITTEST_FLAG != case "$(DC_NAME)" in gdc*|*-gdc|*-gdc-*) echo "-funittest" ;; *) echo "-unittest" ;; esac
VERSION_FLAG  != case "$(DC_NAME)" in ldc2) echo "-d-version" ;; dmd) echo "-version" ;; *) echo "-fversion" ;; esac

# Default target
all: release

# Build targets
ddhx: release

release: $(SRCS)
	$(DC) $(RELEASE_FLAGS) $(OFLAG)ddhx $(SRCS)

debug: $(SRCS)
	$(DC) $(DEBUG_FLAGS) $(OFLAG)ddhx $(SRCS)

debugv: $(SRCS)
	$(DC) $(DEBUGV_FLAGS) $(OFLAG)ddhx $(SRCS)

native: $(SRCS)
	$(DC) $(NATIVE_FLAGS) $(OFLAG)ddhx $(SRCS)

# Static build targets
debug-static: $(SRCS)
	$(DC) $(DEBUG_FLAGS) $(VERSION_FLAG)=Static $(STATIC_FLAG) $(OFLAG)ddhx $(SRCS)

release-static: $(SRCS)
	$(DC) $(RELEASE_FLAGS) $(VERSION_FLAG)=Static $(STATIC_FLAG) $(OFLAG)ddhx $(SRCS)

native-static: $(SRCS)
	$(DC) $(NATIVE_FLAGS) $(VERSION_FLAG)=Static $(STATIC_FLAG) $(OFLAG)ddhx $(SRCS)

# Benchmark
benchmark: $(BENCH_SRCS)
	$(DC) $(RELEASE_FLAGS) $(OFLAG)ddhx-benchmark $(BENCH_SRCS)

# Tests
test: $(SRCS)
	$(DC) $(DEBUG_FLAGS) $(UNITTEST_FLAG) $(OFLAG)ddhx-test-library $(SRCS)
	./ddhx-test-library

test-input: $(TEST_SRCS_INPUT)
	$(DC) $(DEBUG_FLAGS) $(UNITTEST_FLAG) $(VERSION_FLAG)=TestInput $(OFLAG)ddhx-test-library $(TEST_SRCS_INPUT)
	./ddhx-test-library

test-color: $(TEST_SRCS_COLOR)
	$(DC) $(DEBUG_FLAGS) $(UNITTEST_FLAG) $(VERSION_FLAG)=TestColor $(OFLAG)ddhx-test-library $(TEST_SRCS_COLOR)
	./ddhx-test-library

test-size: $(TEST_SRCS_SIZE)
	$(DC) $(DEBUG_FLAGS) $(UNITTEST_FLAG) $(VERSION_FLAG)=TestSize $(OFLAG)ddhx-test-library $(TEST_SRCS_SIZE)
	./ddhx-test-library

# Install/uninstall
install: release
	install -d $(DESTDIR)$(BINDIR)
	install -m 755 ddhx $(DESTDIR)$(BINDIR)/ddhx

uninstall:
	rm -f $(DESTDIR)$(BINDIR)/ddhx

# Clean
clean:
	rm -f ddhx ddhx.o libddhx.a ddhx-benchmark ddhx-test-library ddhx-test-library.o

.PHONY: all ddhx release debug debugv native \
	debug-static release-static native-static \
	benchmark test test-input test-color test-size \
	install uninstall clean
