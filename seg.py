class SegmentDescriptorParser:
    """
    x86 段描述符解析工具（32 位保护模式）
    支持自动计算栈段（向下扩展段）的合法地址范围
    """

    def __init__(self, descriptor_bytes):
        """
        初始化段描述符解析器

        参数:
            descriptor_bytes: 8字节的段描述符 (bytes 或 bytearray)
        """
        if not isinstance(descriptor_bytes, (bytes, bytearray)):
            raise TypeError("描述符必须是8字节的bytes或bytearray")
        if len(descriptor_bytes) != 8:
            raise ValueError("段描述符必须是8字节长度")

        # 将描述符转换为整数并存储
        self.descriptor = int.from_bytes(descriptor_bytes, "little")
        self.descriptor_bytes = descriptor_bytes
        print("0x{:016X}, {}".format(self.descriptor, self.descriptor_bytes))
        self.base = 0
        self.limit = 0
        self.type = 0
        self.dpl = 0
        self.g = False
        self.db = False
        self.avl = False
        self.valid = False

        # 解析结果
        self.parse_descriptor()

    def parse_descriptor(self):
        """解析段描述符的各个字段"""
        # 获取字节数组
        b = self.descriptor_bytes

        # 1. 解析基地址 (32位)
        self.base = b[2] | (b[3] << 8) | (b[4] << 16) | (b[7] << 24)

        # 2. 解析段限长 (20位)
        self.limit = b[0] | (b[1] << 8) | ((b[6] & 0x0F) << 16)

        # 3. 解析访问权限字节 (第5字节)
        self.valid = bool(b[5] & 0x80)  # P位 - 存在位
        self.dpl = int((b[5] & 0x60) >> 5)  # DPL位 - 描述符特权级
        self.type = b[5] & 0x0F  # 类型字段

        # 4. 解析标志字节 (第6字节)
        self.g = bool(b[6] >> 0x80)  # G位 - 粒度
        self.db = bool(b[6] >> 0x40)  # D/B位 - 默认操作大小
        self.l = bool(b[6] >> 0x20)
        self.avl = bool(b[6] >> 0x10)  # AVL位 - 可用

        # 5. 判断段类型(type = XCRA or XEWA)
        # X 位 = 1 表示代码段
        self.is_code_segment = bool(self.type & 0x08)
        # 不是代码段, 代码段, 且往上生长(E = 0), 表示普通数据段
        self.is_data_segment = not self.is_code_segment and not (self.type & 0x04)
        # E 位 = 1 表示向下扩展(栈段)
        self.is_expand_down = bool(self.type & 0x04)

    def get_real_limit(self):
        """计算实际段界限值 (考虑粒度)"""
        if self.g:  # 4KB粒度
            return (self.limit << 12) | 0x0FFF
        else:  # 字节粒度
            return self.limit

    def get_valid_offset_range(self):
        """
        计算有效的偏移地址范围
        对于栈段(向下扩展段)返回 [min_offset, max_offset]
        """
        real_limit = self.get_real_limit()

        if self.db:  # 32位栈 (B=1)
            max_offset = 0xFFFFFFFF
        else:  # 16位栈 (B=0)
            max_offset = 0xFFFF

        if self.is_expand_down:  # 向下扩展段
            min_offset = real_limit + 1
        else:  # 普通向上扩展段
            min_offset = 0
            max_offset = real_limit

        return min_offset, max_offset

    def get_linear_address_range(self):
        """
        计算栈段的合法线性地址范围
        仅对有效的栈段返回有意义结果
        """
        min_offset, max_offset = self.get_valid_offset_range()
        min_address = self.base + min_offset
        max_address = self.base + max_offset

        return min_address, max_address

    def get_segment_type_name(self):
        """获取段类型名称"""
        type_map = {
            0b0010: "可读数据段 (向上扩展)",
            0b0011: "可读写数据段 (向上扩展)",
            0b0110: "可读数据段 (向下扩展)",
            0b0111: "可读写数据段 (向下扩展)",
            0b1010: "可读代码段 (非一致)",
            0b1011: "可读写代码段 (非一致)",
            0b1110: "可读代码段 (一致)",
            0b1111: "可读写代码段 (一致)",
        }
        return type_map.get(self.type, "未知类型")

    def get_segment_properties(self):
        """获取段属性"""
        return {
            "descriptor": f"0x{self.descriptor:016X}",
            "valid": "有效" if self.valid else "无效",
            "type": self.get_segment_type_name(),
            "type_code": bin(self.type),
            "dpl": self.dpl,
            "granularity": "4KB" if self.g else "1字节",
            "default_size": "32位" if self.db else "16位",
            "base_address": f"0x{self.base:08X}",
            "limit_value": f"0x{self.limit:05X}",
            "real_limit": f"0x{self.get_real_limit():08X}",
            "min_offset": f"0x{self.get_valid_offset_range()[0]:08X}",
            "max_offset": f"0x{self.get_valid_offset_range()[1]:08X}",
            "min_linear_addr": f"0x{self.get_linear_address_range()[0]:08X}",
            "max_linear_addr": f"0x{self.get_linear_address_range()[1]:08X}",
        }

    def __str__(self):
        """可视化输出描述符信息"""
        if not self.valid:
            return "!!! 无效段描述符 (P=0) !!!"

        props = self.get_segment_properties()
        output = [
            f"段描述符: {props['descriptor']}",
            f"类型: {props['type']} ({props['type_code']})",
            f"特权级: {props['dpl']}",
            f"基地址: {props['base_address']}",
            f"段界限: {props['limit_value']} (实际值: {props['real_limit']})",
            f"粒度: {props['granularity']} | 默认大小: {props['default_size']}",
        ]

        if self.is_expand_down and self.is_data_segment:
            output.extend([
                "--- 栈段专属计算 ---",
                f"合法偏移范围: [{props['min_offset']}, {props['max_offset']}]",
                (
                    f"合法线性地址范围: [{props['min_linear_addr']},"
                    f" {props['max_linear_addr']}]"
                ),
            ])

        return "\n".join(output)


def hex_number_to_bytes(low, high):
    res = low.to_bytes(length=4, byteorder="little")
    h = high.to_bytes(length=4, byteorder="little")
    res = res + h
    return res


# ==================== 使用示例 ====================
if __name__ == "__main__":
    code_desc = hex_number_to_bytes(0x0000FFFF, 0x00CF9200)
    parser = SegmentDescriptorParser(code_desc)
    print("1# 描述符，这是一个数据段，对应0~4GB的线性地址空间")
    print(parser)

    code_desc = hex_number_to_bytes(0x7C0001FF, 0x00409800)
    parser = SegmentDescriptorParser(code_desc)
    print("2# 保护模式下初始代码段描述符, 粒度为1个字节, 基地址为0x00007c00，512字节")
    print(parser)

    code_desc = hex_number_to_bytes(0x7C0001FF, 0x00409200)
    parser = SegmentDescriptorParser(code_desc)
    print("3# 代码段的别名描述符(数据段), 粒度为1个字节, 基地址为0x00007c00，512字节")
    print(parser)

    code_desc = hex_number_to_bytes(0x7C00FFFE, 0x00CF9600)
    parser = SegmentDescriptorParser(code_desc)
    print("4# 基地址为0x00007c00，界限为0xffffe, 粒度为4KB，向下扩展")
    print(parser)
