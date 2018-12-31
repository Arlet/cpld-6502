# cpld-6502
A verilog model of the 6502 CPU designed to fit in 4 small CPLDs, supporting BCD and RDY signal,
and also a few 65C02 instructions (BRA/PHX/PHY/PLX/PLY)

This version consists of 4 separate modules, each designed to run in a single XC9572XL CPLD.

The 4 parts are:

    CTL - The control unit. This module contains the instruction
          decoding, flags, and control signals for the other 3 modules.
          It is connected to the general data bus (DB).

    ALU - The ALU, including the A, X and Y registers. It receives control
          information from the CTL module, and sends back the flag status.
          It is connected to the data bus (DB) as well as through the special bus (SB) 
          to the ABL module. The SB is bidirectional. In most cases, data flows
          from ALU to ABL sending X, Y index registers or memory byte.

    ABL - The module that is responsible for generating the low 8 bits of the address bus.
          It also contains the stack pointer. It communicates with ALU over the Special
          Bus, receiving X/Y values for offset calculation, or sending stack pointer 
          value for TSX instruction. All address calculations are done here, including
          indexed addressing and branch target, as well as program counter (bottom part)
          updates. It is connected to data bus (DB), lower part of address bus (ABL), and
          SB, leaving only a few pins for control and status. It sends 2 carry signals 
          (one for address, one for program counter) to ABH.

    ABH - The module that is responsible for generation high 8 bits of the address bus. 
          Because this module needs the fewest pins and resources, it can also do some 
          board specific work as clock divider and chip select (and maybe some I/O).

The cpu.v module shows the interconnections.

Have fun. 
