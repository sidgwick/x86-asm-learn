参考仓库:
- [git@github.com:yifengyou/X86-assembly-language-from-real-mode-to-protection-mode.git](https://github.com/yifengyou/X86-assembly-language-from-real-mode-to-protection-mode)


对原始的随书代码简单做一个格式化, 修正老师在 win 下面的编码显示问题:

```bash
for target in `ls *.asm`; do
    iconv -f gbk -t utf8 $target  > a
    mov a $target
done

sed 's/\s\+$//g;
     s/\r\n/\n/g;
     s/^         /        /g;
     s/^   \([^ ]\)/    \1/g' -i *.asm
```