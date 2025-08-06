.PHONY: clean

AS = as --32 -g
LD = ld -m elf_i386

all: write-records read-records

write-records: linux.o record-def.o write-records.o write-record.o
	$(LD) -o $@ $^

read-records: linux.o record-def.o read-records.o read-record.o
	$(LD) -o $@ $^

%.o: %.s
	$(AS) -o $@ $^

clean:
	-rm read-records write-records test.dat *.o
