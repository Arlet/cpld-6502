/*
 * address bus low : handles lower 8 bits of address bus. 
 * 
 * The actions are determined by the 'op' input from the control
 * logic. We have 5 bits for control, with some AB_* defines
 * named after typical usage (but not necessarily uniquely used
 * for that purpose), for example AB_RMW refers to a read-modify-
 * write cycle, but really it is just an operation that holds the
 * previous address.
 *
 * (C) Arlet Ottens <arlet@c-scape.nl>
 */

module abl(
    input clk,
    input [4:0] op,   
    input RDY,
    output CO,                  // carry out
    output PCL8,                // PCL carry out
    output reg [7:0] ABL,       // Address Bus Low
    input SB_DIR,               // Special Bus Output Enable
    inout [7:0] DB,             // Data Bus 
    inout [7:0] SB );           // Special Bus

`include "states.i"

reg [7:0] PCL;                  // Program Counter Low
reg [7:0] SPL = 8'hFF;          // Stack Pointer Low
reg [7:0] AHL;                  // Address Hold Low
reg [7:0] base;                 // base address
wire [7:0] offset;              // address offset
wire [8:0] PCL1 = ABL + 1;      // next program counter

// synthesis attribute KEEP of PCL is TRUE
// synthesis attribute KEEP of base is TRUE
// synthesis attribute KEEP of EAL is FALSE 
// synthesis attribute KEEP of load_ahl is TRUE
// synthesis attribute KEEP of load_spl is TRUE
// synthesis attribute KEEP of load_pcl is TRUE
// synthesis attribute KEEP of oe_pcl is TRUE
// synthesis attribute KEEP of load_abl is TRUE
// synthesis attribute KEEP of use_sb is TRUE
// synthesis attribute KEEP of irq is TRUE
// synthesis attribute KEEP of P is TRUE

reg CI;
reg use_sb;
reg oe_pcl;
reg load_ahl;
reg load_pcl;
wire load_abl = (op != AB_RMW);
wire load_spl = (op == AB_TXS);
wire irq = ( op == AB_IRQ0 );

assign PCL8 = PCL1[8];          // carry out for program counter high
assign DB = oe_pcl ? PCL : 8'hZZ;
assign SB = SB_DIR ? SPL : 8'hZZ;

assign offset = use_sb ? SB : 8'h00;

wire [7:0] P = base ^ offset;   // Partial sum/Carry propagate
wire [7:0] G = base & offset;   // Carry generate

/* 
 * Specify each bit in carry chain separately, otherwise
 * verilator complains of loops.
 *
 * Even though the code is written as a ripple carry, 
 * XST optimizes to lookahead carry. 
 * 
 * I would rather have used a regular '+' operator, but 
 * XST makes a mess of it.
 */

wire C1 = (CI & P[0]) | G[0];
wire C2 = (C1 & P[1]) | G[1];
wire C3 = (C2 & P[2]) | G[2];
wire C4 = (C3 & P[3]) | G[3];
wire C5 = (C4 & P[4]) | G[4];
wire C6 = (C5 & P[5]) | G[5];
wire C7 = (C6 & P[6]) | G[6];

assign CO = (C7 & P[7]) | G[7];

/*
 * EAL is the effective address: 
 * EAL = base + offset + CI. 
 */
wire [7:0] EAL = P ^ { C7, C6, C5, C4, C3, C2, C1, CI };

always @(*)
    case( op )
        AB_BRK1   :                     oe_pcl = 1;
        AB_JSR1   :                     oe_pcl = 1;
        default   :                     oe_pcl = 0;
    endcase

/*
 * determine base register. Bit of ugly hack using
 * partial op[] vector in order to get a complete case
 * with best optimization.
 */

always @(*)
    casez( op[4:3] )
        0 :                             base = AHL;
        1 :    case( op[1:0] )
                   0 :                  base = DB;
                   1 :                  base = 8'hfa;
                   2 :                  base = 8'hfc;
                   3 :                  base = 8'hfe;
               endcase
        2:                              base = PCL;
        3:                              base = SPL;
    endcase

/*
 * adjust stack pointer. If load_spl, then we load
 * the stack pointer from the special bus (which presumably
 * outputs the X register).
 *
 * Otherwise increment/decrement for pull/push
 */
always @(posedge clk)
    if( RDY )
        if( load_spl )                  SPL <= SB;
        else case( op )
            AB_RTS0, 
            AB_PLA:                     SPL <= SPL + 1;

            AB_BRK, 
            AB_BRK1, 
            AB_JSR0, 
            AB_PHA :                    SPL <= SPL - 1;
        endcase

/*
 * determine 'use_sb' signal. This signal indicates 
 * whether the 'SB' input needs to be added to base 
 * value.
 */
always @(*)
    case( op )
        AB_ABS0   :                     use_sb = 1; 
        AB_BRA0   :                     use_sb = 1;
        AB_INDX0  :                     use_sb = 1;
        AB_INDX1  :                     use_sb = 1;
        AB_ZPXY   :                     use_sb = 1;
    default:                            use_sb = 0;
    endcase

/* 
 * determine 'load_ahl' signal. If set, we need to load
 * the AHL (address hold) register from DB.
 */
always @(*)
    case( op )
        AB_INDX0,
        AB_ZPXY,
        AB_RTS0,
        AB_PHA,
        AB_BRK,
        AB_DATA,
        AB_TXS,
        AB_FETCH,
        AB_IND0:                        load_ahl = 1;
        default:                        load_ahl = 0;
    endcase

/*
 * determine the 'load_pcl' signal. If set, the current
 * address needs to be copied to program counter
 */
always @(*) 
    case( op )
        AB_ZPXY,
        AB_BRK,
        AB_ABS0,
        AB_JMP0,
        AB_TXS,
        AB_FETCH,
        AB_IND0:                        load_pcl = 1;
        default:                        load_pcl = 0;
    endcase

/*
 * determine the 'CI' (carry in) signal. If set, add
 * one extra to address.
 */
always @(*) 
    case( op )
        AB_INDX0,
        AB_PLA,
        AB_RTS0,
        AB_RTS1:                        CI = 1;
        default:                        CI = 0;
    endcase

/*
 * update AHL (address hold) from DB.
 */
always @(posedge clk)
    if( RDY & load_ahl )                AHL <= DB; 

/*
 * update PCL (program counter low). Normally we use
 * current ABL + 1, but during interrupts (not BRK)
 * don't increment.
 *
 * Note that clock is updated on falling edge, so we 
 * can take the previously calculated address from
 * the register.
 */
always @(negedge clk)
    if( RDY )
        if( irq )                       PCL <= ABL;
        else if( load_pcl )             PCL <= PCL1;

/*
 * load ABL (address bus low) with effective address
 */
always @(posedge clk)
    if( RDY & load_abl )                ABL <= EAL;

endmodule
