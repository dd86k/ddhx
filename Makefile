# Makefile alternative to DUB for ddhx

DC ?= dmd
PREFIX ?= /usr/local
BINDIR ?= $(PREFIX)/bin

SRCS = $(wildcard src/*.d src/**/*.d src/ddhx/**/*.d)
TEST_SRCS_INPUT = $(SRCS) tests/input.d
TEST_SRCS_COLOR = $(SRCS) tests/color.d
TEST_SRCS_SIZE = $(SRCS) tests/size.d
BENCH_SRCS = $(SRCS) benchmark/src/main.d

# Compiler-specific flag mapping
# DMD flags are the baseline; LDC and GDC equivalents are mapped below.
ifeq ($(DC),ldc2) # LLVM D Compiler
	OFLAG = -of=
	RELEASE_FLAGS = -O2 -release -boundscheck=off
	DEBUG_FLAGS = -g -d-debug
	DEBUGV_FLAGS = -g -d-debug -d-version=verbose --vgc --vtls
	NATIVE_FLAGS = -O2 -release -boundscheck=off -mcpu=native
	STATIC_FLAG = --static
	UNITTEST_FLAG = -unittest
	VERSION_FLAG = -d-version
else ifeq ($(DC),dmd) # DigitalMars D compiler
	OFLAG = -of=
	RELEASE_FLAGS = -O -release -boundscheck=off
	DEBUG_FLAGS = -g -debug
	DEBUGV_FLAGS = -g -debug -version=verbose -vgc -vtls
	NATIVE_FLAGS = -O -release -boundscheck=off -mcpu=native
	STATIC_FLAG = -L=-static
	UNITTEST_FLAG = -unittest
	VERSION_FLAG = -version
else # GNU D Compiler (allows gdc-* invocation)
	OFLAG = -o
	RELEASE_FLAGS = -O2 -frelease -fbounds-check=off
	DEBUG_FLAGS = -g -fdebug
	DEBUGV_FLAGS = -g -fdebug -fversion=verbose
	NATIVE_FLAGS = -O2 -frelease -fbounds-check=off -march=native
	STATIC_FLAG = -Wl,-static -static -static-libgcc
	UNITTEST_FLAG = -funittest
	VERSION_FLAG = -fversion
endif

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
