pub const Instruction = enum { ADC, ADDW, AND, AND1, ASL, BBC, BBS, BCC, BCS, BEQ, BMI, BNE, BPL, BVC, BVS, BRA, BRK, CALL, CBNE, CLR1, CLRC, CLRP, CLRV, CMP, CMPW, DAA, DAS, DBNZ, DEC, DECW, DI, DIV, EI, EOR, EOR1, INC, INCW, JMP, LSR, MOV, MOV1, MOVW, MUL, NOP, NOT1, NOTC, OR, OR1, PCALL, POP, PUSH, RET, RET1, ROL, ROR, SBC, SET1, SETC, SETP, SLEEP, STOP, SUBW, TCALL, TCLR1, TSET1, XCN };

pub const Opcode = struct {
    instruction: Instruction,
    length: u8,
    cycles: u8,
};

pub const Opcodes: [256]Opcode = [_]Opcode{
    .{ .instruction = .NOP, .length = 1, .cycles = 2 },
    .{ .instruction = .TCALL, .length = 1, .cycles = 8 },
    .{ .instruction = .SET1, .length = 2, .cycles = 4 },
    .{ .instruction = .BBS, .length = 3, .cycles = 5 },
    .{ .instruction = .OR, .length = 2, .cycles = 3 },
    .{ .instruction = .OR, .length = 3, .cycles = 4 },
    .{ .instruction = .OR, .length = 1, .cycles = 3 },
    .{ .instruction = .OR, .length = 2, .cycles = 6 },
    .{ .instruction = .OR, .length = 2, .cycles = 2 },
    .{ .instruction = .OR, .length = 3, .cycles = 6 },
    .{ .instruction = .OR1, .length = 3, .cycles = 5 },
    .{ .instruction = .ASL, .length = 2, .cycles = 4 },
    .{ .instruction = .ASL, .length = 3, .cycles = 5 },
    .{ .instruction = .PUSH, .length = 1, .cycles = 4 },
    .{ .instruction = .TSET1, .length = 3, .cycles = 6 },
    .{ .instruction = .BRK, .length = 1, .cycles = 8 },
    .{ .instruction = .BPL, .length = 2, .cycles = 2 },
    .{ .instruction = .TCALL, .length = 1, .cycles = 8 },
    .{ .instruction = .CLR1, .length = 2, .cycles = 4 },
    .{ .instruction = .BBC, .length = 3, .cycles = 5 },
    .{ .instruction = .OR, .length = 2, .cycles = 4 },
    .{ .instruction = .OR, .length = 3, .cycles = 5 },
    .{ .instruction = .OR, .length = 3, .cycles = 5 },
    .{ .instruction = .OR, .length = 2, .cycles = 6 },
    .{ .instruction = .OR, .length = 3, .cycles = 5 },
    .{ .instruction = .OR, .length = 1, .cycles = 5 },
    .{ .instruction = .DECW, .length = 2, .cycles = 6 },
    .{ .instruction = .ASL, .length = 2, .cycles = 5 },
    .{ .instruction = .ASL, .length = 1, .cycles = 2 },
    .{ .instruction = .DEC, .length = 1, .cycles = 2 },
    .{ .instruction = .CMP, .length = 3, .cycles = 4 },
    .{ .instruction = .JMP, .length = 3, .cycles = 6 },
    .{ .instruction = .CLRP, .length = 1, .cycles = 2 },
    .{ .instruction = .TCALL, .length = 1, .cycles = 8 },
    .{ .instruction = .SET1, .length = 2, .cycles = 4 },
    .{ .instruction = .BBS, .length = 3, .cycles = 5 },
    .{ .instruction = .AND, .length = 2, .cycles = 3 },
    .{ .instruction = .AND, .length = 3, .cycles = 4 },
    .{ .instruction = .AND, .length = 1, .cycles = 3 },
    .{ .instruction = .AND, .length = 2, .cycles = 6 },
    .{ .instruction = .AND, .length = 2, .cycles = 2 },
    .{ .instruction = .AND, .length = 3, .cycles = 6 },
    .{ .instruction = .OR1, .length = 3, .cycles = 5 },
    .{ .instruction = .ROL, .length = 2, .cycles = 4 },
    .{ .instruction = .ROL, .length = 3, .cycles = 5 },
    .{ .instruction = .PUSH, .length = 1, .cycles = 4 },
    .{ .instruction = .CBNE, .length = 3, .cycles = 5 },
    .{ .instruction = .BRA, .length = 2, .cycles = 4 },
    .{ .instruction = .BMI, .length = 2, .cycles = 2 },
    .{ .instruction = .TCALL, .length = 1, .cycles = 8 },
    .{ .instruction = .CLR1, .length = 2, .cycles = 4 },
    .{ .instruction = .BBC, .length = 3, .cycles = 5 },
    .{ .instruction = .AND, .length = 2, .cycles = 4 },
    .{ .instruction = .AND, .length = 3, .cycles = 5 },
    .{ .instruction = .AND, .length = 3, .cycles = 5 },
    .{ .instruction = .AND, .length = 2, .cycles = 6 },
    .{ .instruction = .AND, .length = 3, .cycles = 5 },
    .{ .instruction = .AND, .length = 1, .cycles = 5 },
    .{ .instruction = .INCW, .length = 2, .cycles = 6 },
    .{ .instruction = .ROL, .length = 2, .cycles = 5 },
    .{ .instruction = .ROL, .length = 1, .cycles = 2 },
    .{ .instruction = .INC, .length = 1, .cycles = 2 },
    .{ .instruction = .CMP, .length = 2, .cycles = 3 },
    .{ .instruction = .CALL, .length = 3, .cycles = 8 },
    .{ .instruction = .SETP, .length = 1, .cycles = 2 },
    .{ .instruction = .TCALL, .length = 1, .cycles = 8 },
    .{ .instruction = .SET1, .length = 2, .cycles = 4 },
    .{ .instruction = .BBS, .length = 3, .cycles = 5 },
    .{ .instruction = .EOR, .length = 2, .cycles = 3 },
    .{ .instruction = .EOR, .length = 3, .cycles = 4 },
    .{ .instruction = .EOR, .length = 1, .cycles = 3 },
    .{ .instruction = .EOR, .length = 2, .cycles = 6 },
    .{ .instruction = .EOR, .length = 2, .cycles = 2 },
    .{ .instruction = .EOR, .length = 3, .cycles = 6 },
    .{ .instruction = .AND1, .length = 3, .cycles = 4 },
    .{ .instruction = .LSR, .length = 2, .cycles = 4 },
    .{ .instruction = .LSR, .length = 3, .cycles = 5 },
    .{ .instruction = .PUSH, .length = 1, .cycles = 4 },
    .{ .instruction = .TCLR1, .length = 3, .cycles = 6 },
    .{ .instruction = .PCALL, .length = 2, .cycles = 6 },
    .{ .instruction = .BVC, .length = 2, .cycles = 2 },
    .{ .instruction = .TCALL, .length = 1, .cycles = 8 },
    .{ .instruction = .CLR1, .length = 2, .cycles = 4 },
    .{ .instruction = .BBC, .length = 3, .cycles = 5 },
    .{ .instruction = .EOR, .length = 2, .cycles = 4 },
    .{ .instruction = .EOR, .length = 3, .cycles = 5 },
    .{ .instruction = .EOR, .length = 3, .cycles = 5 },
    .{ .instruction = .EOR, .length = 2, .cycles = 6 },
    .{ .instruction = .EOR, .length = 3, .cycles = 5 },
    .{ .instruction = .EOR, .length = 1, .cycles = 5 },
    .{ .instruction = .CMPW, .length = 2, .cycles = 4 },
    .{ .instruction = .LSR, .length = 2, .cycles = 5 },
    .{ .instruction = .LSR, .length = 1, .cycles = 2 },
    .{ .instruction = .MOV, .length = 1, .cycles = 2 },
    .{ .instruction = .CMP, .length = 3, .cycles = 4 },
    .{ .instruction = .JMP, .length = 3, .cycles = 3 },
    .{ .instruction = .CLRC, .length = 1, .cycles = 2 },
    .{ .instruction = .TCALL, .length = 1, .cycles = 8 },
    .{ .instruction = .SET1, .length = 2, .cycles = 4 },
    .{ .instruction = .BBS, .length = 3, .cycles = 5 },
    .{ .instruction = .CMP, .length = 2, .cycles = 3 },
    .{ .instruction = .CMP, .length = 3, .cycles = 4 },
    .{ .instruction = .CMP, .length = 1, .cycles = 3 },
    .{ .instruction = .CMP, .length = 2, .cycles = 6 },
    .{ .instruction = .CMP, .length = 2, .cycles = 2 },
    .{ .instruction = .CMP, .length = 3, .cycles = 6 },
    .{ .instruction = .AND1, .length = 3, .cycles = 4 },
    .{ .instruction = .ROR, .length = 2, .cycles = 4 },
    .{ .instruction = .ROR, .length = 3, .cycles = 5 },
    .{ .instruction = .PUSH, .length = 1, .cycles = 4 },
    .{ .instruction = .DBNZ, .length = 3, .cycles = 5 },
    .{ .instruction = .RET, .length = 1, .cycles = 5 },
    .{ .instruction = .BVS, .length = 2, .cycles = 2 },
    .{ .instruction = .TCALL, .length = 1, .cycles = 8 },
    .{ .instruction = .CLR1, .length = 2, .cycles = 4 },
    .{ .instruction = .BBC, .length = 3, .cycles = 5 },
    .{ .instruction = .CMP, .length = 2, .cycles = 4 },
    .{ .instruction = .CMP, .length = 3, .cycles = 5 },
    .{ .instruction = .CMP, .length = 3, .cycles = 5 },
    .{ .instruction = .CMP, .length = 2, .cycles = 6 },
    .{ .instruction = .CMP, .length = 3, .cycles = 5 },
    .{ .instruction = .CMP, .length = 1, .cycles = 5 },
    .{ .instruction = .ADDW, .length = 2, .cycles = 5 },
    .{ .instruction = .ROR, .length = 2, .cycles = 5 },
    .{ .instruction = .ROR, .length = 1, .cycles = 2 },
    .{ .instruction = .MOV, .length = 1, .cycles = 2 },
    .{ .instruction = .CMP, .length = 2, .cycles = 3 },
    .{ .instruction = .RET1, .length = 1, .cycles = 6 },
    .{ .instruction = .SETC, .length = 1, .cycles = 2 },
    .{ .instruction = .TCALL, .length = 1, .cycles = 8 },
    .{ .instruction = .SET1, .length = 2, .cycles = 4 },
    .{ .instruction = .BBS, .length = 3, .cycles = 5 },
    .{ .instruction = .ADC, .length = 2, .cycles = 3 },
    .{ .instruction = .ADC, .length = 3, .cycles = 4 },
    .{ .instruction = .ADC, .length = 1, .cycles = 3 },
    .{ .instruction = .ADC, .length = 2, .cycles = 6 },
    .{ .instruction = .ADC, .length = 2, .cycles = 2 },
    .{ .instruction = .ADC, .length = 3, .cycles = 6 },
    .{ .instruction = .EOR1, .length = 3, .cycles = 5 },
    .{ .instruction = .DEC, .length = 2, .cycles = 4 },
    .{ .instruction = .DEC, .length = 3, .cycles = 5 },
    .{ .instruction = .MOV, .length = 2, .cycles = 2 },
    .{ .instruction = .POP, .length = 1, .cycles = 4 },
    .{ .instruction = .MOV, .length = 3, .cycles = 5 },
    .{ .instruction = .BCC, .length = 2, .cycles = 2 },
    .{ .instruction = .TCALL, .length = 1, .cycles = 8 },
    .{ .instruction = .CLR1, .length = 2, .cycles = 4 },
    .{ .instruction = .BBC, .length = 3, .cycles = 5 },
    .{ .instruction = .ADC, .length = 2, .cycles = 4 },
    .{ .instruction = .ADC, .length = 3, .cycles = 5 },
    .{ .instruction = .ADC, .length = 3, .cycles = 5 },
    .{ .instruction = .ADC, .length = 2, .cycles = 6 },
    .{ .instruction = .ADC, .length = 3, .cycles = 5 },
    .{ .instruction = .ADC, .length = 1, .cycles = 5 },
    .{ .instruction = .SUBW, .length = 2, .cycles = 5 },
    .{ .instruction = .DEC, .length = 2, .cycles = 5 },
    .{ .instruction = .DEC, .length = 1, .cycles = 2 },
    .{ .instruction = .MOV, .length = 1, .cycles = 2 },
    .{ .instruction = .DIV, .length = 1, .cycles = 12 },
    .{ .instruction = .XCN, .length = 1, .cycles = 5 },
    .{ .instruction = .EI, .length = 1, .cycles = 3 },
    .{ .instruction = .TCALL, .length = 1, .cycles = 8 },
    .{ .instruction = .SET1, .length = 2, .cycles = 4 },
    .{ .instruction = .BBS, .length = 3, .cycles = 5 },
    .{ .instruction = .SBC, .length = 2, .cycles = 3 },
    .{ .instruction = .SBC, .length = 3, .cycles = 4 },
    .{ .instruction = .SBC, .length = 1, .cycles = 3 },
    .{ .instruction = .SBC, .length = 2, .cycles = 6 },
    .{ .instruction = .SBC, .length = 2, .cycles = 2 },
    .{ .instruction = .SBC, .length = 3, .cycles = 6 },
    .{ .instruction = .MOV1, .length = 3, .cycles = 4 },
    .{ .instruction = .INC, .length = 2, .cycles = 4 },
    .{ .instruction = .INC, .length = 3, .cycles = 5 },
    .{ .instruction = .CMP, .length = 2, .cycles = 2 },
    .{ .instruction = .POP, .length = 1, .cycles = 4 },
    .{ .instruction = .MOV, .length = 1, .cycles = 4 },
    .{ .instruction = .BCS, .length = 2, .cycles = 2 },
    .{ .instruction = .TCALL, .length = 1, .cycles = 8 },
    .{ .instruction = .CLR1, .length = 2, .cycles = 4 },
    .{ .instruction = .BBC, .length = 3, .cycles = 5 },
    .{ .instruction = .SBC, .length = 2, .cycles = 4 },
    .{ .instruction = .SBC, .length = 3, .cycles = 5 },
    .{ .instruction = .SBC, .length = 3, .cycles = 5 },
    .{ .instruction = .SBC, .length = 2, .cycles = 6 },
    .{ .instruction = .SBC, .length = 3, .cycles = 5 },
    .{ .instruction = .SBC, .length = 1, .cycles = 5 },
    .{ .instruction = .MOVW, .length = 2, .cycles = 5 },
    .{ .instruction = .INC, .length = 2, .cycles = 5 },
    .{ .instruction = .INC, .length = 1, .cycles = 2 },
    .{ .instruction = .MOV, .length = 1, .cycles = 2 },
    .{ .instruction = .DAS, .length = 1, .cycles = 3 },
    .{ .instruction = .MOV, .length = 1, .cycles = 4 },
    .{ .instruction = .DI, .length = 1, .cycles = 3 },
    .{ .instruction = .TCALL, .length = 1, .cycles = 8 },
    .{ .instruction = .SET1, .length = 2, .cycles = 4 },
    .{ .instruction = .BBS, .length = 3, .cycles = 5 },
    .{ .instruction = .MOV, .length = 2, .cycles = 4 },
    .{ .instruction = .MOV, .length = 3, .cycles = 5 },
    .{ .instruction = .MOV, .length = 1, .cycles = 4 },
    .{ .instruction = .MOV, .length = 2, .cycles = 7 },
    .{ .instruction = .CMP, .length = 2, .cycles = 2 },
    .{ .instruction = .MOV, .length = 3, .cycles = 5 },
    .{ .instruction = .MOV1, .length = 3, .cycles = 6 },
    .{ .instruction = .MOV, .length = 2, .cycles = 4 },
    .{ .instruction = .MOV, .length = 3, .cycles = 5 },
    .{ .instruction = .MOV, .length = 2, .cycles = 2 },
    .{ .instruction = .POP, .length = 1, .cycles = 4 },
    .{ .instruction = .MUL, .length = 1, .cycles = 9 },
    .{ .instruction = .BNE, .length = 2, .cycles = 2 },
    .{ .instruction = .TCALL, .length = 1, .cycles = 8 },
    .{ .instruction = .CLR1, .length = 2, .cycles = 4 },
    .{ .instruction = .BBC, .length = 3, .cycles = 5 },
    .{ .instruction = .MOV, .length = 2, .cycles = 5 },
    .{ .instruction = .MOV, .length = 3, .cycles = 6 },
    .{ .instruction = .MOV, .length = 3, .cycles = 6 },
    .{ .instruction = .MOV, .length = 2, .cycles = 7 },
    .{ .instruction = .MOV, .length = 2, .cycles = 4 },
    .{ .instruction = .MOV, .length = 2, .cycles = 5 },
    .{ .instruction = .MOVW, .length = 2, .cycles = 5 },
    .{ .instruction = .MOV, .length = 2, .cycles = 5 },
    .{ .instruction = .DEC, .length = 1, .cycles = 2 },
    .{ .instruction = .MOV, .length = 1, .cycles = 2 },
    .{ .instruction = .CBNE, .length = 3, .cycles = 6 },
    .{ .instruction = .DAA, .length = 1, .cycles = 3 },
    .{ .instruction = .CLRV, .length = 1, .cycles = 2 },
    .{ .instruction = .TCALL, .length = 1, .cycles = 8 },
    .{ .instruction = .SET1, .length = 2, .cycles = 4 },
    .{ .instruction = .BBS, .length = 3, .cycles = 5 },
    .{ .instruction = .MOV, .length = 2, .cycles = 3 },
    .{ .instruction = .MOV, .length = 3, .cycles = 4 },
    .{ .instruction = .MOV, .length = 1, .cycles = 3 },
    .{ .instruction = .MOV, .length = 2, .cycles = 6 },
    .{ .instruction = .MOV, .length = 2, .cycles = 2 },
    .{ .instruction = .MOV, .length = 3, .cycles = 4 },
    .{ .instruction = .NOT1, .length = 3, .cycles = 5 },
    .{ .instruction = .MOV, .length = 2, .cycles = 3 },
    .{ .instruction = .MOV, .length = 3, .cycles = 4 },
    .{ .instruction = .NOTC, .length = 1, .cycles = 3 },
    .{ .instruction = .POP, .length = 1, .cycles = 4 },
    .{ .instruction = .SLEEP, .length = 1, .cycles = 0 },
    .{ .instruction = .BEQ, .length = 2, .cycles = 2 },
    .{ .instruction = .TCALL, .length = 1, .cycles = 8 },
    .{ .instruction = .CLR1, .length = 2, .cycles = 4 },
    .{ .instruction = .BBC, .length = 3, .cycles = 5 },
    .{ .instruction = .MOV, .length = 2, .cycles = 4 },
    .{ .instruction = .MOV, .length = 3, .cycles = 5 },
    .{ .instruction = .MOV, .length = 3, .cycles = 5 },
    .{ .instruction = .MOV, .length = 2, .cycles = 6 },
    .{ .instruction = .MOV, .length = 2, .cycles = 3 },
    .{ .instruction = .MOV, .length = 2, .cycles = 4 },
    .{ .instruction = .MOV, .length = 3, .cycles = 5 },
    .{ .instruction = .MOV, .length = 2, .cycles = 4 },
    .{ .instruction = .INC, .length = 1, .cycles = 2 },
    .{ .instruction = .MOV, .length = 1, .cycles = 2 },
    .{ .instruction = .DBNZ, .length = 2, .cycles = 4 },
    .{ .instruction = .STOP, .length = 1, .cycles = 0 },
};