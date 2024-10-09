TARGET=bob
CPUOPT=-m68060 -mno-bitfield 

VBCC ?= /opt/amiga
GCC ?= $(VBCC)/bin/m68k-amigaos-gcc
GPP ?= $(VBCC)/bin/m68k-amigaos-g++
VLINK ?= $(VBCC)/bin/vlink
STRIP ?= $(VBCC)/bin/m68k-amigaos-strip
OBJCOPY ?= $(VBCC)/bin/m68k-amigaos-objcopy
CFLAGS := $(CPUOPT) -Wstack-usage=3000 -mregparm=4 -Wno-deprecated -O2 -noixemul -fomit-frame-pointer -MMD
INCLUDE ?= -I $(VBCC)/m68k-amigaos/ndk-include/
VASM ?= $(VBCC)/bin/vasmm68k_mot
VASM_FLAGS := -Fhunk -kick1hunks -quiet -m68020 -nosym $(INCLUDE)

all: $(TARGET) 

clean:
	rm -f $(TARGET) $(TARGET).sym *.o
        
libcRSID.o: libcRSID.c 
	$(GCC) -c $< -o $@ $(CFLAGS)

glue.o: glue.c 
	$(GCC) -c $< -o $@ $(CFLAGS)

testAudio.o: testAudio.s 
	$(VASM) $< -o $@  $(VASM_FLAGS)

$(TARGET): testAudio.o libcRSID.o glue.o
	$(GCC)  $^ -o $@
