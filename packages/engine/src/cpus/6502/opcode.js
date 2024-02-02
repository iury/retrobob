import { AddressingMode } from './addressing_mode'
import { adc } from './instructions/adc'
import { and } from './instructions/and'
import { asl } from './instructions/asl'
import { bcc } from './instructions/bcc'
import { bcs } from './instructions/bcs'
import { beq } from './instructions/beq'
import { bit } from './instructions/bit'
import { bne } from './instructions/bne'
import { bpl } from './instructions/bpl'
import { brk } from './instructions/brk'
import { bmi } from './instructions/bmi'
import { bvc } from './instructions/bvc'
import { bvs } from './instructions/bvs'
import { clc } from './instructions/clc'
import { cld } from './instructions/cld'
import { cli } from './instructions/cli'
import { clv } from './instructions/clv'
import { cmp } from './instructions/cmp'
import { cpx } from './instructions/cpx'
import { cpy } from './instructions/cpy'
import { dcp } from './instructions/dcp'
import { dec } from './instructions/dec'
import { dex } from './instructions/dex'
import { dey } from './instructions/dey'
import { eor } from './instructions/eor'
import { jmp } from './instructions/jmp'
import { jsr } from './instructions/jsr'
import { lax } from './instructions/lax'
import { lda } from './instructions/lda'
import { ldx } from './instructions/ldx'
import { ldy } from './instructions/ldy'
import { lsr } from './instructions/lsr'
import { inc } from './instructions/inc'
import { inx } from './instructions/inx'
import { iny } from './instructions/iny'
import { isb } from './instructions/isb'
import { nop } from './instructions/nop'
import { ora } from './instructions/ora'
import { pha } from './instructions/pha'
import { php } from './instructions/php'
import { pla } from './instructions/pla'
import { plp } from './instructions/plp'
import { rla } from './instructions/rla'
import { rol } from './instructions/rol'
import { ror } from './instructions/ror'
import { rra } from './instructions/rra'
import { rti } from './instructions/rti'
import { rts } from './instructions/rts'
import { sbc } from './instructions/sbc'
import { sec } from './instructions/sec'
import { sed } from './instructions/sed'
import { sei } from './instructions/sei'
import { sax } from './instructions/sax'
import { slo } from './instructions/slo'
import { sta } from './instructions/sta'
import { stx } from './instructions/stx'
import { sty } from './instructions/sty'
import { sre } from './instructions/sre'
import { tax } from './instructions/tax'
import { tay } from './instructions/tay'
import { tsx } from './instructions/tsx'
import { txa } from './instructions/txa'
import { txs } from './instructions/txs'
import { tya } from './instructions/tya'

function* hlt() {
  while (true) yield 'GET'
}

/** @enum {string} */
export const Instruction = {
  ADC: 'ADC',
  AND: 'AND',
  ASL: 'ASL',
  BCC: 'BCC',
  BCS: 'BCS',
  BEQ: 'BEQ',
  BIT: 'BIT',
  BMI: 'BMI',
  BNE: 'BNE',
  BPL: 'BPL',
  BRK: 'BRK',
  BVC: 'BVC',
  BVS: 'BVS',
  CLC: 'CLC',
  CLD: 'CLD',
  CLI: 'CLI',
  CLV: 'CLV',
  CMP: 'CMP',
  CPX: 'CPX',
  CPY: 'CPY',
  DEC: 'DEC',
  DEX: 'DEX',
  DEY: 'DEY',
  EOR: 'EOR',
  INC: 'INC',
  INX: 'INX',
  INY: 'INY',
  JMP: 'JMP',
  JSR: 'JSR',
  LDA: 'LDA',
  LDX: 'LDX',
  LDY: 'LDY',
  LSR: 'LSR',
  NOP: 'NOP',
  ORA: 'ORA',
  PHA: 'PHA',
  PHP: 'PHP',
  PLA: 'PLA',
  PLP: 'PLP',
  ROL: 'ROL',
  ROR: 'ROR',
  RTI: 'RTI',
  RTS: 'RTS',
  SBC: 'SBC',
  SEC: 'SEC',
  SED: 'SED',
  SEI: 'SEI',
  STA: 'STA',
  STX: 'STX',
  STY: 'STY',
  TAX: 'TAX',
  TAY: 'TAY',
  TSX: 'TSX',
  TXA: 'TXA',
  TXS: 'TXS',
  TYA: 'TYA',

  LAX: 'LAX',
  SAX: 'SAX',
  DCP: 'DCP',
  ISB: 'ISB',
  SLO: 'SLO',
  RLA: 'RLA',
  SRE: 'SRE',
  RRA: 'RRA',
  HLT: 'HLT',
}

/**
 * @callback fn
 * @param {AddressingMode} mode
 * @param {*} addr
 */

/** @type Array.<{ instruction: Instruction, addressingMode: AddressingMode, fn: fn }> */
export const Opcode = [
  { instruction: Instruction.BRK, addressingMode: AddressingMode.IMP, fn: brk },
  { instruction: Instruction.ORA, addressingMode: AddressingMode.IDX, fn: ora },
  { instruction: Instruction.HLT, addressingMode: AddressingMode.IMP, fn: hlt },
  { instruction: Instruction.SLO, addressingMode: AddressingMode.IDX, fn: slo },
  { instruction: Instruction.NOP, addressingMode: AddressingMode.ZPG, fn: nop },
  { instruction: Instruction.ORA, addressingMode: AddressingMode.ZPG, fn: ora },
  { instruction: Instruction.ASL, addressingMode: AddressingMode.ZPG, fn: asl },
  { instruction: Instruction.SLO, addressingMode: AddressingMode.ZPG, fn: slo },
  { instruction: Instruction.PHP, addressingMode: AddressingMode.IMP, fn: php },
  { instruction: Instruction.ORA, addressingMode: AddressingMode.IMM, fn: ora },
  { instruction: Instruction.ASL, addressingMode: AddressingMode.ACC, fn: asl },
  { instruction: Instruction.NOP, addressingMode: AddressingMode.IMM, fn: nop },
  { instruction: Instruction.NOP, addressingMode: AddressingMode.ABS, fn: nop },
  { instruction: Instruction.ORA, addressingMode: AddressingMode.ABS, fn: ora },
  { instruction: Instruction.ASL, addressingMode: AddressingMode.ABS, fn: asl },
  { instruction: Instruction.SLO, addressingMode: AddressingMode.ABS, fn: slo },
  { instruction: Instruction.BPL, addressingMode: AddressingMode.REL, fn: bpl },
  { instruction: Instruction.ORA, addressingMode: AddressingMode.IDY, fn: ora },
  { instruction: Instruction.HLT, addressingMode: AddressingMode.IMP, fn: hlt },
  { instruction: Instruction.SLO, addressingMode: AddressingMode.IDY, fn: slo },
  { instruction: Instruction.NOP, addressingMode: AddressingMode.ZPX, fn: nop },
  { instruction: Instruction.ORA, addressingMode: AddressingMode.ZPX, fn: ora },
  { instruction: Instruction.ASL, addressingMode: AddressingMode.ZPX, fn: asl },
  { instruction: Instruction.SLO, addressingMode: AddressingMode.ZPX, fn: slo },
  { instruction: Instruction.CLC, addressingMode: AddressingMode.IMP, fn: clc },
  { instruction: Instruction.ORA, addressingMode: AddressingMode.ABY, fn: ora },
  { instruction: Instruction.NOP, addressingMode: AddressingMode.IMP, fn: nop },
  { instruction: Instruction.SLO, addressingMode: AddressingMode.ABY, fn: slo },
  { instruction: Instruction.NOP, addressingMode: AddressingMode.ABX, fn: nop },
  { instruction: Instruction.ORA, addressingMode: AddressingMode.ABX, fn: ora },
  { instruction: Instruction.ASL, addressingMode: AddressingMode.ABX, fn: asl },
  { instruction: Instruction.SLO, addressingMode: AddressingMode.ABX, fn: slo },
  { instruction: Instruction.JSR, addressingMode: AddressingMode.ABS, fn: jsr },
  { instruction: Instruction.AND, addressingMode: AddressingMode.IDX, fn: and },
  { instruction: Instruction.HLT, addressingMode: AddressingMode.IMP, fn: hlt },
  { instruction: Instruction.RLA, addressingMode: AddressingMode.IDX, fn: rla },
  { instruction: Instruction.BIT, addressingMode: AddressingMode.ZPG, fn: bit },
  { instruction: Instruction.AND, addressingMode: AddressingMode.ZPG, fn: and },
  { instruction: Instruction.ROL, addressingMode: AddressingMode.ZPG, fn: rol },
  { instruction: Instruction.RLA, addressingMode: AddressingMode.ZPG, fn: rla },
  { instruction: Instruction.PLP, addressingMode: AddressingMode.IMP, fn: plp },
  { instruction: Instruction.AND, addressingMode: AddressingMode.IMM, fn: and },
  { instruction: Instruction.ROL, addressingMode: AddressingMode.ACC, fn: rol },
  { instruction: Instruction.NOP, addressingMode: AddressingMode.IMM, fn: nop },
  { instruction: Instruction.BIT, addressingMode: AddressingMode.ABS, fn: bit },
  { instruction: Instruction.AND, addressingMode: AddressingMode.ABS, fn: and },
  { instruction: Instruction.ROL, addressingMode: AddressingMode.ABS, fn: rol },
  { instruction: Instruction.RLA, addressingMode: AddressingMode.ABS, fn: rla },
  { instruction: Instruction.BMI, addressingMode: AddressingMode.REL, fn: bmi },
  { instruction: Instruction.AND, addressingMode: AddressingMode.IDY, fn: and },
  { instruction: Instruction.HLT, addressingMode: AddressingMode.IMP, fn: hlt },
  { instruction: Instruction.RLA, addressingMode: AddressingMode.IDY, fn: rla },
  { instruction: Instruction.NOP, addressingMode: AddressingMode.ZPX, fn: nop },
  { instruction: Instruction.AND, addressingMode: AddressingMode.ZPX, fn: and },
  { instruction: Instruction.ROL, addressingMode: AddressingMode.ZPX, fn: rol },
  { instruction: Instruction.RLA, addressingMode: AddressingMode.ZPX, fn: rla },
  { instruction: Instruction.SEC, addressingMode: AddressingMode.IMP, fn: sec },
  { instruction: Instruction.AND, addressingMode: AddressingMode.ABY, fn: and },
  { instruction: Instruction.NOP, addressingMode: AddressingMode.IMP, fn: nop },
  { instruction: Instruction.RLA, addressingMode: AddressingMode.ABY, fn: rla },
  { instruction: Instruction.NOP, addressingMode: AddressingMode.ABX, fn: nop },
  { instruction: Instruction.AND, addressingMode: AddressingMode.ABX, fn: and },
  { instruction: Instruction.ROL, addressingMode: AddressingMode.ABX, fn: rol },
  { instruction: Instruction.RLA, addressingMode: AddressingMode.ABX, fn: rla },
  { instruction: Instruction.RTI, addressingMode: AddressingMode.IMP, fn: rti },
  { instruction: Instruction.EOR, addressingMode: AddressingMode.IDX, fn: eor },
  { instruction: Instruction.HLT, addressingMode: AddressingMode.IMP, fn: hlt },
  { instruction: Instruction.SRE, addressingMode: AddressingMode.IDX, fn: sre },
  { instruction: Instruction.NOP, addressingMode: AddressingMode.ZPG, fn: nop },
  { instruction: Instruction.EOR, addressingMode: AddressingMode.ZPG, fn: eor },
  { instruction: Instruction.LSR, addressingMode: AddressingMode.ZPG, fn: lsr },
  { instruction: Instruction.SRE, addressingMode: AddressingMode.ZPG, fn: sre },
  { instruction: Instruction.PHA, addressingMode: AddressingMode.IMP, fn: pha },
  { instruction: Instruction.EOR, addressingMode: AddressingMode.IMM, fn: eor },
  { instruction: Instruction.LSR, addressingMode: AddressingMode.ACC, fn: lsr },
  { instruction: Instruction.NOP, addressingMode: AddressingMode.IMM, fn: nop },
  { instruction: Instruction.JMP, addressingMode: AddressingMode.ABS, fn: jmp },
  { instruction: Instruction.EOR, addressingMode: AddressingMode.ABS, fn: eor },
  { instruction: Instruction.LSR, addressingMode: AddressingMode.ABS, fn: lsr },
  { instruction: Instruction.SRE, addressingMode: AddressingMode.ABS, fn: sre },
  { instruction: Instruction.BVC, addressingMode: AddressingMode.REL, fn: bvc },
  { instruction: Instruction.EOR, addressingMode: AddressingMode.IDY, fn: eor },
  { instruction: Instruction.HLT, addressingMode: AddressingMode.IMP, fn: hlt },
  { instruction: Instruction.SRE, addressingMode: AddressingMode.IDY, fn: sre },
  { instruction: Instruction.NOP, addressingMode: AddressingMode.ZPX, fn: nop },
  { instruction: Instruction.EOR, addressingMode: AddressingMode.ZPX, fn: eor },
  { instruction: Instruction.LSR, addressingMode: AddressingMode.ZPX, fn: lsr },
  { instruction: Instruction.SRE, addressingMode: AddressingMode.ZPX, fn: sre },
  { instruction: Instruction.CLI, addressingMode: AddressingMode.IMP, fn: cli },
  { instruction: Instruction.EOR, addressingMode: AddressingMode.ABY, fn: eor },
  { instruction: Instruction.NOP, addressingMode: AddressingMode.IMP, fn: nop },
  { instruction: Instruction.SRE, addressingMode: AddressingMode.ABY, fn: sre },
  { instruction: Instruction.NOP, addressingMode: AddressingMode.ABX, fn: nop },
  { instruction: Instruction.EOR, addressingMode: AddressingMode.ABX, fn: eor },
  { instruction: Instruction.LSR, addressingMode: AddressingMode.ABX, fn: lsr },
  { instruction: Instruction.SRE, addressingMode: AddressingMode.ABX, fn: sre },
  { instruction: Instruction.RTS, addressingMode: AddressingMode.IMP, fn: rts },
  { instruction: Instruction.ADC, addressingMode: AddressingMode.IDX, fn: adc },
  { instruction: Instruction.HLT, addressingMode: AddressingMode.IMP, fn: hlt },
  { instruction: Instruction.RRA, addressingMode: AddressingMode.IDX, fn: rra },
  { instruction: Instruction.NOP, addressingMode: AddressingMode.ZPG, fn: nop },
  { instruction: Instruction.ADC, addressingMode: AddressingMode.ZPG, fn: adc },
  { instruction: Instruction.ROR, addressingMode: AddressingMode.ZPG, fn: ror },
  { instruction: Instruction.RRA, addressingMode: AddressingMode.ZPG, fn: rra },
  { instruction: Instruction.PLA, addressingMode: AddressingMode.IMP, fn: pla },
  { instruction: Instruction.ADC, addressingMode: AddressingMode.IMM, fn: adc },
  { instruction: Instruction.ROR, addressingMode: AddressingMode.ACC, fn: ror },
  { instruction: Instruction.NOP, addressingMode: AddressingMode.IMM, fn: nop },
  { instruction: Instruction.JMP, addressingMode: AddressingMode.IND, fn: jmp },
  { instruction: Instruction.ADC, addressingMode: AddressingMode.ABS, fn: adc },
  { instruction: Instruction.ROR, addressingMode: AddressingMode.ABS, fn: ror },
  { instruction: Instruction.RRA, addressingMode: AddressingMode.ABS, fn: rra },
  { instruction: Instruction.BVS, addressingMode: AddressingMode.REL, fn: bvs },
  { instruction: Instruction.ADC, addressingMode: AddressingMode.IDY, fn: adc },
  { instruction: Instruction.HLT, addressingMode: AddressingMode.IMP, fn: hlt },
  { instruction: Instruction.RRA, addressingMode: AddressingMode.IDY, fn: rra },
  { instruction: Instruction.NOP, addressingMode: AddressingMode.ZPX, fn: nop },
  { instruction: Instruction.ADC, addressingMode: AddressingMode.ZPX, fn: adc },
  { instruction: Instruction.ROR, addressingMode: AddressingMode.ZPX, fn: ror },
  { instruction: Instruction.RRA, addressingMode: AddressingMode.ZPX, fn: rra },
  { instruction: Instruction.SEI, addressingMode: AddressingMode.IMP, fn: sei },
  { instruction: Instruction.ADC, addressingMode: AddressingMode.ABY, fn: adc },
  { instruction: Instruction.NOP, addressingMode: AddressingMode.IMP, fn: nop },
  { instruction: Instruction.RRA, addressingMode: AddressingMode.ABY, fn: rra },
  { instruction: Instruction.NOP, addressingMode: AddressingMode.ABX, fn: nop },
  { instruction: Instruction.ADC, addressingMode: AddressingMode.ABX, fn: adc },
  { instruction: Instruction.ROR, addressingMode: AddressingMode.ABX, fn: ror },
  { instruction: Instruction.RRA, addressingMode: AddressingMode.ABX, fn: rra },
  { instruction: Instruction.NOP, addressingMode: AddressingMode.IMM, fn: nop },
  { instruction: Instruction.STA, addressingMode: AddressingMode.IDX, fn: sta },
  { instruction: Instruction.NOP, addressingMode: AddressingMode.IMM, fn: nop },
  { instruction: Instruction.SAX, addressingMode: AddressingMode.IDX, fn: sax },
  { instruction: Instruction.STY, addressingMode: AddressingMode.ZPG, fn: sty },
  { instruction: Instruction.STA, addressingMode: AddressingMode.ZPG, fn: sta },
  { instruction: Instruction.STX, addressingMode: AddressingMode.ZPG, fn: stx },
  { instruction: Instruction.SAX, addressingMode: AddressingMode.ZPG, fn: sax },
  { instruction: Instruction.DEY, addressingMode: AddressingMode.IMP, fn: dey },
  { instruction: Instruction.NOP, addressingMode: AddressingMode.IMM, fn: nop },
  { instruction: Instruction.TXA, addressingMode: AddressingMode.IMP, fn: txa },
  { instruction: Instruction.NOP, addressingMode: AddressingMode.IMM, fn: nop },
  { instruction: Instruction.STY, addressingMode: AddressingMode.ABS, fn: sty },
  { instruction: Instruction.STA, addressingMode: AddressingMode.ABS, fn: sta },
  { instruction: Instruction.STX, addressingMode: AddressingMode.ABS, fn: stx },
  { instruction: Instruction.SAX, addressingMode: AddressingMode.ABS, fn: sax },
  { instruction: Instruction.BCC, addressingMode: AddressingMode.REL, fn: bcc },
  { instruction: Instruction.STA, addressingMode: AddressingMode.IDY, fn: sta },
  { instruction: Instruction.HLT, addressingMode: AddressingMode.IMP, fn: hlt },
  { instruction: Instruction.NOP, addressingMode: AddressingMode.IDY, fn: nop },
  { instruction: Instruction.STY, addressingMode: AddressingMode.ZPX, fn: sty },
  { instruction: Instruction.STA, addressingMode: AddressingMode.ZPX, fn: sta },
  { instruction: Instruction.STX, addressingMode: AddressingMode.ZPY, fn: stx },
  { instruction: Instruction.SAX, addressingMode: AddressingMode.ZPY, fn: sax },
  { instruction: Instruction.TYA, addressingMode: AddressingMode.IMP, fn: tya },
  { instruction: Instruction.STA, addressingMode: AddressingMode.ABY, fn: sta },
  { instruction: Instruction.TXS, addressingMode: AddressingMode.IMP, fn: txs },
  { instruction: Instruction.NOP, addressingMode: AddressingMode.ABY, fn: nop },
  { instruction: Instruction.NOP, addressingMode: AddressingMode.ABX, fn: nop },
  { instruction: Instruction.STA, addressingMode: AddressingMode.ABX, fn: sta },
  { instruction: Instruction.NOP, addressingMode: AddressingMode.ABY, fn: nop },
  { instruction: Instruction.NOP, addressingMode: AddressingMode.ABY, fn: nop },
  { instruction: Instruction.LDY, addressingMode: AddressingMode.IMM, fn: ldy },
  { instruction: Instruction.LDA, addressingMode: AddressingMode.IDX, fn: lda },
  { instruction: Instruction.LDX, addressingMode: AddressingMode.IMM, fn: ldx },
  { instruction: Instruction.LAX, addressingMode: AddressingMode.IDX, fn: lax },
  { instruction: Instruction.LDY, addressingMode: AddressingMode.ZPG, fn: ldy },
  { instruction: Instruction.LDA, addressingMode: AddressingMode.ZPG, fn: lda },
  { instruction: Instruction.LDX, addressingMode: AddressingMode.ZPG, fn: ldx },
  { instruction: Instruction.LAX, addressingMode: AddressingMode.ZPG, fn: lax },
  { instruction: Instruction.TAY, addressingMode: AddressingMode.IMP, fn: tay },
  { instruction: Instruction.LDA, addressingMode: AddressingMode.IMM, fn: lda },
  { instruction: Instruction.TAX, addressingMode: AddressingMode.IMP, fn: tax },
  { instruction: Instruction.LAX, addressingMode: AddressingMode.IMM, fn: lax },
  { instruction: Instruction.LDY, addressingMode: AddressingMode.ABS, fn: ldy },
  { instruction: Instruction.LDA, addressingMode: AddressingMode.ABS, fn: lda },
  { instruction: Instruction.LDX, addressingMode: AddressingMode.ABS, fn: ldx },
  { instruction: Instruction.LAX, addressingMode: AddressingMode.ABS, fn: lax },
  { instruction: Instruction.BCS, addressingMode: AddressingMode.REL, fn: bcs },
  { instruction: Instruction.LDA, addressingMode: AddressingMode.IDY, fn: lda },
  { instruction: Instruction.HLT, addressingMode: AddressingMode.IMP, fn: hlt },
  { instruction: Instruction.LAX, addressingMode: AddressingMode.IDY, fn: lax },
  { instruction: Instruction.LDY, addressingMode: AddressingMode.ZPX, fn: ldy },
  { instruction: Instruction.LDA, addressingMode: AddressingMode.ZPX, fn: lda },
  { instruction: Instruction.LDX, addressingMode: AddressingMode.ZPY, fn: ldx },
  { instruction: Instruction.LAX, addressingMode: AddressingMode.ZPY, fn: lax },
  { instruction: Instruction.CLV, addressingMode: AddressingMode.IMP, fn: clv },
  { instruction: Instruction.LDA, addressingMode: AddressingMode.ABY, fn: lda },
  { instruction: Instruction.TSX, addressingMode: AddressingMode.IMP, fn: tsx },
  { instruction: Instruction.NOP, addressingMode: AddressingMode.ABY, fn: nop },
  { instruction: Instruction.LDY, addressingMode: AddressingMode.ABX, fn: ldy },
  { instruction: Instruction.LDA, addressingMode: AddressingMode.ABX, fn: lda },
  { instruction: Instruction.LDX, addressingMode: AddressingMode.ABY, fn: ldx },
  { instruction: Instruction.LAX, addressingMode: AddressingMode.ABY, fn: lax },
  { instruction: Instruction.CPY, addressingMode: AddressingMode.IMM, fn: cpy },
  { instruction: Instruction.CMP, addressingMode: AddressingMode.IDX, fn: cmp },
  { instruction: Instruction.NOP, addressingMode: AddressingMode.IMM, fn: nop },
  { instruction: Instruction.DCP, addressingMode: AddressingMode.IDX, fn: dcp },
  { instruction: Instruction.CPY, addressingMode: AddressingMode.ZPG, fn: cpy },
  { instruction: Instruction.CMP, addressingMode: AddressingMode.ZPG, fn: cmp },
  { instruction: Instruction.DEC, addressingMode: AddressingMode.ZPG, fn: dec },
  { instruction: Instruction.DCP, addressingMode: AddressingMode.ZPG, fn: dcp },
  { instruction: Instruction.INY, addressingMode: AddressingMode.IMP, fn: iny },
  { instruction: Instruction.CMP, addressingMode: AddressingMode.IMM, fn: cmp },
  { instruction: Instruction.DEX, addressingMode: AddressingMode.IMP, fn: dex },
  { instruction: Instruction.NOP, addressingMode: AddressingMode.IMM, fn: nop },
  { instruction: Instruction.CPY, addressingMode: AddressingMode.ABS, fn: cpy },
  { instruction: Instruction.CMP, addressingMode: AddressingMode.ABS, fn: cmp },
  { instruction: Instruction.DEC, addressingMode: AddressingMode.ABS, fn: dec },
  { instruction: Instruction.DCP, addressingMode: AddressingMode.ABS, fn: dcp },
  { instruction: Instruction.BNE, addressingMode: AddressingMode.REL, fn: bne },
  { instruction: Instruction.CMP, addressingMode: AddressingMode.IDY, fn: cmp },
  { instruction: Instruction.HLT, addressingMode: AddressingMode.IMP, fn: hlt },
  { instruction: Instruction.DCP, addressingMode: AddressingMode.IDY, fn: dcp },
  { instruction: Instruction.NOP, addressingMode: AddressingMode.ZPX, fn: nop },
  { instruction: Instruction.CMP, addressingMode: AddressingMode.ZPX, fn: cmp },
  { instruction: Instruction.DEC, addressingMode: AddressingMode.ZPX, fn: dec },
  { instruction: Instruction.DCP, addressingMode: AddressingMode.ZPX, fn: dcp },
  { instruction: Instruction.CLD, addressingMode: AddressingMode.IMP, fn: cld },
  { instruction: Instruction.CMP, addressingMode: AddressingMode.ABY, fn: cmp },
  { instruction: Instruction.NOP, addressingMode: AddressingMode.IMP, fn: nop },
  { instruction: Instruction.DCP, addressingMode: AddressingMode.ABY, fn: dcp },
  { instruction: Instruction.NOP, addressingMode: AddressingMode.ABX, fn: nop },
  { instruction: Instruction.CMP, addressingMode: AddressingMode.ABX, fn: cmp },
  { instruction: Instruction.DEC, addressingMode: AddressingMode.ABX, fn: dec },
  { instruction: Instruction.DCP, addressingMode: AddressingMode.ABX, fn: dcp },
  { instruction: Instruction.CPX, addressingMode: AddressingMode.IMM, fn: cpx },
  { instruction: Instruction.SBC, addressingMode: AddressingMode.IDX, fn: sbc },
  { instruction: Instruction.NOP, addressingMode: AddressingMode.IMM, fn: nop },
  { instruction: Instruction.ISB, addressingMode: AddressingMode.IDX, fn: isb },
  { instruction: Instruction.CPX, addressingMode: AddressingMode.ZPG, fn: cpx },
  { instruction: Instruction.SBC, addressingMode: AddressingMode.ZPG, fn: sbc },
  { instruction: Instruction.INC, addressingMode: AddressingMode.ZPG, fn: inc },
  { instruction: Instruction.ISB, addressingMode: AddressingMode.ZPG, fn: isb },
  { instruction: Instruction.INX, addressingMode: AddressingMode.IMP, fn: inx },
  { instruction: Instruction.SBC, addressingMode: AddressingMode.IMM, fn: sbc },
  { instruction: Instruction.NOP, addressingMode: AddressingMode.IMP, fn: nop },
  { instruction: Instruction.SBC, addressingMode: AddressingMode.IMM, fn: sbc },
  { instruction: Instruction.CPX, addressingMode: AddressingMode.ABS, fn: cpx },
  { instruction: Instruction.SBC, addressingMode: AddressingMode.ABS, fn: sbc },
  { instruction: Instruction.INC, addressingMode: AddressingMode.ABS, fn: inc },
  { instruction: Instruction.ISB, addressingMode: AddressingMode.ABS, fn: isb },
  { instruction: Instruction.BEQ, addressingMode: AddressingMode.REL, fn: beq },
  { instruction: Instruction.SBC, addressingMode: AddressingMode.IDY, fn: sbc },
  { instruction: Instruction.HLT, addressingMode: AddressingMode.IMP, fn: hlt },
  { instruction: Instruction.ISB, addressingMode: AddressingMode.IDY, fn: isb },
  { instruction: Instruction.NOP, addressingMode: AddressingMode.ZPX, fn: nop },
  { instruction: Instruction.SBC, addressingMode: AddressingMode.ZPX, fn: sbc },
  { instruction: Instruction.INC, addressingMode: AddressingMode.ZPX, fn: inc },
  { instruction: Instruction.ISB, addressingMode: AddressingMode.ZPX, fn: isb },
  { instruction: Instruction.SED, addressingMode: AddressingMode.IMP, fn: sed },
  { instruction: Instruction.SBC, addressingMode: AddressingMode.ABY, fn: sbc },
  { instruction: Instruction.NOP, addressingMode: AddressingMode.IMP, fn: nop },
  { instruction: Instruction.ISB, addressingMode: AddressingMode.ABY, fn: isb },
  { instruction: Instruction.NOP, addressingMode: AddressingMode.ABX, fn: nop },
  { instruction: Instruction.SBC, addressingMode: AddressingMode.ABX, fn: sbc },
  { instruction: Instruction.INC, addressingMode: AddressingMode.ABX, fn: inc },
  { instruction: Instruction.ISB, addressingMode: AddressingMode.ABX, fn: isb },
]
