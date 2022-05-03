# cpld-6502
A verilog model of the 6502 CPU designed to fit in 4 small CPLDs, supporting BCD and RDY signal,
and also a few 65C02 instructions (BRA/PHX/PHY/PLX/PLY)

This version consists of 4 separate modules, each designed to run in a single XC9572XL CPLD.

![Block Diagram](http://c-scape.nl/arlet/6502/cpld-block-diagram.png)

The 4 parts are:

## CTL
The control unit. This module contains the instruction decoding, flags, and control signals for the other 3 modules.  It is connected to the general data bus (DB). 
It sends a 5-bit control signal (AB_OP) to both ABL and ABH modules, as well as three 3-bit control signals to the ALU. The control unit also does the reset and 
interrupt handling.

## ALU
The ALU, including the A, X and Y registers. It receives control
information from the CTL module, and sends back the flag status.
It is connected to the data bus (DB) as well as through the special bus (SB) 
to the ABL module. The SB is bidirectional. In most cases, data flows
from ALU to ABL sending X, Y index registers or memory byte, but flow is reversed
to get access to stack pointer for TSX instruction.

## ABL
The module that is responsible for generating the low 8 bits of the address bus.
It also contains the stack pointer. It communicates with ALU over the Special
Bus, receiving X/Y values for offset calculation, or sending stack pointer 
value for TSX instruction. All address calculations are done here, including
indexed addressing and branch target, as well as program counter (bottom part)
updates. It is connected to data bus (DB), lower part of address bus (ABL), and
SB, leaving only a few pins for control and status. It sends 2 carry signals 
(one for address, one for program counter) to ABH.

## ABH
The module that is responsible for generation high 8 bits of the address bus. 
Because this module needs the fewest pins and resources, it can also do some 
board specific work as clock divider and chip select (and maybe some I/O).

The cpu.v module shows the interconnections. This project also includes an IO module with very
simple UART and SPI peripheral that may be useful.

### DB (data bus)
The data bus is attached to all 4 modules. It is only used for reading/writing memory. Each of the four units can
access the data bus for both reading and writing. Both the ABL and ABH monitor the DB to pick up address values, 
the CTL unit reads DB for instructions, and the ALU reads DB for any operation involving memory operands. Each unit can 
also write the bus: the ABH/ABL modules write the upper and lower part of the PC to the stack during JSR/BRK, the ALU 
writes registers to memory, and the CTL module writes the flags to the stack.

### Cycle counts
For purpose of minimizing design, I did not keep the original cycle count. Instead, some
of the dead cycles were removed.

- implied instructions only take a single cycle (except for PHx/PLx which take 3). 
- ZP, X takes 3 cycles (same as ZP). The X offset is added at the same time.
- (ZP,X) takes 5 cycles
- DEC ZP takes 4 cycles, as does DEC ZP,X. DEC ABS takes 5 cycles.
- no penalty for page boundary crossing.
- JSR takes 5 cycles, RTS takes 4.

In fact, the only redundant cycles are in the implied single byte push/pull instructions (PHA/PLA and friends). 
These instructions fetch the next opcode, perform the stack access, and then fetch next opcode again.

### Test board

Here's picture of a board that I made to test the design on real hardware.
![Test board](http://c-scape.nl/arlet/6502/CPLD-6502.JPG)

Have fun. 
