# Elbrus architecture


## Overview
Elbrus is a SPARC-inspired VLIW architecture.

## Structure

### Stacks

#### Procedure stack (стек процедур)
The procedure stack contains parameters and local data of procedures. Its top area is stored in the register file (RF). On overflow or underflow of the register file, its contents are automatically swapped in/out of memory. Launch of a new procedure allocates a window on the procedure stack, which may overlap with the calling procedure's window.

Register PSHTP (procedure stack hardware top pointer) (insert description here)

Register PSP (procedure stack pointer) contains the virtual base address of the procedure stack.

Register WD (window descriptor) contains the base and the size of the current procedure's window into the procedure stack.

#### User stack (стек пользователя)
Stack for dynamic allocation (?)

Register USBR (user stack base pointer, РгБСП)

Register USD (user stack descriptor, ДСП)

#### Procedure chain stack (стек связующей информации)
Stack of return addresses. It can only be manipulated by the operating system and the hardware. Its top area is stored in CF (chain file) registers.

On this stack the following information is encoded in two quad words:
- return address
- compilation unit index descriptor (CUIR)
- window base (wbs) in the register file
- presence of real 80 (?)
- predicate file
- user stack descriptor
- rotating area base
- processor status register

On overflow or underflow of the chain file, its contents are automatically swapped in/out of memory.

Register PCSHTP (procedure chain stack hardware top pointer) (insert description here)

### Registers
#### Register file, RF (Регистровый файл , РгФ)
The register file has 256 registers, 84 bit each. Each of the registers holds two 32 bit values with two bit tags or a 64 bit value, and a 16 bit ordering value.

The first 224 registers are procedure stack registers, the other 32 are global registers.

TODO: %r, %b, %g, %dr, %db, %dg

TODO: Register window (Window descriptor, WD)

Accessing procedure stack registers is cyclic, i.e. after %r223 follows %r0.

TODO: Rotatable area area of procedure stack registers
TODO: last eight global registers are designated rotating area

#### Predicate file, PF (Предикатный файл, ПФ)
TODO: 32 two-bit predicates.

#### Chain file, CF 

#### Other

CUIR - compilation unit index register, индекс дескрипторов модуля компиляции

## Instructions

Elbrus' wide instructions (широкая команда, ШК) are comprised of a header syllable and one or more operation syllables. Wide instructions are 8 byte aligned.

### Syllables

Abbreviation | Description
---|---
HS   | Header syllable - it encodes length and structure of a wide instruction
SS   | Stubs syllable - short operations that take only a few bits to encode
ALS  | Arithmetic logic channel syllable
CS   | Control syllable
ALES | Arithmetic logic extension channel semi-syllable. They extend corresponding ALS. ALES2 and ALES5 are only available on Elbrus v4 and higher.
AAS  | Array access semi-syllable
LTS  | Literal syllable - literals to be used as operands
PLS  | Predicate logic syllable - processing of boolean values
CDS  | Conditional syllable - specified which operations are to be executed under which condition

The first syllable is the header syllable.
Presence of other syllables depend on the purpose of the command.
Syllables occur in the following order:
HS, SS, ALS0, ALS1, ALS2, ALS3, ALS4, ALS5, CS0, CS1, ALES2, ALES5, ALES0, ALES1, ALES3, ALES4, AAS0, AAS1, AAS2, AAS3, AAS4, AAS5, LTS3, LTS2, LTS1, LTS0, PLS2, PLS1, PLS0, CDS2, CDS1, CDS0.

#### Header syllable

Bit | Description
--- | ---
0 - 3   | Number of syllables occupied by SS, ALS, CS, ALES2, ALES5 - called "middle pointer"
4 - 6   | Length of instruction, in multiples of 8 bytes, minus 8 bytes
7 - 9   | nop
10      | loop_mode
11      | ?
12      | SS
13      | set_mark
14      | CS0
15      | CS1
16 - 17 | CDS
18 - 19 | PLS
20      | ALES0
21      | ALES1
22      | ALES2
23      | ALES3
24      | ALES4
25      | ALES5
26      | ALS0
27      | ALS1
28      | ALS2
29      | ALS3
30      | ALS4
31      | ALS5

#### Stubs syllable

Bit | Description
--- | ---
0 - 8  | ctcond (?)
9  | ?
10 - 11 | ctpr (?)
12 - 15 | syllable scale - see below
16 | alct
17 | alcf
18 | abpt
19 | abpf
20 | ?
21 | abnt
22 | abnf
23 | abgd
24 | abgi
25 | crp (?)
26 | vfdi
27 | srp
28 | bap - begin array prefetch
29 | eap - end array prefetch
30 - 31 | ipd - instruction prefetch depth

#### ALS

Bit | Description
--- | ---
0 - 24 | Params
24 - 30   | Opcode
31   | Speculative mode

#### ALES

Bit | Description
--- | ---
0 - 7 | Extension
8 - 15 | Opcode 2

### Address operands

0xxx xxxx - Rotatable area procedure stack register
10xx xxxx - procedure stack register
111x xxxx - global register
1111 1xxx - Rotatable area global register
1100 xxxx - literal

Not in src2:
1101 xxxx - literal between 16 and 31

Only in src2:
1101 0xxx - reference to 16 bit constant semi-syllable; (1<<2) indicates high half of a LTS
1101 10xx - reference to 32 bit constant syllable LTS0, LTS1, LTS2, or LTS3
1101 11xx - reference to 64 bit constant syllable pair (LTS0 and LTS1, LTS1 and LTS2, LTS2 and LTS3)

## Decoding

### Group 1

Syllables occur in the following order: SS, ALS0, ALS1, ALS2, ALS3, ALS4, ALS5, CS0

Scale index | Indicated by | Syllable
--- | --- | ---
1 | HS[12] | SS
2 | HS[26] | ALS0
3 | HS[27] | ALS1
4 | HS[28] | ALS2
5 | HS[29] | ALS3
6 | HS[30] | ALS4
7 | HS[31] | ALS5
8 | HS[14] | CS0

### Group 2

Syllables occur in the following order: CS1, ALES2, ALES5, ALES0, ALES1, ALES3, ALES4, AAS0, AAS1, AAS2, AAS3, AAS4, AAS5

ALES and AAS are semi-syllables. **In a syllable, the higher (more significant) half is decoded first, then the lower half.**

ALES2 and ALES5 are only available on Elbrus v4 and higher. If any of ALES2 or ALES5 is present, they get their own syllable that is not shared with the other ALES or AAS syllables.

Scale index | Indicated by | Syllable
--- | --- | ---
9 | HS[15] | CS1
10 | HS[20] | ALES0
11 | HS[21] | ALES1
12 | HS[22] | ALES2
13 | HS[23] | ALES3
14 | HS[24] | ALES4
15 | HS[25] | ALES5
16 | SS[12] or SS[13] | AAS0
17 | SS[14] or SS[15] | AAS1
18 | SS[12] | AAS2
19 | SS[13] | AAS3
20 | SS[14] | AAS4
21 | SS[15] | AAS5

### Group 3

Syllables occur in the following order: LTS3, LTS2, LTS1, LTS0, PLS2, PLS1, PLS0, CDS2, CDS1, CDS0

Group 3 is decoded from right to left. Any syllables not belonging to a different category are literal syllables.

Scale index | Indicated by | Syllable
--- | --- | ---
22 | - | LTS3
23 | - | LTS2
24 | - | LTS1
25 | - | LTS0
26 | HS[19:18] == 3 | PLS2
27 | HS[19:18] >= 2 | PLS1
28 | HS[19:18] >= 1 | PLS0
29 | HS[17:16] == 3 | CDS2
30 | HS[17:16] >= 2 | CDS1
31 | HS[17:16] >= 1 | CDS0
