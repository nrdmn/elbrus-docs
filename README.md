# Elbrus architecture


## Overview

Elbrus 2000 (Elbrus or e2k for short), is a SPARC-inspired VLIW architecture
developed by the [Moscow Center for SPARC Technology (MCST)](http://mcst.ru/).

Elbrus machine code is organized into [very long instruction words (VLIW)](https://en.wikipedia.org/wiki/Very_long_instruction_word),
which consist of multiple so-called syllables that are executed together.

### References

Several useful documents about Elbrus are available on the internet, albeit
mostly in Russian.

- [Руководство по эффективному программированию на платформе «Эльбрус» (elbrus-prog)](http://ftp.altlinux.org/pub/people/mike/elbrus/docs/elbrus_prog/html/)
- [Микропроцессоры и вычислительные комплексы семейства «Эльбрус»](http://www.mcst.ru/doc/book_121130.pdf)
- A series of articles about porting [Embox](https://www.embox.rocks/) to Elbrus:
  [introduction](https://habr.com/ru/company/embox/blog/421441/),
  [part 1](https://habr.com/ru/company/embox/blog/447704/),
  [part 2](https://habr.com/ru/company/embox/blog/447744/),
  [part 3](https://habr.com/ru/company/embox/blog/485694/)
- Pictures of [various](https://www.zvezdasp.ru/products/vychislitelnyy-kompleks-elbrus) [Elbrus](https://www.zvezdasp.ru/products/kompyutery-serii-elbrus)
  [mainboards](https://www.zvezdasp.ru/products/moduli-protsessornye)


## Memory organization

Most operations in Elbrus code either:

- Take the values of one or more registers, compute a function, and write the
  result to another register, or
- Load a value from memory into a register or store a value from a
  register into memory.


### Register file, RF (Регистровый файл , РгФ)

The 256 general-purpose registers of the Register File (RF/РгФ) are divided
into two categories:

- 224 registers are part of the _procedure stack_ in a
  [windowed](https://en.wikipedia.org/wiki/Register_window) way. They can
  become available or unavailable during procedure calls and returns.
  (See also [elbrus-prog chapter 9.3.1.1](http://ftp.altlinux.org/pub/people/mike/elbrus/docs/elbrus_prog/html/chapter9.html#mech-register-window))
- 32 registers are global registers. They are available during the whole
  runtime of a program.

 32-bit | 64-bit | description
--------|--------|-----------------------------------
 `%g0`  |`%dg0`  | Global register (0-31)
 `%r0`  |`%dr0`  | Procedure stack register, relative to start of current window
 `%b[0]`|`%db[0]`| [Mobile base registers](http://ftp.altlinux.org/pub/people/mike/elbrus/docs/elbrus_prog/html/chapter9.html#baseregisters), relative to the start of the current window, plus `BR`

TODO: last eight global registers are designated rotatable area


#### Changing the register window

The procedure stack contains parameters and local data of procedures. Its top
area is stored in the register file (RF). On overflow or underflow of the
register file, its contents are automatically swapped in/out of memory. Launch
of a new procedure allocates a window on the procedure stack, which may overlap
with the calling procedure's window.


### Procedure chain stack (стек связующей информации)

Stack of return addresses. It can only be manipulated by the operating system
and the hardware. Its top area is stored in CF (chain file) registers.

On this stack the following information is encoded in two quad words:
- return address
- compilation unit index descriptor (CUIR)
- window base (wbs) in the register file
- presence of real 80 (?)
- predicate file
- user stack descriptor
- rotatable area base
- processor status register

On overflow or underflow of the chain file, its contents are automatically
swapped in/out of memory.


### Predicate file, PF (Предикатный файл, ПФ)

Comparison operations produce one-bit results (true or false) that can be
stored in the predicate registers.

Predicates can be used in conditional control transfers (jumps/calls), or in
the conditional execution of individual operations.

There are 32 predicate registers in the predicate file, which appear as
`%pred0` to `%pred31` in assembly code.


### Special purpose registers

Special purpose registers can be read using the `rrs` and `rrd` operations, and
writing using the `rws` and `rwd` operations.

 Name   | Description
--------|--------------------------------------------------------------
 CUIR   | compilation unit index register, индекс дескрипторов модуля компиляции
 PSHTP  | procedure stack hardware top pointer
 PSP    | procedure stack pointer - contains the virtual base address of the procedure stack.
 WD     | window descriptor - contains the base and the size of the current procedure's window into the procedure stack.
 PCSHTP | procedure chain stack hardware top pointer
 USBR   | user stack base pointer, РгБСП
 USD    | user stack descriptor, ДСП


## Regular Instructions

Elbrus' wide instructions (широкая команда, ШК) are comprised of a header syllable and zero or more additional syllables. Wide instructions are 8 byte aligned and up to 16 words (64 bytes) long.

### Syllables

Abbreviation | Description
-------------|---------------------------------------------------------
HS           | Header syllable - it encodes length and structure of a wide instruction
SS           | Stubs syllable - short operations that take only a few bits to encode
ALS          | Arithmetic logic channel syllable
CS           | Control syllable
ALES         | Arithmetic logic extension channel semi-syllable. They extend corresponding ALS. ALES2 and ALES5 are only available on Elbrus v4 and higher.
AAS          | Array access semi-syllable
LTS          | Literal syllable - literals to be used as operands
PLS          | Predicate logic syllable - processing of boolean values
CDS          | Conditional syllable - specified which operations are to be executed under which condition

The first syllable is the header syllable. It is always present.
Presence of other syllables depend on the purpose of the command.
Syllables occur in the following order:

- HS
- SS
- ALS0, ALS1, ALS2, ALS3, ALS4, ALS5
- CS0, CS1
- ALES2, ALES5
- ALES0, ALES1, ALES3, ALES4
- AAS0, AAS1, AAS2, AAS3, AAS4, AAS5
- LTS3, LTS2, LTS1, LTS0
- PLS2, PLS1, PLS0
- CDS2, CDS1, CDS0

#### Syllable packing

Semi-syllables ALES and AAS are a half-word (2 bytes) long. All other syllables are one word (4 bytes) long.

Syllables SS, ALS\* and CS\* occur as indicated in the header syllable in the order described above.
They are packed, e.g. if header bits indicate presence of ALS0 and ALS2 but not SS nor ALS1, then the syllable ALS0 follows directly after HS and ALS2 follows directly after ALS0.

If presence of ALES2 or ALES5 is indicated, then a whole word is allocated for them, whether both are present or not.
The first of both to be present occupies the more significant half of the word, the second is encoded in the less significant half.
For example, when looking at the syllables as bytes, if ALES2 and ALES5 are present, then the first two bytes of the little endian word contain ALES5 and the last two bytes contain ALES2.
If only ALES5 is present, the first two bytes are empty and the last two bytes contain ALES5.

ALES{0,1,3,4} and AAS\* start at the word indicated by the "middle pointer" from the header syllable. Their ordering is the same as for ALES2 and ALES5 (high half first, low half second) but they are all packed. This means that any two syllables of ALES{0,1,3,4} and AAS{0,1} may share a word. ALES\* may not share a word with AAS{2,3,4,5} because presence of the latter implies presence of AAS0 and/or AAS1.
For example, if ALES0, ALES1, ALES4, AAS0 and AAS2 are indicated, then they are encoded as ALES1, ALES0, AAS0, ALES4, two bytes left empty, and finally AAS2.

LTS\*, PLS\* and CDS\* are decoded starting from the end of the wide command.
CDS\* and PLS\* are not indicated by individual flags but rather by their number. For example, there cannot be a PLS2 without a PLS0 and PLS1.
LTS take any remaining words between the other syllables. For example, if after the AAS there are five words remaining in the wide command and two CDS and one PLS are indicated, then two words for LTS are left. They would be encoded as LTS1, LTS0, PLS0, CDS1, CDS0.

We do not know what happens if more syllables are indicated than there is space allocated or if syllables are encoded to overlap.

#### HS - Header syllable

Bit     | Name          | Description
------- | ------------- | -----------------------------------------------------
   31   | ALS5          | arithmetic-logic syllable 5 presence
   30   | ALS4          | arithmetic-logic syllable 4 presence
   29   | ALS3          | arithmetic-logic syllable 3 presence
   28   | ALS2          | arithmetic-logic syllable 2 presence
   27   | ALS1          | arithmetic-logic syllable 1 presence
   26   | ALS0          | arithmetic-logic syllable 0 presence
   25   | ALES5         | arithmetic-logic extension syllable 5 presence
   24   | ALES4         | arithmetic-logic extension syllable 4 presence
   23   | ALES3         | arithmetic-logic extension syllable 3 presence
   22   | ALES2         | arithmetic-logic extension syllable 2 presence
   21   | ALES1         | arithmetic-logic extension syllable 1 presence
   20   | ALES0         | arithmetic-logic extension syllable 0 presence
 19:18  | PLS           | number of predicate logic syllables
 17:16  | CDS           | number of conditional execution syllables
   15   | CS1           | control syllable 1 presence
   14   | CS0           | control syllable 0 presence
   13   | set\_mark     |
   12   | SS            | stub syllable presence
   11   | --            | unused
   10   | loop\_mode    |
   9:7  | nop           |
   6:4  |               | Length of instruction, in multiples of 8 bytes, minus 8 bytes
   3:0  |               | Number of words occupied by SS, ALS, CS, ALES2, ALES5 - called "middle pointer"

#### SS - Stubs syllable

##### Stubs syllable format 1 - SF1

Bit     | Name     | Description
--------|----------|----------------------------------------------
 31:30  | ipd      | instruction prefetch depth
   29   | eap      | end array prefetch
   28   | bap      | begin array prefetch
   27   | srp      |
   26   | vfdi     |
   25   | crp (?)  |
   24   | abgi     |
   23   | abgd     |
   22   | abnf     |
   21   | abnt     |
   20   | type     | type is 0 for SF1
   19   | abpf     |
   18   | abpt     |
   17   | alcf     |
   16   | alct     |
   15   |          | array access syllable 0 and 2 presence
   14   |          | array access syllable 0 and 3 presence
   13   |          | array access syllable 1 and 4 presence
   12   |          | array access syllable 1 and 5 presence
 11:10  | ctop     | `ctpr` number used in control transfer (`ct`) instructions
   9    | ?        |
   8:0  | ctcond   | condition code for control transfers (`ct`)

##### Stubs syllable format 2 - SF2

Bit     | Name     | Description
--------|----------|----------------------------------------------
 31:30  | ipd      | instruction prefetch depth
 29:28  |          | encodes invts and flushts, see below
   27   | srp (?)  |
   26   |          | encodes invts and flushts, see below
   25   | crp (?)  |
   20   | type     | type is 1 for SF2

`(ss >> 27 & 6) \| (ss >> 26 & 1)`   | Description
-----------------------------------|------------
 2 | `invts`
 3 | `flushts`
 6 | `invts ? %predN`, where N is `ss & 0x1f`
 7 | `invts ? ~ %predN`, where N is `ss & 0x1f`


##### `ct` condition codes

The condition code in the stubs syllable controls under which conditions a
control transfer operation is executed.

 Bit    | description
--------|--------------------------------------------------------------
  4:0   | Predicate number (from `pred0` to `pred31`)
  8:5   | Condition type

 Type |  syntax                       | description
------|-------------------------------|---------------------------------
   0  | --                            | never
   1  |                               | always
   2  | `? %pred0`                    | if predicate is true
   3  | `? ~ %pred0`                  | if predicate is false
   4  | `? #LOOP_END`                 |
   5  | `? #NOT_LOOP_END`             |
   6  | `? %pred0 \|\| #LOOP_END`     |
   7  | `? ~ %pred0 && #NOT_LOOP_END` |
   8  | (TODO, depends on syllable)   |
   9  | (TODO, depends on syllable)   |
  10  | (reserved)                    |
  11  | (reserved)                    |
  12  | (reserved)                    |
  13  | (reserved)                    |
  14  | `? ~ %pred0 \|\| #LOOP_END`   |
  15  | `? %pred0 && #NOT_LOOP_END`   |

`#LOOP_END` and `#NOT_LOOP_END` are sometimes spelled as `%LOOP_END` and `%NOT_LOOP_END`.

#### ALS - Arithmetic-logical syllables

All arithmetic-logical operations that are encoded in ALS are identified by an opcode at `als[30:24]`
and possibly an opcode extension number and/or cmp opcode extension number and/or opcode 2.
The role of the other bits in the ALS depends on the operation's format (ALOPF).

Other variations:
- Some operations require two ALS
- Some operations require a Memory Address Specifier (MAS) in CS1
- Some operations have predicates. Some operations require additional data from CDS.
- ALOPF1, ALOPF2, ALOPF3, ALOPF7, ALOPF8 require no ALES (getsp is an exception), all others seem to require an ALES.

Bit     | Description
------- | -------------------------------------------------------------
   31   | Speculative mode
 30:24  | Opcode
 23:16  | Operand src1, or opcode extension number
 15:8   | Operand src2
  7:0   | Operand src3 or dst

##### Operand roles

 Operand role     | encoded in                                       | description
------------------|--------------------------------------------------|------------------------------------------------------
  src1            | `als[23:16]`                                     | source operand 1
  src2            | `als[15:8]`                                      | source operand 2 - can encode access to literal syllables (LTS)
  src3            | `als[7:0]` or `ales[7:0]`                        | source operand 3 - for ALOPF3 and ALOPF13 it is in ALS, for ALOPF21 it is in ALES
  dst             | `als[7:0]`, or `als[4:0]` for predicate registers| destination register

##### src1 encoding

Pattern   | Range | Description
----------|-------|------------------------------------
0xxx xxxx | 00-7f | Rotatable area procedure stack register
10xx xxxx | 80-bf | procedure stack register
110x xxxx | c0-df | constant between 0 and 31
111x xxxx | e0-ff | global register

##### src2 encoding

src2 that are not status register numbers are encoded as follows:

Pattern   | Range        | Description
----------|--------------|------------------------------------
0xxx xxxx | 00-7f        | Rotatable area procedure stack register
10xx xxxx | 80-bf        | procedure stack register
1100 xxxx | c0-cf        | constant between 0 and 15
1101 0x0x | d0-d1, d4-d5 | reference to 16 bit literal semi-syllable; (1<<2) indicates high half of a LTS; Only in lts0 and lts1.
1101 10xx | d8-db        | reference to 32 bit literal syllable LTS0, LTS1, LTS2, or LTS3
1101 11xx | dc-df        | reference to 64 bit literal syllable pair (LTS0 and LTS1, LTS1 and LTS2, LTS2 and LTS3)
111x xxxx | e0-ff        | global register

##### src3 encoding

Pattern   | Range | Description
----------|-------|------------------------------------
0xxx xxxx | 00-7f | Rotatable area procedure stack register
10xx xxxx | 80-bf | procedure stack register
111x xxxx | e0-ff | global register

##### dst encoding

dst that are not predicate register numbers or status register numbers are encoded as follows:

Pattern   | Range | Description
----------|-------|------------------------------------
0xxx xxxx | 00-7f | Rotatable area procedure stack register
10xx xxxx | 80-bf | procedure stack register
1100 1101 | cd    | %tst
1100 1110 | ce    | %tc
1100 1111 | cf    | %tcd
1101 0001 | d1    | %ctpr1
1101 0010 | d2    | %ctpr2
1101 0011 | d3    | %ctpr3
1101 1110 | de    | %empty.lo
1101 1111 | df    | %empty.hi
111x xxxx | e0-ff | global register

##### Arithmetic-logical operation formats (ALOPF)

Several operand formats are defined:

 Format  | src1 | src2 | src3 | dst | Example            | Comment
---------|------|------|------|-----|--------------------|----------
 ALOPF1  | x    | x    |      | x   | adds, ld{b,h,w,d}  |
 ALOPF2  |      | x    |      | x   | movx, popcnts      | Opcode `getsp` needs ALES even though it is ALOPF2; opcode extension number in `als[23:16]`
 ALOPF3  | x    | x    | x    |     | st{b,h,w,d}        | `src3` in ALS
 ALOPF7  | x    | x    |      | x   | cmposb             | `dst` is a predicate register; `als[7:5]` holds the cmp opcode extension number
 ALOPF8  |      | x    |      | x   | cctopo             | `dst` is a predicate register; `als[7:5]` holds the cmp opcode extension number
 ALOPF11 | x    | x    |      | x   | muls               | Some opcodes require a literal in `ales[7:0]`, all others have an opcode extension number there.
 ALOPF12 |      | x    |      | x   | fsqrts             | The opcode extension number is in `als[23:16]` and `ales[7:0]`. Opcode `pshufh` is special as it requires a literal in `ales[7:0]` instead.
 ALOPF13 | x    | x    | x    |     | stq                | `src3` in ALS
 ALOPF15 |      | x    |      | x   | rws, rwd           | `dst` is a status register; opcode 2 is EXT (1), extension is `0xc0`
 ALOPF16 | x    |      |      | x   | rrs, rrd           | `src2` is a status register; opcode 2 is EXT (1), extension is `0xc0`
 ALOPF17 | x    | x    |      | x   | pcmpeqbop          | `dst` is a predicate register; opcode 2 is EXT1 (2)
 ALOPF21 | x    | x    | x    | x   | incs\_fb           | `src3` in ALES
 ALOPF22 |      | x    |      | x   | movtq              | The opcode extension number is in `als[23:16]`; opcode 2 is EXT (1), the extension field in ALES is set to `0xc0`

TODO: ALOPF5, ALOPF6, ALOPF9, ALOPF10, ALOPF19

It is not clear what the difference between ALOPF1 and ALOPF11 is.

TODO: seems like ALS and ALES can have different opcode extension numbers

#### ALES - Arithmetic-logical extension syllables

Bit     | Description
------- | -------------------------------------------------------------
  15:8  | Opcode 2
   7:0  | src3 (in ALEF1) or extension or cmp opcode extension number (in ALEF2)

 Opcode 2 | Name
----------|-------------
 0x01     | EXT
 0x02     | EXT1
 0x03     | EXT2
 0x04     | FLB
 0x05     | FLH
 0x06     | FLW
 0x07     | FLD
 0x08     | ICMB0
 0x09     | ICMB1
 0x0a     | ICMB2
 0x0b     | ICMB3
 0x0c     | FCMB0
 0x0d     | FCMB1
 0x0e     | PFCMB0
 0x0f     | PFCMB1
 0x10     | LCMBD0
 0x11     | LCMBD1
 0x12     | LCMBQ0
 0x13     | LCMBQ1
 0x16     | QPFCMB0
 0x17     | QPFCMB1

#### CS - Control syllables

CS0 and CS1 encode different operations.

 Syllable | pattern   | name   | description
----------|-----------|--------|----------------------------------------
 CS0, CS1 |`0xxxxxxx` | set\*  | setwd/setbn/setbp/settr
 CS1      |`1xxxxxxx` | vrfpsz | vrfpsz + setwd/setbn/setbp/settr
 CS0      |`2xxxxxxx` | puttsd | puttsd with a multiple-of-8 parameter relative to the start of the current instruction
 CS1      |`200000xx` | setei  |
 CS1      |`28000000` | setsft |
 CS0, CS1 |`300000xx` | wait   | wait for specified kinds of operations to complete
 CS0      |`4xxxxxxx` | disp   | prepare a relative jump in `ctpr1`
 CS0      |`5xxxxxxx` | ldisp  | prepare an array prefetch program (?) in `ctpr1`
 CS0      |`6xxxxxxx` | sdisp  | prepare a system call in `ctpr1`
 CS0      |`70000000` | return | prepare to return from procedure in `ctpr1`
 CS0      |`8xxxxxxx+`| --     | disp/ldisp/sdisp/return with ctpr2
 CS0      |`cxxxxxxx+`| --     | disp/ldisp/sdisp/return with ctpr3
 CS1      |`6xxxx000` | setmas | Set memory address specifier for load and store operations



##### set\*

The set\* operation sets several parameters related to register windows.
Most bits are encoded in the CS0 syllable itself, but some are also read from
the LTS0 syllable.

According to `ldis`, setwd is always performed, but settr, setbn, and setbp
have to be enabled by setting the corrsponding bits in CS0.

 Syl. | bit    | name        | description
------|--------|-------------|-----------------------------------------
 CS1  |     28 |enable vfrpsz|
 CS   |     27 |enable settr |
 CS   |     26 |enable setbn |
 CS   |     25 |enable setbp |
 CS   |  22:18 | setbp psz=x |
 CS   |  17:12 | setbn rcur=x|
 CS   |  11:6  | setbn rsz=x |
 CS   |   5:0  | setbn rbs=x |
 LTS0 |  16:12 |vfrpsz rpsz=x|
 LTS0 |  11:5  | setwd wsz=x |
 LTS0 |     4  | setwd nfx=x |
 LTS0 |     3  | setwd dbl=x |


##### wait

 Bit    | name  | description
--------|-------|------------------------------------------------------
  5     |`ma_c` | wait for all previous memory access operations to complete
  4     |`fl_c` | wait for all previous cache flush operations to complete
  3     |`ls_c` | wait for all previous load operations to complete
  2     |`st_c` | wait for all previous store operations to complete
  1     |`all_e`| wait for all previous operations to issue all possible exceptions
  0     |`all_c`| wait for all previous operations to complete

##### disp/ldisp/sdisp/return

The `disp` operation prepares a jump to a different location by using one of
the control transfer preparation registers (`ctpr1` to `ctpr3`).

 bit    | description
--------|--------------------------------------------------------------
  31:30 | can be 1, 2, or 3 for `ctpr1`, `ctpr2`, or `ctpr3` respectively
  29:28 | can be 0, 1, 2, or 3, for `disp`, `ldisp`, `sdisp`, or `return` respectively
  27:0  | offset or system call number

For `disp` and `ldisp`, the offset is relative to the start of the current
instruction, and in multiples of eight bytes. For example, in an instruction at
`0x1000`, with CS0=`40000042`, we get `disp %ctpr1, 0x1210`.

`ldisp` is only allowed with `ctpr2`.

For `sdisp`, the system call number is not shifted. `CS0=6000001a` is
`sdisp %ctpr1, 0x1a`.

The `return` operation doesn't take an offset. The offset field should be zero
in this case.

##### setmas (setting the memory address specifier)

[Memory address specifiers](https://repo.or.cz/linux/elbrus.git/blob/HEAD:/arch/e2k/include/asm/mas.h)
control multiple aspects of load and store operations. Their 7-bit format is
described elsewhere.

The MAS can be independently specified for load and store operations, in CS1:

 CS1 bits | description
----------|-------------------------------------------------------------
  27:21   | MAS for load operations
  20:14   | MAS for store operations


## Array Prefetch Instructions

Array prefetch instructions are run asynchronously on the array access unit.
They are always 16 bytes long.
To write array prefetch instructions, the mnemonic `fapb` is used.
To call an array prefetch program, load its address with ldisp to %ctpr2 (no need to call or ct).
Even though array prefetch instructions should only ever be called by ldisp and are not processed using the same facilities as
regular instructions, they always seem to be terminated by a regular branch instruction.
The maximum length of an array prefetch program is 32 instructions.



## List of ALU operations

ALU operations are generally identified by several aspects:

- The opcode field in the ALS
- If a corrsponding ALES exists, the opcode2 field in the ALES
- The ALUs in which the operation can be performed. Sometimes the same opcode
  can mean different operations in different ALUs (numbered from 0 to 5)

The following tables are grouped by opcode2 and sorted by opcode.


### Short operations (without ALES)

 Opcode | ALUs | name     | ALS[23:16]| ALS[15:8] | ALS[7:0]  | data width | description
--------|------|----------|-----------|-----------|-----------|------------|--------------------------
  0x00  | all  | ands     |  src1     |  src2     |  dst      | 32 bits    | Compute bit-wise AND of src1 and src2, store result in dst
  0x01  | all  | andd     |  src1     |  src2     |  dst      | 64 bits    | Compute bit-wise AND of src1 and src2, store result in dst
  0x10  | all  | adds     |  src1     |  src2     |  dst      | 32 bits    | Compute bit-wise AND of src1 and src2, store result in dst
  0x11  | all  | addd     |  src1     |  src2     |  dst      | 64 bits    | Compute bit-wise AND of src1 and src2, store result in dst
  0x24  | 25   | stb      |  src1     |  src2     |  src3     |  8 bits    | store  8-bit value from src3 to address at src1+src2
  0x25  | 25   | sth      |  src1     |  src2     |  src3     | 16 bits    | store 16-bit value from src3 to address at src1+src2
  0x26  | 25   | stw      |  src1     |  src2     |  src3     | 32 bits    | store 32-bit value from src3 to address at src1+src2
  0x26  | 0134 | bitrevs  |  0xc0     |  src2     |  dst      | 32 bits    | 
  0x27  | 25   | std      |  src1     |  src2     |  src3     | 64 bits    | store 64-bit value from src3 to address at src1+src2
  0x27  | 0134 | bitrevd  |  0xc0     |  src2     |  dst      | 64 bits    | 
  0x64  | 0235 | ldb      |  src1     |  src2     |  dst      |  8 bits    | load  8-bit value from address at src1+src2, store into dst
  0x65  | 0235 | ldh      |  src1     |  src2     |  dst      | 16 bits    | load 16-bit value from address at src1+src2, store into dst
  0x66  | 0235 | ldw      |  src1     |  src2     |  dst      | 32 bits    | load 32-bit value from address at src1+src2, store into dst
  0x67  | 0235 | ldd      |  src1     |  src2     |  dst      | 64 bits    | load 64-bit value from address at src1+src2, store into dst


### EXT (opcode2 = 1)

 Opcode | ALUs | name     | ALS[23:16]| ALS[15:8] | ALS[7:0]  | ALES[7:0]  | data width | description
--------|------|----------|-----------|-----------|-----------|------------|------------|-------------
  0x58  | 0    | getsp    |  0xec     |  src2     |  dst      | unused     | 32 -> 64   | Take src2, sign-extend to 32 bits; Add to user stack pointer, store in dst
