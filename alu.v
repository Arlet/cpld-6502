/*
 * ALU module for 6502 CPU
 *
 * This ALU module performs all logic and arithmetic
 * functions of the 6502, and also holds the A, X and Y
 * registers. 
 *
 * The ALU has two inputs: AI and BI. The AI input is also 
 * exported on the Special Bus (SB), for purpose of address
 * indexing. During those cycles, the output of the ALU is
 * not used.
 *
 * The 'sel' input determines which values are used for the
 * AI and BI input ports. MEM (M) is value we saw on DB in
 * previous cycle.
 *
 * sel | AI  |   BI  |   purpose
 *-----+-----+-------+------------
 *  0  |  0  |   xx  | write zero to SB for non-indexed address
 * MEM | MEM |  0/-1 | inc/dec/rol/ror memory or lda/ldx/ldy
 * CMP |  A  |  ~MEM | perform sbc/cmp by adding A to inverted memory
 * ADC |  A  |  MEM  | perform adc and all logical operations on A
 * CPX |  X  |  ~MEM | perform cpx     (or access to X)
 * INX |  X  |  0/-1 | perform inx/dex (or access to X)
 * CPY |  Y  |  ~MEM | perform cpy     (or access to Y)
 * INY |  Y  |  0/-1 | perform inx/dex (or access to Y)
 *
 * Note: the 0/-1 value for BI is based on carry input (which is 
 * also included in the addition, so the real action is +1 or -1
 * assuming adc operation is selected)
 *
 * The ROL operation is provided as an ALU primitive rather than
 * implementing it as AI + AI, in order to simplify the BI input
 * mux and reduce signal count.
 *
 * Subtracting is done by done by using inverted memory operand and
 * reducing to addition. Addition is done in two steps: first
 * calculate partial sum (as 'OUT') using a simple XOR between the 
 * bits, followed by additional XOR with carry chain bits.
 *
 * (C) Arlet Ottens <arlet@c-scape.nl>
 */
module alu(
    input clk,
    input [2:0] op,
    input [2:0] sel,
    input [2:0] op_ld,
    input CI,
    output reg CO,
    output N,
    output Z,
    output V,
    input RDY,
    input SB_DIR,
    inout [7:0] SB,
    inout [7:0] DB );

`include "states.i"

// synthesis attribute KEEP of OUT is true 
// synthesis attribute KEEP of LSD is TRUE
// synthesis attribute KEEP of MSD is TRUE
// synthesis attribute KEEP of AI is TRUE
// synthesis attribute KEEP of BI is TRUE
// synthesis attribute KEEP of N is TRUE
// synthesis attribute KEEP of HC is TRUE
// synthesis attribute KEEP of C9 is TRUE
// synthesis attribute KEEP of C8 is TRUE

reg [7:0] X = 0;
reg [7:0] Y = 0;
reg [7:0] A = 0;
reg [7:0] M;
reg [7:0] OUT;
wire [3:0] LSD;
wire [3:0] MSD;
reg [7:0] AI;
reg [7:0] BI;

wire is_adc = (op == OP_ADC) | (op == OP_BCD);
wire is_bcd = (op == OP_BCD);
wire is_add = sel[0];

wire [7:0] AB = AI & BI;

/*
 * intermediate carry bits. Intermediate results
 * will be optimized away.
 */
wire C0 = is_adc & CI;
wire C1 = is_adc & (AB[0] | (OUT[0] & C0));
wire C2 = is_adc & (AB[1] | (OUT[1] & C1));
wire C3 = is_adc & (AB[2] | (OUT[2] & C2));
wire C4 = is_adc & (AB[3] | (OUT[3] & C3));

wire HC = C4 | (is_bcd & is_add & (LSD >= 10));

wire C5 = is_adc & (AB[4] | (OUT[4] & HC));
wire C6 = is_adc & (AB[5] | (OUT[5] & C5));
wire C7 = is_adc & (AB[6] | (OUT[6] & C6));
wire C8 = is_adc & (AB[7] | (OUT[7] & C7));

wire C9 = C8 | (is_bcd & is_add & (MSD >= 10));

assign DB = op_ld[2] ? { MSD, LSD } : 8'hzz;
assign SB = ~SB_DIR  ? AI  : 8'hzz;

/*
 * select ALU AI input
 */
always @*
    case( sel )
        SEL_0  :                        AI = 0;
        SEL_MEM:                        AI = M;
        SEL_CMP:                        AI = A;
        SEL_ADD:                        AI = A;
        SEL_CPX:                        AI = X;
        SEL_INX:                        AI = X;
        SEL_CPY:                        AI = Y;
        SEL_INY:                        AI = Y;
    endcase

/*
 * select ALU BI input
 */
always @*
    case( sel )
        SEL_0,                          // SEL_0 is don't care for BI. 
        SEL_CMP,
        SEL_CPX,
        SEL_CPY:                        BI = ~M;

        SEL_ADD:                        BI = M;

        SEL_MEM,
        SEL_INX,
        SEL_INY: if( CI )               BI = 0;                 // ADD 00 + CI = +1
                 else                   BI = 8'hff;             // ADD FF      = -1
    endcase

/*
 * select ALU operation. The "BCD" operation is a regular ADC/SBC, but
 * with extra BCD correction later.
 */
always @*
    case( op )
        OP_AI :                         OUT = SB;
        OP_ROL:                         OUT = {SB[6:0], CI};    // ROL
        OP_ROR:                         OUT = {CI, SB[7:1]};    // ROR
        OP_ORA:                         OUT = SB | BI;          // ORA
        OP_AND:                         OUT = SB & BI;          // AND
        OP_EOR:                         OUT = SB ^ BI;          // EOR
        OP_ADC:                         OUT = SB ^ BI;          // ADC/SBC
        OP_BCD:                         OUT = SB ^ BI;          // BCD 
    endcase

/*
 * now XOR in the carry bits. This operation can be done 
 * using dedicated XOR port in the macrocell. 
 *
 * When not doing an add/subtract, the carry bits are all
 * cleared so this has no effect.
 */
assign LSD = OUT[3:0] ^ { C3, C2, C1, C0 };
assign MSD = OUT[7:4] ^ { C7, C6, C5, HC };

/* 
 * form ALU output by combining two digits.
 */
wire [7:0] ADD = { MSD, LSD };

/*
 * determine status flag outputs
 */

assign N = ADD[7];
assign Z = !ADD;
assign V = C7 ^ C8; 

/*
 * produce carry out
 */
always @*
    if( op == OP_ROR )                  CO = SB[0];
    else if( op == OP_ROL )             CO = SB[7];
    else                                CO = C9;

/*
 * BCD correction. Looks scary, but can be optimized
 * quite well (without needing any additional macrocells)
 */

reg [3:0] BCDL;
reg [3:0] BCDM;

always @*
    if( is_add & HC )                   BCDL = LSD + 6;
    else if( !is_add & !HC )            BCDL = LSD + 10;
    else                                BCDL = LSD;

always @*
    if( is_add & C9 )                   BCDM = MSD + 6;
    else if( !is_add & !C9 )            BCDM = MSD + 10;
    else                                BCDM = MSD;

/*
 * load ALU input in register (if indicated)
 */
always @(posedge clk)
    if( RDY )
    case( op_ld[1:0] )
        LD_X:                           X <= ADD;
        LD_Y:                           Y <= ADD;
        LD_A: if( !is_bcd )             A <= ADD;
              else                      A <= { BCDM, BCDL };
    endcase

/*
 * make copy of data bus in M register
 */
always @(posedge clk)
    if( RDY )
        M <= DB;


endmodule
