# 编译 lualib C 扩展, 输出到 ../luaclib
CC ?= gcc
CFLAGS ?= -O2 -Wall -fPIC
LUA_INC = ../skynet/3rd/lua
OUTDIR = ../luaclib
SHARED = -shared

SRCS = skiplist.c timerwheel.c recordstore.c
TARGETS = $(addprefix $(OUTDIR)/,$(patsubst %.c,%.so,$(SRCS)))

.NOTPARALLEL:

all: $(TARGETS)

$(OUTDIR)/%.so: %.c
	$(CC) $(CFLAGS) $(SHARED) -I$(LUA_INC) $< -o $@

clean:
	rm -f $(TARGETS)

.PHONY: all clean
