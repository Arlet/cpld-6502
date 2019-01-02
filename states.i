parameter 
    FETCH   = 4'b0000,
    DATA    = 4'b0001,
    DECODE  = 4'b0010,
    STK1    = 4'b0100,
    INDX0   = 4'b0110,
    ABS0    = 4'b1000,
    STK2    = 4'b1001,
    BRA0    = 4'b1010,
    STK0    = 4'b1100,
    IND0    = 4'b1110;

parameter
    SEL_0   = 3'd0,
    SEL_MEM = 3'd1,
    SEL_CMP = 3'd2,
    SEL_ADD = 3'd3,
    SEL_CPX = 3'd4,
    SEL_INX = 3'd5,
    SEL_CPY = 3'd6,
    SEL_INY = 3'd7;

parameter
    LD_A    = 3'd1,
    LD_X    = 3'd2,
    LD_Y    = 3'd3,
    LD_M    = 3'd4;

parameter
    OP_AI   = 3'd0,
    OP_ROR  = 3'd1,
    OP_ROL  = 3'd2,
    OP_AND  = 3'd3,
    OP_EOR  = 3'd5,
    OP_ORA  = 3'd4,
    OP_ADC  = 3'd6,
    OP_BCD  = 3'd7;

parameter
    AB_RTS1   = 5'b00000,
    AB_INDX0  = 5'b00001,
    AB_INDX1  = 5'b00011,
    AB_RMW    = 5'b00101,
    AB_ABS0   = 5'b00110,
    AB_JMP0   = 5'b00111,

    AB_ZPXY   = 5'b01000,
    AB_BRK2   = 5'b01011,
    AB_RST    = 5'b01110,
    AB_NMI    = 5'b01101,

    AB_FETCH  = 5'b10000,
    AB_IRQ0   = 5'b10001,
    AB_JSR1   = 5'b10010,
    AB_DATA   = 5'b10011,
    AB_TXS    = 5'b10100,
    AB_IND0   = 5'b10101,
    AB_BRA0   = 5'b10110,

    AB_PHA    = 5'b11000,
    AB_PLA    = 5'b11001,
    AB_BRK    = 5'b11010,
    AB_JSR0   = 5'b11011,
    AB_RTS0   = 5'b11100,
    AB_BRK1   = 5'b11101;

