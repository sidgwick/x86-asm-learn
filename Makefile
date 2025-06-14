.PHONY: clean

all:
	dd if=/dev/zero of=a.img bs=512 count=2880

	nasm -f bin -o boot -l boot.lst boot.asm
	nasm -f bin -o user -l user.lst user.asm

	dd if=boot of=a.img bs=512 count=1 conv=notrunc
	dd if=user of=a.img seek=100 bs=512 conv=notrunc

	bochs -debugger -f bochsrc.txt

	# # 验证写入 (可选)
	# fdisk -lu a.img       # 查看分区表
	# hexdump -C -s 0 a.img # 查看MBR内容
	# hexdump -C -s $((512 * 100)) a.img  # 查看LBA100内容

clean:
	rm boot user *.lst
