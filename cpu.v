/*
 * verilog model of 6502 CPU, using 4 interconnected
 * CPLDs (XC9572XL)
 * 
 * This file defines the board netlist, and also 
 * top level module for simulation 
 *
 * (C) Arlet Ottens, <arlet@c-scape.nl>
 *
 */

module cpu( clk, RST, AB, DB, WE, IRQ, NMI );

`include "states.i"

input clk;              // CPU clock 
input RST;              // reset signal
output [15:0] AB;       // address bus
inout  [7:0] DB;        // data bus
output WE;              // write enable
input IRQ;              // interrupt request
input NMI;              // non-maskable interrupt request (not yet implemented)

wire tsx;               // 0: ALU->ABL, 1: ABL->ALU (TSX)
wire [7:0] SB;

wire [4:0] ab_op;
wire abl_co;
wire abl_pcl8;

/* ALU CONTROLS */
wire [2:0] alu_op;
wire [2:0] alu_sel;
wire [2:0] alu_ld;

/* ALU flag bits */
wire alu_ci;
wire alu_co;
wire alu_n;
wire alu_z;
wire alu_v;

wire RDY;

integer cycle;

always @( posedge clk )
    cycle <= cycle + 1;

always @( posedge clk )
      $display( "%d %8s AB:%04x [%d] DB:%02x PC:%02x%02x IR:%02x %d SEL:%d+%d OP:%d DST:%d DL:%02x BI:%02x ALU:%02x WE:%d PLP:%d AHL:%02x SB:%02x S:%02x A:%02x X:%02x Y:%02x %d:CNZDIV: %d%d%d%d%d%d (%d) IRQ:%h RDY:%h", 
        cycle,
        statename, AB, ab_op, DB, abh.PCH, abl.PCL, ctl.IR, ctl.load_ir, alu_sel, alu_ci, alu_op, alu_ld, alu.M, alu.BI, alu.ADD, WE, ctl.load_p,
        abl.AHL, SB, abl.SPL, alu.A, alu.X, alu.Y, ctl.load_p, 
        ctl.C, ctl.N, ctl.Z, ctl.D, ctl.I, ctl.V, ctl.cond_true, IRQ, RDY );

/*
 * =====================
 *    ADDRESS BUS HIGH 
 * =====================
 */
abh abh( 
    .clk(clk),
    .ABH(AB[15:8]),
    .op(ab_op),
    .PCL8(abl_pcl8),
    .SB7(SB[7]),
    .CI(abl_co),
    .RDY(RDY),
    .DB(DB) );

/*
 * =====================
 *    ADDRESS BUS LOW
 * =====================
 */
abl abl( 
    .clk(clk),
    .ABL(AB[7:0]),
    .op(ab_op),
    .PCL8(abl_pcl8),
    .CO(abl_co),
    .SB_DIR(tsx),
    .DB(DB),
    .RDY(RDY),
    .SB(SB) );

/*
 * =====================
 *    CONTROL LOGIC
 * =====================
 */
ctl ctl(
    .clk(clk),
    .RST(RST),
    .RDY(RDY),
    .IRQ(IRQ),
    .WE(WE),
    .ab_op(ab_op),
    .alu_sel(alu_sel),
    .alu_op(alu_op),
    .alu_ld(alu_ld),
    .alu_ci(alu_ci),
    .alu_co(alu_co),
    .alu_n(alu_n),
    .alu_v(alu_v),
    .alu_z(alu_z),
    .tsx(tsx),
    .DB(DB) );

/*
 * =====================
 *          ALU
 * =====================
 */
alu alu(
    .clk(clk),
    .sel(alu_sel),
    .op(alu_op),
    .op_ld(alu_ld),
    .CI(alu_ci),
    .CO(alu_co),
    .N(alu_n),
    .V(alu_v),
    .Z(alu_z),
    .SB_DIR(tsx),
    .SB(SB),
    .RDY(RDY),
    .DB(DB) );


/*
 * easy to read names in simulator output
 */
reg [8*6-1:0] statename;

always @*
    case( ctl.state )
            FETCH:  statename = "FETCH";
            DECODE: statename = "DECODE";
            DATA:   statename = "DATA";
            ABS0:   statename = "ABS0";
            IND0:   statename = "IND0";
            INDX0:  statename = "INDX0";
            STK0:   statename = "STK0";
            STK1:   statename = "STK1";
            STK2:   statename = "STK2";
            BRA0:   statename = "BRA0";
    endcase

endmodule
