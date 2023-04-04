# SMON

SMON is a machine language monitor and direct assembler for the Commodore 64,
published in 1984 in the German magazin 64'er (for more info see credits).

In a nutshell, SMON provides the following functionality:
  - View and edit data in memory
  - Disassemble machine code
  - Write assembly code directly into memory (direkt assembler with support for labels)
  - Powerful search features
  - Moving memory, optionally with translation of absolute addresses
  - Trace (single-step) through code
  - Set breakpoint or run to a specific address and continue in single-step mode

The best description of SMON's commands and capabilities is the article in the
64'er magazine (in German) [available here](https://archive.org/details/64er_sonderheft_1985_08/page/n121/mode/2up).
For English speakers, C64Wiki has a brief [overview of SMON commands](https://www.c64-wiki.com/wiki/SMON).

## SMON for 6502

The version published here is an adaptation of SMON for a simple MOS6502-based 
computer, such as the one built by [Ben Eater](https://eater.net/6502) in his 
[YouTube video series](https://www.youtube.com/watch?v=LnzuMJLZRdU&list=PLowKtXNTBypFbtuVMUVXNR0z1mu7dp7eH).
The following original SMON functions are **not** available in this version:
  - Loading and saving programs/data to disk or tape (L/S/I commands)
  - Sending output to a printer (P command)
  - Producing BASIC DATA statements for memory content (B command)
  - Disk monitor mode and other extensions
  
The following new commands have been added in this version
  - H - show a help screen with a brief overview of available commands
  - L - load files in Intel HEX format into the 6502 by pasting them into the terminal
  - MS - check and print size of installed memory
  - MT - test memory

## Installing and running SMON 6502

If you are using Ben Eater's standard setup (16k RAM at $0-$3FFF, VIA at $6000, ROM at $8000-$FFFF, 1MHz clock)
you can just download the [smon.bin](https://github.com/dhansel/smon6502/raw/main/smon.bin) file from
this repository and burn it to the EEROM.

Connect a serial port to the VIA as follows: Receive (RX) pin of the serial port goes to pin 19 (CB2)
of the VIA. Transmit (TX) pin of the serial port goes to pin 18 (CB1) **and** pin 17 (PB7) of the VIA.
Configure your terminal program for 1200 baud, 8 data bits, 1 stop bit and no parity. After turning
on the 6502 you should see SMON showing the 6502 register contents and command prompt.

If you are using a non-standard setup, SMON can easily be adapted by changing the settings
in the `config.asm` file (see below).

## Basic usage

At startup, SMON shows the current 6502 processor status, followed by a "." command prompt
```
  PC  SR AC XR YR SP  NV-BDIZC
;E00B B4 E7 00 FF FF  10110100
.                             
```
Where "PC" is the program counter, "SR" is the status register, "AC" is the accumulator, "XR" and "YR" are
the X and Y registers and "SP" is the stack pointer. the "NV-BDIZC" column shows the individual bits
in the status register.

At the command prompt you can enter commands. For example, entering "m 1000 1020" will show the memory
content from $1000-$1020:
```
.m 1000 1030                                                                    
:1000 00 01 02 03 04 05 06 07  08 09 0A 0B 0C 0D 0E 0F         ........ ........
:1010 10 11 12 13 14 15 16 17  18 19 1A 1B 1C 1D 1E 1F         ........ ........
:1020 20 21 22 23 24 25 26 27  28 29 2A 2B 2C 2D 2E 2F          !"#$%&' ()*+,-./
```
The column on the right shows the (printable) ASCII characters corresponding to the data bytes.

If your terminal supports the VT100 cursor movement sequences, you can **modify** the memory
content by just moving the cursor into the displayed lines, editing data and pressing ENTER
on each line where data was modified. If your terminal does not support cursor keys you can
modify memory by typing (for example) `:1015 AA BB` and pressing ENTER. The example here will 
set $1015 to AA and $1016 to BB.

If you supply only one argument to the "m" command, SMON will show the memory content line-by-line,
stopping after each line. Press SPACE to advance to the next line, ESC to go back to the command prompt
or any other key to keep displaying memory without pausing (press SPACE to pause the scrolling display).

The "d" (disassemble) command will disassemble code in memory, for example:
```
.d f000
,F009  A9 FF     LDA #FF
,F00B  A2 04     LDX #04
,F00D  95 FA     STA   FA,X
,F00F  CA        DEX
,F010  D0 FB     BNE F00D
```
You can use the cursor keys to move over the displayed assembly statements and their arguments and modify 
them (assuming the code is in RAM).

You can use the "a" (assemble) command to assemble code directly into memory. SMON will show the current
address as a prompt and you can enter an assembly statement (e.g. `LDX #12`). Press ENTER and SMON will
assemble it, place it directly in memory, and advance the address to the next location according to the
previous opcode's size. To exit assembly mode, type "f" as the opcode. SMON will then show you the full
disassembly of the code you entered, in which you can edit again. For example:
```
.a 2000                  
 2000  ldx #00 
 2002  inx     
 2003  bne 2002
 2005  brk     
 2006 f                  
,2000  A2 00     LDX #00 
,2002  E8        INX     
,2003  D0 FD     BNE 2002
,2005  00        BRK     
```

To run your code just enter `g 2000`. Note that to jump back into SMON after your code
finishes, it should end with a `BRK` instruction.

SMON also allows you to single-step through code using the `tw` (trace walk) command. For example:

```
  PC  SR AC XR YR SP  NV-BDIZC
;2002 23 E7 00 FF FF  00100011
.tw 2000                      
 2002 23 E7 00 FF FF  INX     
 2003 21 E7 01 FF FF  BNE 2002
 2002 21 E7 01 FF FF  INX     
 2003 21 E7 02 FF FF  BNE 2002
 2002 21 E7 02 FF FF  INX     
 2003 21 E7 03 FF FF  BNE 2002
```

After entering the `tw` command, SMON executes the first opcode and stops after
finishing it and displays the next opcode (the first opcode is not shown).
It also shows you the processor registers in the same order as they appear in the
register display line. Press any key to advance one step or ESC to stop.
If the next command is a `JSR`, press 'j' to "jump" over the subroutine and
continue after it finishes (this only works if the `JSR` command is located in RAM).

SMON has a number of other "trace" related commands, a range of "find"
commands to examine memory and several other commands. To get a quick overview
of commands type "h" at the command line. For a bit more information on each command,
refer to the [C64Wiki](https://www.c64-wiki.com/wiki/SMON) page or for the full description 
read the [64er article](https://archive.org/details/64er_sonderheft_1985_08/page/n121/mode/2up) 
(in German).


## Configuring SMON 6502

There are three basic settings that can be changed by modified by changing 
  - RAM size (default: 16k). RAM is assumed to occupy the address space from $0 to the RAMTOP setting.
    For example, if you have 32K of RAM then set RAMTOP to $7FFF
  - VIA location (default: $6000). Change this if the location of the VIA differs from the default setting.
  - UART driver. Communication with SMON works via RS232 protocol. By default, SMON is configured to
    use the 6522 VIA as a pseudo UART. Alternatively, a Motorola MC6850 UART can be used by changing the
    corresponding setting in config.asm. Support for other UARTs can easily be implemented by adjusting
    the uart_6850.asm file to your specific UART.

## Compiling SMON 6502

To produce a binary file that can be programmed into an EEPROM for the 6502 computer,
do the following:
  1. Download the `*.asm` files from this repository (there are only 6)
  2. Download the VASM compiler ([vasm6502_oldstyle_Win64.zip](http://sun.hasenbraten.de/vasm/bin/rel/vasm6502_oldstyle_Win64.zip)).
  3. Extract `vasm6502_oldstyle.exe` from the archive and put it into the same directory as the .asm files
  4. Issue the following command: `vasm6502_oldstyle.exe -dotdir -Fbin -o smon.bin smon.asm`

Then just burn the generated smon.bin file to the EEPROM using whichever programmer
you have been using.

## Credits

The SMON machine language monitor was originally published in three parts in the 
[November](https://archive.org/details/64er_1984_11/page/n59/mode/2up)
/ [December](https://archive.org/details/64er_1984_12/page/n59/mode/2up)
/ [January](https://archive.org/details/64er_1985_01/page/n68/mode/2up)
1984/85 issues of German magazine "[64er](https://www.c64-wiki.com/wiki/64%27er)".

SMON was written for the Commodore 64 by Norfried Mann and Dietrich Weineck.

The [code](https://github.com/dhansel/smon6502/blob/main/smon.asm) here is based 
on a (partially) commented [disassembly of SMON](https://github.com/cbmuser/smon-reassembly/blob/master/smon_acme.asm)
by GitHub user Michael ([cbmuser](https://github.com/cbmuser)).

The [code](https://github.com/dhansel/smon6502/blob/main/uart_via.asm) for handling RS232 communication via the 6522 VIA chip was taken
and (heavily) adapted from the VIC-20 kernal, using Lee Davidson's 
[commented disassembly](https://www.mdawson.net/vic20chrome/vic20/docs/kernel_disassembly.txt).
