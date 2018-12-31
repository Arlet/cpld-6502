/*
 * monitor CPLD.
 * 
 * implements simple UART and SPI output. Assumes 24 MHz clock
 * and 115k2 UART speed.
 *
 * (C) Arlet Ottens <arlet@c-scape.nl>
 */

module monitor( 
    input clk, 
    input rxd_async, 
    output reg txd,
    output reg led,
    input button,

    // SPI
    output reg sck,
    output mosi,
    output reg load,
    
    // CPU bus
    input [15:0] AB,
    inout [7:0] DB, 
    input WE,
    output IRQ );

reg [7:0] DO;
reg rxd;

/*
 * we use memory area of CFF0..CFFF
 *
 * offset 6: spi write register (you can read it back too)
 * offset 7: spi load (on any write)
 * offset 8: uart status (tx_idle in bit 7, rx_ready in bit 6)
 * offset 9: uart data (read and write)
 * 
 */
wire sel = AB[15:4] == 12'hCFF;
wire OE = WE & sel;
assign DB = OE ? DO : 8'hZZ;

wire read  = sel & WE;
wire write = sel & ~WE;

wire rx_read   = read  & (AB[3:0] == 4'h9);
wire tx_write  = write & (AB[3:0] == 4'h9);
wire spi_write = write & (AB[3:0] == 4'h6);
wire spi_load  = write & (AB[3:0] == 4'h7); 
reg [7:0] spi_data;

/*
 * baud rate divider, divide input clock (24 MHz) to get
 * 666.7 kHz UART enable
 */

reg [5:0] div;

wire uart_tick = (div == 35);      

always @(posedge clk)
    if( uart_tick ) 
        div <= 0;
    else
        div <= div + 1;

/*
 * sync rxd on clock
 */

always @(negedge clk)
    rxd <= rxd_async;

reg [7:0] rx_data;
reg [5:0] rx_state = 6'd63;    // number of baud rate ticks
wire [7:0] rx_buf = rx_data;

// synthesis attribute KEEP of rx_ready is TRUE
reg rx_ready;
wire rx_idle  = (rx_state == 6'd54);
wire rx_done  = (rx_state == 6'd49);

/*
 * transmit signals
 */

reg [5:0] tx_state;
reg [7:0] tx_data;

wire tx_idle = (tx_state == 63);


/*
 * data output to CPU
 */
always @*
    case( AB[3:0] )
        6:              DO = spi_data;
        8:              DO = {tx_idle, rx_ready, 6'b0};
        9:              DO = rx_buf;
    default:            DO = 0;
    endcase

assign IRQ = !rx_ready;

/*
 * SPI output
 */

reg [2:0] spi_count;
reg spi_active;

always @(negedge clk)
    if( spi_active )
        sck <= !sck;

always @(posedge clk)
    if( spi_write ) begin
        spi_data <= DB;
    end

always @(posedge clk)
    if( spi_write )
        spi_count <= 7;
    else if( !sck && spi_count > 0 )
        spi_count <= spi_count - 1;

assign mosi = ~spi_data[spi_count];

always @(posedge clk)
    load <= spi_load & ~spi_active;

always @(posedge clk)
    if( spi_write )
        spi_active <= 1;
    else if( ~sck  && spi_count == 0 )
        spi_active <= 0;

/* 
 * UART receiver, fixed at 115k2 bits/sec, 8 bits, 1 stop bit
 *
 * Note that UART receive data is not buffered, so get it quickly
 * You can add an extra buffer.
 */

always @(posedge clk)
    if( uart_tick )
        if( !rx_idle )                              rx_state <= rx_state + 1;
        else if( !rxd )                             rx_state <= 0;              // start bit

always @(posedge clk)
    if( rx_read )                                   rx_ready <= 0;
    else if( uart_tick && rx_done )                 rx_ready <= 1;

always @(posedge clk)
    led <= spi_write;

always @(posedge clk)
    case( rx_state )
        7:                                          rx_data[0] <= rxd;
        13:                                         rx_data[1] <= rxd;
        19:                                         rx_data[2] <= rxd;
        25:                                         rx_data[3] <= rxd;
        31:                                         rx_data[4] <= rxd;
        36:                                         rx_data[5] <= rxd;
        42:                                         rx_data[6] <= rxd;
        48:                                         rx_data[7] <= rxd;
    endcase

/*
 * UART transmitter
 */

always @(posedge clk )
    if( tx_write )
        tx_data = DB;

always @(posedge clk )
    case( tx_state )
        0: txd <= 0;                // start bit
        6: txd <= tx_data[0];
       12: txd <= tx_data[1];
       17: txd <= tx_data[2];
       23: txd <= tx_data[3];
       29: txd <= tx_data[4];
       35: txd <= tx_data[5];
       41: txd <= tx_data[6];
       46: txd <= tx_data[7];
       52: txd <= 1;                // stop bit
    endcase

always @(posedge clk) 
    if( tx_write & tx_idle )
        tx_state <= 0;
    else if( uart_tick & !tx_idle )
        tx_state <= tx_state + 1;

endmodule
