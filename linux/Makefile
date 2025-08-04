.PHONY: clean


all: exit power

exit: exit.s
	as -o exit.o $^
	ld -o $@ exit.o

power: power.s
	as -o power.o $^
	ld -o $@ power.o

clean:
	rm exit power *.o
