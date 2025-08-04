.PHONY: clean


all: exit power

exit: exit.s
	as --32 -o exit.o $^
	ld -m elf_i386 -o $@ exit.o

power: power.s
	as --32 -o power.o $^
	ld -m elf_i386 -o $@ power.o

clean:
	rm exit power *.o
