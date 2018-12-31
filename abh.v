/*
 * address bus high : handles high 8 bits of address bus
 *
 * Also does a bit of address decoding for RAM/ROM, and adds
 * a wait state when accessing ROM (= Flash).
 *
 * (C) Arlet Ottens <arlet@c-scape.nl>
 */

module abh( 
    input clk,
    input clk4,
    output reg clk_out,
    output reg [7:0] ABH,
    inout [7:0] DB,
    input CI,
    output RDY,
    input SB7,                  // bit 7 of SB (branch offset)
    input PCL8,
    input button,
    input WE,
    output OE,
    output reg RAM,
    output reg ROM,
    input [4:0] op
);

`include "states.i"

initial ABH = 8'hf0;

reg [7:0] PCH = 8'hf0;          // program counter 

// synthesis attribute KEEP of load_pch is TRUE
// synthesis attribute KEEP of load_abh is TRUE
// synthesis attribute KEEP of write_pch is TRUE
// synthesis attribute KEEP of DB_CI is FALSE 
// synthesis attribute KEEP of sel is TRUE
// synthesis attribute KEEP of irq is TRUE
// synthesis attribute KEEP of PCB is TRUE
// synthesis attribute KEEP of RDY2 is TRUE

reg load_pch;
wire [7:0] DB_CI = DB + CI;
reg [7:0] PCB;
reg [2:0] sel;
wire write_pch = (op == AB_JSR0);
wire load_abh = (op != AB_RMW);
wire irq = ( op == AB_IRQ0 );

reg sel_lsb, sel_map;
reg map_rom = 1;
wire RDY2;

assign OE = !WE;

assign RDY = RDY2; 

reg waitstate;

reg [1:0] delay;

/*
 * optional clock divider
 */
always @(posedge clk4)
    delay <= delay + 1;

/*
 * some RDY and chip select logic for my board
 */
always @(posedge clk)
    if( RDY2 )                          waitstate <= 1;
    else                                waitstate <= 0; 

assign RDY2 = button & (ROM | !waitstate);

always @* 
    if( !WE )                           RAM = 0;        // always write to RAM
    else if( ABH <= 8'hCE )             RAM = 0;        // read from RAM between 0000-CEFF
    else if( ABH == 8'hff )             RAM = map_rom;  // select RAM if button is pushed
    else                                RAM = 1;        

always @* 
    if( !ABH[7] )           			ROM = 1;        // ignore bottom half
    else if( ABH == 8'hCF ) 			ROM = 1;        // don't write to CFxx
    else if( !WE )          			ROM = 0;        // always write to rest (shadow) Flash
    else if( ABH == 8'hFF ) 			ROM = !map_rom; // don't read from top page 
    else if( ABH <= 8'hCF ) 			ROM = 1;        // don't read from 0000-CFFFF
    else                    			ROM = 0;        // do read from D000-FEFF

assign DB = write_pch ? PCH : 8'hZZ;

/*
 * listen to bus transactions. 
 * if we see F0, CF on the databus, followed by a write
 * assume it's a write to our CFF0 map register
 *
 * board specific
 */

always @(posedge clk)
    if( RDY2 )                          sel_lsb <= DB == 8'hF0;

always @(posedge clk)
    if( RDY2 )                          sel_map <= sel_lsb & (DB == 8'hCF);

always @(posedge clk)
    if( RDY2 )
        if( op == AB_RST )              map_rom <= 1;
        else if( sel_map && ~WE )       map_rom <= DB[0];

/*
 * generate main clock. Note that clk_out is 
 * fed back externally to clk input so we can use
 * the global clock input.
 */
always @(posedge clk4)
    //if( delay == 0 )
        clk_out <= ~clk_out;

/*
 * use intermediate 'sel' to reduce expressions. This needs to
 * be cleaned up a bit more.
 */
always @* begin
    sel = 0;
    case( op )
        AB_INDX0    :                   sel = 0;
        AB_ZPXY 	: 					sel = 0;
        AB_PLA  	: 					sel = 1;
        AB_RTS0 	: 					sel = 1;
        AB_PHA  	: 					sel = 1;
        AB_BRK      : 					sel = 1;
        AB_BRK1 	: 					sel = 1;
        AB_JSR0 	: 					sel = 1;
        AB_JMP0 	: 					sel = 2;
        AB_RTS1 	: 					sel = 2;  
        AB_INDX1    : 					sel = 2;
        AB_ABS0 	: 					sel = 2;
        AB_DATA 	: 					sel = 3;
        AB_IRQ0     : 					sel = 3;
        AB_FETCH    : 					sel = 3;
        AB_JSR1 	: 					sel = 3;
        AB_TXS      : 					sel = 3;  // check these
        AB_IND0     : 					sel = 3;
        AB_BRA0 	: if( SB7 & ~CI ) 	sel = 6; // backwards and no carry
                      else if( ~SB7 & CI )
                                        sel = 6; // forwards and carry 
                      else              sel = 3; 
        AB_RST      : 					sel = 4;
        AB_NMI      : 					sel = 4;
        AB_BRK2 	: 					sel = 4;

    default:          					sel = 0;
    endcase
end

/*
 * calculate PC branch target
 */
always @*
    if( SB7 & ~CI )                     PCB = PCH - 1;
    else                                PCB = PCH + 1;

always @(posedge clk)
    if( RDY2 & load_abh )
    case( sel )
        0   :                           ABH <= 0;           // zero page
        1  	: 						    ABH <= 1;           // stack
        2 	: 						    ABH <= DB_CI;       // DB + Carry In
        3   : 						    ABH <= PCH;         // program counter
        4   : 						    ABH <= 8'hff;       // vectors
        5   : 						    ABH <= 0;           // don't care
        6   : 				            ABH <= PCB;         // PC after branch
    endcase

/*
 * update PCH (program counter high)
 */
always @(negedge clk)
    if( RDY2 )
        if( irq )                       PCH <= ABH;
        else if( load_pch )             PCH <= ABH + PCL8; 

/*
 * determine whether program counter should be updated
 */
always @(*) 
    case( op )
        AB_ZPXY,
        AB_BRK,
        AB_ABS0,
        AB_TXS,
        AB_FETCH,
        AB_IND0 :                       load_pch = 1;
        default:                        load_pch = 0;
    endcase

endmodule


