.PHONY: clean

AS = as --32
LD = ld -m elf_i386


all:
	dd if=/dev/zero of=a.img bs=512 count=2880

	nasm -f bin -o boot.bin -l boot.lst boot.asm
	nasm -f bin -o core.bin -l core.lst core.asm
	nasm -f bin -o user1.bin -l user1.lst user1.asm
	nasm -f bin -o user2.bin -l user2.lst user2.asm

	dd if=boot.bin of=a.img bs=512 count=1 conv=notrunc
	dd if=core.bin of=a.img seek=1 bs=512 conv=notrunc
	dd if=user1.bin of=a.img seek=50 bs=512 conv=notrunc
	dd if=user2.bin of=a.img seek=55 bs=512 conv=notrunc
	dd if=diskdata.txt of=a.img seek=100 bs=512 conv=notrunc

	bochs -debugger -f bochsrc.txt

learn:
	nasm -f bin -o boot -l boot.lst boot.asm
	nasm -f bin -o boot1 -l boot1.lst boot1.asm

	ndisasm -b 16 boot > a.txt
	ndisasm -b 16 boot1 > b.txt

rewrite:
	-rm core.o core.bin a b core0.bin

	$(AS) -o core.o core.s
	$(LD) -z noexecstack --oformat=binary --Ttext=0x80040000 -o core.bin core.o

	nasm -f bin -o core0.bin core0.asm

	# objdump -D -b binary -mi386 -Maddr16,data16 core.bin

	objdump -D -b binary -mi386 -Maddr32,data32 core0.bin | cut -d: -f2- > a
	objdump -D -b binary -mi386 -Maddr32,data32 core.bin | cut -d: -f2- > b

	diff --color -u a b
	echo $?

clean:
	rm a.img *.bin *.lst
