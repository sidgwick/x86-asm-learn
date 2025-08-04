.PHONY: clean

AS = as --32
LD = ld -m elf_i386

all: exit power factorial

exit: exit.s
	$(AS) -o exit.o $^
	$(LD) -o $@ exit.o

factorial: factorial.s
	$(AS) -o factorial.o $^
	$(LD) -o $@ factorial.o

power: power.s
	$(AS) -o power.o $^
	$(LD) -o $@ power.o

clean:
	rm exit power *.o
