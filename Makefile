.PHONY: clean

all:
	nasm -f bin -o boot -l a.lst boot.asm
	dd if=boot of=a.img bs=512 count=1 conv=notrunc
	bochs -debugger -f bochsrc.txt

clean:
	rm boot a.lst
