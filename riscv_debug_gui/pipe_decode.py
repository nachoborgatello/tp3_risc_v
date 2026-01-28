PIPE_WORDS = 23

def signed32(x: int) -> int:
    x &= 0xFFFFFFFF
    return x if x < 0x80000000 else x - 0x100000000

def decode_pipe_words(pw: list[int]) -> dict:
    if len(pw) != PIPE_WORDS:
        return {"error": f"pipe_words len={len(pw)} != {PIPE_WORDS}"}

    w = pw

    # IF/ID
    valid_ifid = (w[3] & 0x1)

    # ID/EX fields
    w9 = w[9]
    funct7 = (w9 >> 25) & 0x7F
    funct3 = (w9 >> 22) & 0x7
    rs2    = (w9 >> 17) & 0x1F
    rs1    = (w9 >> 12) & 0x1F
    rd     = (w9 >> 7)  & 0x1F

    c10 = w[10]
    valid_idex     = (c10 >> 0) & 1
    reg_write_idex = (c10 >> 1) & 1
    mem_to_reg     = (c10 >> 2) & 1
    mem_read       = (c10 >> 3) & 1
    mem_write      = (c10 >> 4) & 1
    branch         = (c10 >> 5) & 1
    alu_src        = (c10 >> 6) & 1
    alu_op         = (c10 >> 7) & 0x3
    jump           = (c10 >> 9) & 1
    jalr           = (c10 >> 10) & 1
    wb_sel_pc4     = (c10 >> 11) & 1

    # EX/MEM
    w15 = w[15]
    funct3_exmem = (w15 >> 10) & 0x7
    rd_exmem     = (w15 >> 5) & 0x1F

    c16 = w[16]
    valid_exmem      = (c16 >> 0) & 1
    reg_write_exmem  = (c16 >> 1) & 1
    mem_to_reg_exmem = (c16 >> 2) & 1
    mem_read_exmem   = (c16 >> 3) & 1
    mem_write_exmem  = (c16 >> 4) & 1
    branch_taken     = (c16 >> 5) & 1
    wb_sel_pc4_exmem = (c16 >> 6) & 1

    # MEM/WB
    rd_mwb = w[20] & 0x1F
    c21 = w[21]
    valid_memwb      = (c21 >> 0) & 1
    reg_write_memwb  = (c21 >> 1) & 1
    mem_to_reg_memwb = (c21 >> 2) & 1
    wb_sel_pc4_memwb = (c21 >> 3) & 1

    return {
        "ifid": {"pc": w[0], "pc4": w[1], "instr": w[2], "valid": valid_ifid},
        "idex": {
            "pc": w[4], "pc4": w[5], "rs1_data": w[6], "rs2_data": w[7], "imm": w[8],
            "rs1": rs1, "rs2": rs2, "rd": rd, "funct3": funct3, "funct7": funct7,
            "ctrl": {
                "valid": valid_idex, "reg_write": reg_write_idex, "mem_to_reg": mem_to_reg,
                "mem_read": mem_read, "mem_write": mem_write, "branch": branch, "alu_src": alu_src,
                "alu_op": alu_op, "jump": jump, "jalr": jalr, "wb_sel_pc4": wb_sel_pc4
            }
        },
        "exmem": {
            "alu_result": w[11], "rs2_pass": w[12], "branch_target": w[13], "pc4": w[14],
            "rd": rd_exmem, "funct3": funct3_exmem,
            "ctrl": {
                "valid": valid_exmem, "reg_write": reg_write_exmem, "mem_to_reg": mem_to_reg_exmem,
                "mem_read": mem_read_exmem, "mem_write": mem_write_exmem,
                "branch_taken": branch_taken, "wb_sel_pc4": wb_sel_pc4_exmem
            }
        },
        "memwb": {
            "mem_read_data": w[17], "alu_result": w[18], "pc4": w[19], "rd": rd_mwb,
            "ctrl": {
                "valid": valid_memwb, "reg_write": reg_write_memwb,
                "mem_to_reg": mem_to_reg_memwb, "wb_sel_pc4": wb_sel_pc4_memwb
            }
        },
        "raw_words": w,
    }
