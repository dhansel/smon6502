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

If you are using Ben Eater's standard setup (16k RAM at $0-$3FFF, VIA at $6000, ROM at $8000-$FFFF)
you can just download the [smon.bin](https://github.com/dhansel/smon6502/raw/main/smon.bin) file from
this repository and burn it to the EEROM.

Connect a serial port to the VIA as follows: Receive (RX) pin of the serial port goes to pin 19 (CB2)
of the VIA. Transmit (TX) pin of the serial port goes to pin 18 (CB1) **and** pin 17 (PB7) of the VIA.
Configure your terminal program for 1200 baud, 8 data bits, 1 stop bit and no parity. After turning
on the 6502 you should see SMON showing the 6502 register contents and command prompt.

If you are using a non-standard setup, SMON can easily be adapted by changing the settings
in the `config.asm` file (see below).

## Basic usage

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

The code here is based on a (partially) commented [disassembly of SMON](https://github.com/cbmuser/smon-reassembly/blob/master/smon_acme.asm)
by GitHub user Michael ([cbmuser](https://github.com/cbmuser)).

The [code](https://github.com/dhansel/smon6502/blob/main/uart_via.asm) for handling RS232 communication via the 6522 VIA chip was taken
and (heavily) adapted from the VIC-20 kernal, using Lee Davidson's 
[commented disassembly](https://www.mdawson.net/vic20chrome/vic20/docs/kernel_disassembly.txt).
