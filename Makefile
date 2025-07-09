.PHONY: clean

all:
	dd if=/dev/zero of=a.img bs=512 count=2880

	nasm -f bin -o boot.bin -l boot.lst boot.asm
	nasm -f bin -o core.bin -l core.lst core.asm
	nasm -f bin -o user.bin -l user.lst user.asm

	dd if=boot.bin of=a.img bs=512 count=1 conv=notrunc
	dd if=core.bin of=a.img seek=1 bs=512 conv=notrunc
	dd if=user.bin of=a.img seek=50 bs=512 conv=notrunc
	dd if=diskdata.txt of=a.img seek=100 bs=512 conv=notrunc

	bochs -debugger -f bochsrc.txt

learn:
	nasm -f bin -o boot -l boot.lst boot.asm
	nasm -f bin -o boot1 -l boot1.lst boot1.asm

	ndisasm -b 16 boot > a.txt
	ndisasm -b 16 boot1 > b.txt

clean:
	rm a.img *.bin *.lst
