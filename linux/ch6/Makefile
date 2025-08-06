.PHONY: clean

AS = as --32 -g
LD = ld -m elf_i386

all: write-records read-records add-year

write-records: linux.o record-def.o write-records.o write-record.o
	$(LD) -o $@ $^

read-records: linux.o record-def.o count-char.o write-newline.o read-records.o read-record.o
	$(LD) -o $@ $^


add-year: linux.o record-def.o write-record.o read-record.o add-year.o
	$(LD) -o $@ $^

%.o: %.s
	$(AS) -o $@ $^

clean:
	-rm read-records write-records add-year *.dat *.o
