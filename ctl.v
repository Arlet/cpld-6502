/*
 * ctl.v
 * 
 * generate all control signals for other modules  
 *
 * (C) Arlet Ottens <arlet@c-scape.nl>
 */
module ctl( 
    input clk,
    inout [7:0] DB,
    input RST,
    input IRQ,
    input RDY,
    input NMI,
    output reg WE,
    output reg [2:0] alu_sel,
    output reg [2:0] alu_op,
    output reg [2:0] alu_ld,
    output reg alu_ci,
    input alu_co,
    input alu_n,
    input alu_v,
    input alu_z,
    output tsx,
    output reg [4:0] ab_op );

`include "states.i"

// synthesis attribute KEEP of cond_true is TRUE
// synthesis attribute KEEP of take_irq is TRUE 
// synthesis attribute KEEP of write_p is TRUE
// synthesis attribute KEEP of load_p is TRUE
// synthesis attribute KEEP of do_bit is TRUE
// synthesis attribute KEEP of load_ir is TRUE
// synthesis attribute KEEP of load_c_alu is TRUE
// synthesis attribute KEEP of load_v_alu is TRUE
// synthesis attribute KEEP of load_n_alu is TRUE
// synthesis attribute KEEP of clv is TRUE
// synthesis attribute KEEP of cli_sei is TRUE 
// synthesis attribute KEEP of clc_sec is FALSE
// synthesis attribute KEEP of cld_sed is FALSE
// synthesis attribute KEEP of pull is TRUE 

reg [3:0] state = FETCH;
reg [7:0] IR;
reg Z, N, C, V, I = 1, D;
reg cond_true;
reg rst;            // clean reset signal
reg irq;

always @(posedge clk)
    if( RDY )
        if( ~IRQ )               irq <= 1;
        else if( state == STK2 ) irq <= 0;

wire take_irq = (irq & ~I);

initial WE = 1;

wire [7:0] P = { N, V, 2'b11, D, I, Z, C };

assign tsx = (state == DECODE && IR == 8'hba);

reg jmp;
reg ind;
reg rmw;
reg load_ir;
reg load_c_alu;
reg load_n_alu;
reg load_z_alu;
reg load_v_alu;

wire indx = (IR[3:0] == 4'b0001);
wire brk = (IR == 8'h00);
wire clv = (IR == 8'hb8);
wire pha = (IR == 8'h48);
wire php = (IR == 8'h08);
wire plp = (IR == 8'h28);
wire rti = (IR == 8'h40);
wire cli = (IR == 8'h58);
wire sei = (IR == 8'h78);
wire clc = (IR == 8'h18);
wire sec = (IR == 8'h38);
wire cld = (IR == 8'hd8);
wire sed = (IR == 8'hf8);

wire cli_sei = cli | sei;
wire clc_sec = clc | sec;
wire cld_sed = cld | sed;

wire load_p = (state == STK0 && plp) || (state == STK0 && rti);
wire write_p = (state == STK0 && php) || (state == STK2 && brk);
wire do_bit = state == DATA && (IR == 8'h24 || IR == 8'h2c);
wire pull = IR[3] ? IR[5]: IR[6];
assign DB = write_p ? P: 8'hzz;

/*
 * rmw is set when doing a read-modify-write instruction. In those
 * instructions, we stay in DATA state for extra cycle to write back 
 * the result.
 */
always @(posedge clk)
    if( RDY )
        if( state == DECODE )
            casez( IR )
                8'b0???_?110:           rmw <= 1;               // shift memory
                8'b11??_?110:           rmw <= 1;               // INC/DEC
                default:                rmw <= 0;
            endcase
        else if( state == DATA )        rmw <= 0;

/*
 * ind is used for indirect access. These are initially treated as ABS
 * addressing, but then the result is treated as 2nd ABS address. 
 */
always @(posedge clk)
    if( RDY )
        if( state == DECODE )
            casez( IR )
                8'b??0?_0000:           ind <= 1;               // BRK
                8'b0110_??00:           ind <= 1;               // JMP (a)
                default:                ind <= 0;
            endcase
        else if( state == IND0 )        ind <= 0;               // prevent multiple indirections

/*
 * set 'jmp' for anything that needs to write PC in ABS0 state
 */
always @* begin
    jmp = 0;
    casez( IR )
        8'b????_0000:                   jmp = 1;                // JSR a/BRK
        8'b01??_??00:                   jmp = 1;                // JMP a
    endcase
end

/*
 * ALU input selection. Selects both AI/BI inputs of the ALU, as well as the
 * value to send to SB for address calculations. Note that in the BRA0 state, we
 * send DB value over SB, even though ABL module has access to DB. This reduces the
 * muxing we need to do.
 */
always @* begin
    alu_sel = SEL_0;
    case( state )
        BRA0:                           alu_sel = SEL_MEM;      // BRA (M     -> S)

        STK0:
            casez( IR )                 
                8'b????_??0?:           alu_sel = SEL_CMP;      // PHA
                8'b0???_??1?:           alu_sel = SEL_CPY;      // PHY
                8'b1???_??1?:           alu_sel = SEL_CPX;      // 
            endcase

        ABS0:        
            casez( IR )
                8'b10?1_??10:           alu_sel = SEL_CPY;      // A,Y (Y     -> S)
                8'b???1_?0??:           alu_sel = SEL_CPY;      // (Y) (Y     -> S)
                8'b???1_?1??:           alu_sel = SEL_CPX;      // A,X (X     -> S)
            endcase

        DECODE:         
            casez( IR )
                8'b1?0?_1000:           alu_sel = SEL_INY;      // DEY/INY/TYA
                8'b111?_1000:           alu_sel = SEL_INX;      // INX
                8'b1?0?_1010:           alu_sel = SEL_INX;      // TXA/TXS/DEX
                8'b1010_10?0:           alu_sel = SEL_CMP;      // TAX/TAY
                8'b0???_1010:           alu_sel = SEL_CMP;      // shift A
                8'b10?1_??10:           alu_sel = SEL_CPY;      // ZPY (Y     -> S)
                8'b???1_?1??:           alu_sel = SEL_CPX;      // ZPX (X     -> S)
                8'b???0_?0??:           alu_sel = SEL_CPX;      // (X) (X     -> S)
            endcase

        INDX0:          
            casez( IR )
                8'b???0_????:           alu_sel = SEL_CPX;      // (X) (X     -> S)
            endcase

        DATA, FETCH:                        
            casez( IR )
                8'b11??_??01:           alu_sel = SEL_CMP;      // CMP/SBC (~M)
                8'b1?0?_??00:           alu_sel = SEL_CPY;      // STY/CPY
                8'b111?_??00:           alu_sel = SEL_CPX;      // CPX
                8'b101?_????:           alu_sel = SEL_MEM;      // LDA/LDX/LDY
                8'b100?_??10:           alu_sel = SEL_CPX;      // STX
                8'b0010_?100:           alu_sel = SEL_ADD;      // BIT
                8'b????_??01:           alu_sel = SEL_ADD;      // ORA/AND/...
                    default:            alu_sel = SEL_MEM;
            endcase
    endcase
end

/*
 * select ALU operation
 */
always @* 
    casez( IR )
        8'b?1?1_1010:                   alu_op = OP_AI;         // PHX/PHY/PLX/PLY
        8'b1000_1000:                   alu_op = OP_ADC;        // DEY
        8'b001?_??00:                   alu_op = OP_AND;        // BIT
        8'b?11?_??01:  if( D )          alu_op = OP_BCD;        // ADC with BCD correction
                       else             alu_op = OP_ADC;        // ADC without correction
        8'b11??_????:                   alu_op = OP_ADC;        // SBC/CMP/INX/DEX/INY
        8'b000?_??01:                   alu_op = OP_ORA;        // ORA
        8'b001?_??01:                   alu_op = OP_AND;        // AND 
        8'b010?_??01:                   alu_op = OP_EOR;        // EOR 
        8'b01??_??10:                   alu_op = OP_ROR;        // ROR
        8'b00??_??10:                   alu_op = OP_ROL;        // ROL
             default:                   alu_op = OP_AI;         // nothing
    endcase

/*
 * select ALU load operation. We can load result in X, A, Y, or store it
 * to memory
 */
always @* begin
    alu_ld = 0;
    case( state )
        STK0:           
            casez( IR )
                8'b?10?_1???:           alu_ld = LD_M;          // PHA
            endcase

        DATA:           
            if( !WE )                   alu_ld = LD_M;          // write ALU

        DECODE:         
            casez( IR )
                8'b1000_1010:           alu_ld = LD_A;          // TXA
                8'b1001_1000:           alu_ld = LD_A;          // TYA
                8'b0???_1010:           alu_ld = LD_A;          // shift A
                8'b101?_1010:           alu_ld = LD_X;          // TAX/TSX
                8'b110?_1010:           alu_ld = LD_X;          // DEX
                8'b1110_1000:           alu_ld = LD_X;          // INX
                8'b1??0_1000:           alu_ld = LD_Y;          // INY/DEY/TAY
            endcase

        FETCH:          
            casez( IR )
                8'b0???_??01:           alu_ld = LD_A;          // ORA/AND/EOR/ADC 
                8'b101?_??01:           alu_ld = LD_A;          // LDA 
                8'b111?_??01:           alu_ld = LD_A;          // SBC
                8'b0111_1010:           alu_ld = LD_Y;          // PLY
                8'b1111_1010:           alu_ld = LD_X;          // PLX
                8'b?11?_10??:           alu_ld = LD_A;          // PLA
                8'b101?_??10:           alu_ld = LD_X;          // LDX
                8'b1010_??00:           alu_ld = LD_Y;          // LDY
                8'b1011_?100:           alu_ld = LD_Y;          // LDY
            endcase 
    endcase
end

/*
 * ALU CI (carry input) selection
 */
always @* begin
    casez( IR )
        8'b0?1?_?110:                   alu_ci = C;             // ROL/ROR MEM 
        8'b110?_?110:                   alu_ci = 0;             // DEC (M + FF + 0 -> M)
        8'b111?_?110:                   alu_ci = 1;             // INC (M + 00 + 1 -> M)
        8'b1100_1010:                   alu_ci = 0;             // DEX (X + FF + 0 -> X)
        8'b1000_1000:                   alu_ci = 0;             // DEY (Y + FF + 0 -> Y)
        8'b1110_1000:                   alu_ci = 1;             // INX (X + 00 + 1 -> X)
        8'b1100_1000:                   alu_ci = 1;             // INY (Y + 00 + 1 -> Y)
        8'b0?10_1010:                   alu_ci = C;             // ROL/ROR A
        8'b?11?_??01:                   alu_ci = C;             // ADC/SBC
        8'b110?_??01:                   alu_ci = 1;             // CMP
        8'b11??_??00:                   alu_ci = 1;             // CPX/CPY
        default:                        alu_ci = 0;             // default is no carry
    endcase
end

/*
 * control signal to determine if we need to update Z flag with
 * ALU result in this cycle. It is the same as for the N flag, except
 * for the BIT instruction, where the N flag comes from DB[7] instead.
 */
always @* begin
    load_z_alu = load_n_alu;
    if( state == FETCH )
        casez( IR )
            8'b0010_?100:               load_z_alu = 1;         // bit
        endcase
end

/*
 * control signal to determine if we need to update N flag with
 * ALU result in this cycle. 
 */
always @* begin
    load_n_alu = 0;
    case( state )
        FETCH:          
            casez( IR )
                8'b0110_1000:           load_n_alu = 1;         // pla
                8'b0???_??01:           load_n_alu = 1;         // ora/and/eor/adc
                8'b101?_??01:           load_n_alu = 1;         // lda
                8'b11??_??01:           load_n_alu = 1;         // cmp/sbc
                8'b1010_00?0:           load_n_alu = 1;         // ldx/ldy imm
                8'b101?_?1?0:           load_n_alu = 1;         // ldx/ldy abs/zp
                8'b11?0_0000:           load_n_alu = 1;         // cpx/cpy imm
                8'b11??_?100:           load_n_alu = 1;         // cpx/cpy
            endcase
        
        DECODE:         
            casez( IR )
                8'b0???_1010:           load_n_alu = 1;         // rol A
                8'b1?00_10?0:           load_n_alu = 1;         // dey/txa/iny/dex
                8'b1010_10?0:           load_n_alu = 1;         // tax/tay
                8'b1001_1000:           load_n_alu = 1; 
                8'b1011_1010:           load_n_alu = 1;
                8'b1110_1000:           load_n_alu = 1;
            endcase

        DATA:        
            casez( IR )
                8'b0???_?110:           load_n_alu = !WE; 
                8'b11??_?110:           load_n_alu = !WE;
            endcase
    endcase
end

/*
 * control signal to determine if we need to update N flag with
 * ALU result in this cycle.  Only true for ADC/SBC.
 */
always @* begin
    load_v_alu = 0;
    case( state )
        FETCH:          
            casez( IR )
                8'b?11?_??01:           load_v_alu = 1;         // ADC/SBC
            endcase
    endcase
end

/*
 * control signal to determine if we need to update C flag with
 * ALU result in this cycle.
 */
always @* begin
    load_c_alu = 0;
    case( state )
        DECODE: 
            casez( IR )
                8'b0???_1010:           load_c_alu = 1;         // shift A
            endcase

        DATA:   
            if( !WE ) 
            casez( IR ) 
                8'b0???_?110:           load_c_alu = 1;           // shift mem
            endcase

        FETCH:  
            casez( IR ) 
                8'b011?_??01:           load_c_alu = 1;           // ADC
                8'b11??_??01:           load_c_alu = 1;           // CMP/SBC
                8'b11?0_??00:           load_c_alu = 1;           // CPX/CPY
            endcase
    endcase
end

/*
 * Update the flags
 */

always @(posedge clk)
    if( RDY )
        if( load_p )                    Z <= DB[1];
        else if( load_z_alu )           Z <= alu_z;

always @(posedge clk)
    if( RDY )
        //if( brk && state == STK2 )      D <= 0;                 // optional: clear D in interrupt
        if( load_p )                    D <= DB[3];
        else if( cld_sed )              D <= IR[5];

always @(posedge clk)
    if( RDY )
        if( brk && state == STK2 )      I <= 1;
        else if( load_p )               I <= DB[2];
        else if( cli_sei )              I <= IR[5];
        
always @(posedge clk)
    if( RDY )
        if( load_p | do_bit )           N <= DB[7];
        else if( load_n_alu )           N <= alu_n;

always @(posedge clk)
    if( RDY )
        if( load_p | do_bit )           V <= DB[6];
        else if( clv )                  V <= 0;
        else if( load_v_alu )           V <= alu_v;

always @(posedge clk)
    if( RDY )
        if( load_p )                    C <= DB[0]; 
        else if( load_c_alu )           C <= alu_co;
        else if( clc_sec )              C <= IR[5];

/*
 * remember we saw a RST signal so we don't get 
 * confused by glitches, but always complete a full
 * sequence
 */

always @(posedge clk)
    if( RDY )
        if( !RST )                      rst <= 1;
        else if( state == STK2 )        rst <= 0;

/*
 * control signal to indicate if we need to load IR (instruction register)
 * in this cycle
 */

always @* begin
    load_ir = 0; 
    case( state )
        FETCH:                          load_ir = 1;
        DECODE:       
            if( rst )
                load_ir = 1;
            else casez( IR )
                8'b?1?1_1010:           load_ir = 0;            // PHX/PHY/PLX/PLY
                8'b0??0_1000:           load_ir = 0;
                8'b????_10?0:           load_ir = 1; 
            endcase
    endcase
end

/*
 * update IR (instruction register)
 */
always @(posedge clk)
    if( RDY & load_ir )
        if( rst | take_irq )            IR <= 0;
        else if( load_ir )              IR <= DB;

/*
 * !WE signal
 */
always @(posedge clk)
    if( RDY ) case( state )
        DATA:                           WE <= !rmw;

        ABS0:              
            casez( IR )
                8'b100?_????:           WE <= 0;                // all STA/STX/STY 
                default:                WE <= 1;
            endcase

        DECODE:
            casez( IR )
                8'b00?0_0000:           WE <= 0;                // JSR, BRK
                8'b0?00_1000:           WE <= 0;                // PHA/PHP
                8'b?101_1010:           WE <= 0;                // PHX/PHY
                8'b100?_01??:           WE <= 0;                // STA/STX/STY ZP[,X]
                default:                WE <= 1;
            endcase                 

        STK0:                           WE <= !(!IR[6] && !IR[3]);

        STK1:                           WE <= !(!IR[6] && !IR[5]); 
        default:                        WE <= 1;
    endcase

/*
 * Address Bus operation
 */

always @* begin
    ab_op = 0;
    case( state )
        DECODE: 
            casez( IR )
                8'b????_01??:           ab_op = AB_ZPXY;        // only use SB here
                8'b????_0001:           ab_op = AB_ZPXY;
                8'b0100_0000:           ab_op = AB_PLA;         // RTI
                8'b0110_0000:           ab_op = AB_PLA;         // RTS
                8'b0010_1000:           ab_op = AB_PLA;         // PLP
                8'b0110_1000:           ab_op = AB_PLA;         // PLA
                8'b?111_1010:           ab_op = AB_PLA;         // PLX/PLY
                8'b0000_0000:           ab_op = take_irq ? AB_PHA : AB_BRK;             // IRQ
                8'b0010_0000:           ab_op = AB_BRK;         // JSR
                8'b0000_1000:           ab_op = AB_PHA;         // PHP
                8'b0100_1000:           ab_op = AB_PHA;         // PHA
                8'b?101_1010:           ab_op = AB_PHA;         // PHX/PHY
                8'b1001_1010:           ab_op = AB_TXS;
                default:                ab_op = take_irq & load_ir ? AB_IRQ0 : AB_FETCH;
            endcase

        STK0:               
            casez( IR )
                8'b?1??_0???:           ab_op = AB_RTS0;        // RTS/RTI
                8'b?0??_0???:           ab_op = AB_JSR0;        // JSR/BRK
                8'b????_1???:           ab_op = AB_DATA;        // PHA/PHA/PLA/PLP
            endcase
        
        STK1:
            casez( IR )
                8'h00:                  ab_op = AB_BRK1;
                8'h20:                  ab_op = AB_JSR1;
                8'h40:                  ab_op = AB_RTS0;
                8'h60:                  ab_op = AB_RTS1;
            endcase
                                // fixme NMI vectors
        STK2:
            if( pull )                  ab_op = AB_JMP0;
            else if( rst )              ab_op = AB_RST;
            else                        ab_op = AB_BRK2;

        FETCH: if( take_irq )           ab_op = AB_IRQ0;
               else                     ab_op = AB_FETCH; 
        INDX0:                          ab_op = AB_INDX0;    

        ABS0:
            if( jmp )                   ab_op = AB_JMP0;
            else if( indx )             ab_op = AB_INDX1;
            else                        ab_op = AB_ABS0;

        DATA:
            if( rmw )                   ab_op = AB_RMW;
            else                        ab_op = AB_DATA;
        BRA0:                           ab_op = AB_BRA0; 
        IND0:                           ab_op = AB_IND0;
    endcase
end

/*
 * instruction decoding/state machine
 */

always @(posedge clk)
    if( RDY )
    if( !RST )                          state <= FETCH;
    else case( state )
        DECODE: 
            casez( IR )
                8'b?1?1_1010:           state <= STK0;          // PHY/PHX/PLY/PLX
                8'b0??0_?000:           state <= STK0;          // BRK,JSR,RTI,RTS,PLA,PHA,PLP,PHP
                8'b1000_0000:           state <= BRA0;          // BRA
                8'b???1_0000:           state <= cond_true ? BRA0: FETCH;        // odd column 0
                8'b????_0001:           state <= INDX0;         // column 1 = (ZP,X) or (ZP),Y
                8'b1??0_00?0:           state <= FETCH;         // LDY#,CPY#,CPX#,LDX#
                8'b????_01??:           state <= DATA;          // column 4567 (ZP [+index])
                8'b???0_1001:           state <= FETCH;         // even column 9 (IMM)
                8'b???1_1001:           state <= ABS0;          // odd column 9
                8'b????_11??:           state <= ABS0;          // columns CDEF
            endcase

        STK0: 
            if( ~IR[3] )                state <= STK1;
            else                        state <= FETCH;
    
        STK1: 
            if( ~IR[5] )                state <= STK2;
            else if( pull )             state <= FETCH;
            else                        state <= ABS0;

        STK2: 
            if( pull )                  state <= FETCH;
            else                        state <= IND0;          // jump through vector 

        DATA: 
            if( !rmw )                  state <= FETCH;
        BRA0:                           state <= FETCH;
        FETCH:                          state <= DECODE;
        INDX0:                          state <= ABS0; 
        IND0:                           state <= ABS0;
        ABS0: 
            if( ind )                   state <= IND0;
            else if( jmp )              state <= FETCH;
            else                        state <= DATA;
    endcase

/*
 * condition codes
 */

always @*
    casez( IR[7:4] )
        4'b000?:                        cond_true = ~N;         // BPL
        4'b001?:                        cond_true = N;          // BMI
        4'b010?:                        cond_true = ~V;         // BVC
        4'b011?:                        cond_true = V;          // BVS
        4'b1000:                        cond_true = 1;          // BRA
        4'b1001:                        cond_true = ~C;         // BCC
        4'b101?:                        cond_true = C;          // BCS
        4'b110?:                        cond_true = ~Z;         // BNE
        4'b111?:                        cond_true = Z;          // BEQ
    endcase

endmodule

