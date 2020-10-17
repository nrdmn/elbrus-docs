; Linux/E2k loader, rev. 0.01

	bits 16
	org 0x7c00

; set up stack
	cli
	mov ax,0x1000
	mov ss,ax
	mov sp,0xfffe
	sti

; clear direction
	cld

; check if video mode is 3 ...
	mov ah,0xf
	int 0x10
	cmp al,0x3
	jz .video_mode_correctly_set

; ... if not, set video mode to 3
	mov ax,0x3
	int 0x10

.video_mode_correctly_set:
; write the video mode into the boot info struct
	mov byte [cs:boot_info.vga_mode],0x3

; read sector 1, head 0, cylinder 0 of drive #0 to 2003:0000
	mov ah,0x20
	mov es,ax ; segment=0x2003
	mov ds,ax
	xor bx,bx ; offset=0
	mov dx,0x80 ; head=0, drive=0x80
	mov cx,0x1 ; cylinder=0, sector=1
	mov ax,0x201 ; read one sector
	int 0x13

	lea si,[mbr_read_failed]
	jc print_error

; look for active partition in mbr partition table
	add bx,0x1be
.look_for_active_partition:
	cmp byte [bx],0x80
	jz load_rest_of_bootloader
	add bl,0x10
	cmp bl,0xfe
	jnz .look_for_active_partition

	lea si,[no_active_partition]




print_error:
	mov ah,0xe
	xor bx,bx

.print_error_loop:
	cs lodsb
	int 0x10
	cmp al,0x0
	jnz .print_error_loop

; clear interrupts and halt
	cli
	hlt




load_rest_of_bootloader:
; check if partition type is 0xe2
	cmp byte [bx+0x4],0xe2
	lea si,[bad_partition_type]
	jnz print_error

	mov dh,[bx+0x1] ; read heads from partition table entry
	mov cx,[bx+0x2] ; read cylinders and sectors from partition table entry
	xor ax,ax
	mov es,ax
	mov ds,ax
	mov [read_window.heads],dh
	mov [read_window.cylinders_and_sectors],cx

	lds bx,[0x104] ; load pointer to drive #0's fixed disk parameter table
	mov ecx,[bx] ; read number of cylinders
	mov [cs:boot_info.cylinders],ecx
	mov cl,[bx+0xe] ; read number of sectors per track
	mov [cs:drive_sectors],cl
	mov [cs:boot_info.sectors],cl

	mov ds,ax
	mov al,0x1
	call shift_read_window

; load 3 sectors from disk to 0x7e00
	mov bx,main
	mov ax,0x203
	int 0x13
	lea si,[loader_read_failed]
	jc print_error

; check bootloader signature
	cmp dword [pvk],'PVK!'
	lea si,[bad_loader]
	jnz print_error

; fully loaded the bootloader!
	jmp main




; shift read window by al sectors
shift_read_window:
	mov cx,[read_window.cylinders_and_sectors]
	mov dh,[read_window.heads]
	mov bx,cx
	and bx,strict word 0x3f ; extract sectors
	xor ah,ah
	add bx,ax ; bx = sectors + al

.loop:
; check if drive's number of sectors is not greater
; than read window's sector
	cmp bx,[drive_sectors]
	jbe .done

; if it is greater, subtract drive's number of sectors per track
; from read window's sector
	sub bx,[drive_sectors]
; and increment read window's head
	inc dh

; check if disk's number of heads if below read window's head
	cmp dh,[boot_info.heads]
	jb .loop

; set read window's head to zero and increment cylinder
; then jump back
	xor dh,dh
	inc ch
	jnz .loop
	add cx,strict word 0x40
	jmp near .loop

.done:
; decrement cylinder
	and cx,strict word -0x40
; extract sector
	or cx,bx
	mov [read_window.cylinders_and_sectors],cx
	mov [read_window.heads],dh
	ret




read_window:
.heads			db 0
.cylinders_and_sectors	dw 0

drive_sectors		dw 0

			times 256-($-$$) db 0

boot_info:
.signature		dw 0x8086
.cylinders		dw 0
.heads			db 0
.sectors		db 0
.vga_mode		db 3
.num_banks		db 1 ; number of memory banks
.kernel_base_lo		dd 0
.kernel_base_hi		dd 0
.kernel_size_lo		dd 0
.kernel_size_hi		dd 0
.ramdisk_base_lo	dd 0
.ramdisk_base_hi	dd 0
.ramdisk_size_lo	dd 0
.ramdisk_size_hi	dd 0

	times 128	db 0

bad_partition_type	db 'Bad partition type', 0
bad_loader		db 'Bad loader', 0
loader_read_failed	db 'Loader read failed', 0
mbr_read_failed		db 'MBR read failed', 0
no_active_partition	db 'No active partition', 0

	db 0
	dw 0xaa55




main:
	lea si,[version]
	call puts
	lgdt [gdt]
	mov al,0x7f
	call shift_read_window

; if kernel_base_lo is 0, set it to 0x100000
	cmp strict dword [boot_info.kernel_base_lo],strict dword 0
	jnz .kernel_base_set
	mov strict dword [boot_info.kernel_base_lo],0x100000

.kernel_base_set:
; if ramdisk_base_lo is 0, put it directly behind the kernel
; and round up to nearest 4K
	cmp strict dword [boot_info.ramdisk_base_lo],strict dword 0
	jnz .ramdisk_base_set
	mov eax,[boot_info.kernel_base_lo]
	add eax,[boot_info.kernel_size_lo]
	add eax,0xfff
	and eax,0xfffff000
	mov [boot_info.ramdisk_base_lo],eax

.ramdisk_base_set:
; {kernel,ramdisk}_{base,size} must be below 4G
	xor eax,eax
	cmp [boot_info.kernel_base_hi],eax
	jnz .wrong_memory_layout
	cmp [boot_info.kernel_size_hi],eax
	jnz .wrong_memory_layout
	cmp [boot_info.ramdisk_base_hi],eax
	jnz .wrong_memory_layout
	cmp [boot_info.ramdisk_size_hi],eax
	jnz .wrong_memory_layout

; query memory map
	mov ax,0xe801
	int 0x15
	shl eax,10 ; memory between 1M and 16M, in bytes
	shl ebx,16 ; memory above 16M, in bytes
	add eax,ebx ; memory above 1M, in bytes
	add eax,0x100000 ; add 1M to get total memory in bytes
	lea si,[bios_accessible_memory_size]
	call puts
	call print_hex_dword

; is end of kernel above BIOS accessible memory area?
	mov ebx,[boot_info.kernel_base_lo]
	mov edi,ebx
	add ebx,[boot_info.kernel_size_lo]
	cmp ebx,eax
	ja .wrong_memory_layout

; is end of ramdisk above BIOS accessible memory area?
	mov ecx,[boot_info.ramdisk_base_lo]
	mov esi,ecx
	add ecx,[boot_info.ramdisk_size_lo]
	cmp ecx,eax
	ja .wrong_memory_layout

; is ramdisk base above kernel base?
	cmp edi,esi
	ja .ramdisk_base_above_kernel_base

; is end of kernel below or at ramdisk base?
	cmp ebx,esi
	jbe .ok

.wrong_memory_layout:
	lea si,[wrong_memory_layout_requested]
	jmp print_error

.ramdisk_base_above_kernel_base:
; is kernel base above end of ramdisk?
	cmp ecx,edi
	ja .wrong_memory_layout

.ok:
; kernel and ramdisk do not overlap and are within BIOS accessible memory
	lea si,[kernel]
	mov ebp,[boot_info.kernel_size_lo]
	mov edi,[boot_info.kernel_base_lo]
	call copy_from_disk
	mov ebp,[boot_info.ramdisk_size_lo]
	test ebp,ebp
	jz .switch_to_e2k
	lea si,[ramdisk]
	mov edi,[boot_info.ramdisk_base_lo]
	call copy_from_disk

.switch_to_e2k:
	jmp near .magic

.magic:
	icebp
	db 0xee, 0xbc ; what's this?
	dd boot_info




; This function copys from disk to memory in chunks of 1/30th
; of size and outputs a progress bar with one '*' per chunk.
; edi: base
; ebp: size
copy_from_disk:
; print description
	call puts

; print size
	mov eax,ebp
	call print_hex_dword

; convert size to sectors
	add ebp,0x1ff
	shr ebp,9 

; print from
	lea si,[from]
	call puts

; print base
	mov eax,edi
	call print_hex_dword

; print progress bar
	lea si,[progress_bar]
	call puts

; divide size by 30
	mov eax,ebp
	xor edx,edx
	mov ecx,30
	div ecx
	mov [progress_bar.size_1_30th],eax ; write quotient
	mov [progress_bar.size_remainder],edx ; write remainder

	mov ecx,ebp
	sub ecx,eax
	mov [progress_bar.remaining],ecx
	mov [progress_bar.sectors_copied],edx
.loop:
; check if less than 1/30th is remaining
	mov ecx,[progress_bar.remaining]
	cmp ebp,ecx
	ja .1

; print one '*' per 1/30th
	xor bx,bx
	mov ax,0xe2a
	int 0x10

	sub ecx,[progress_bar.size_1_30th]
	mov eax,[progress_bar.sectors_copied]
	add eax,[progress_bar.size_remainder]
	mov [progress_bar.sectors_copied],eax
	jnc .2
	dec ecx ; decrement chunks remaining
.2:
	mov [progress_bar.remaining],ecx

.1:
; read up to 0x7f sectors from disk
	mov dl,0x80
	mov dh,[read_window.heads]
	mov cx,[read_window.cylinders_and_sectors]
	mov ax,0x3000
	mov es,ax
	xor bx,bx
	mov si,0x7f
	cmp ebp,strict dword 0x7f
	cmovbe si,bp
	mov ax,si
	mov ah,2
	int 0x13
	jc .print_read_error
	mov ax,si
	call shift_read_window

; enable protected mode
	cli
	mov eax,cr0
	or eax,strict dword 1
	mov cr0,eax
	jmp 0x10:.protected_mode_enabled

.protected_mode_enabled:
	bits 32

; copy si sectors to base
	mov ax,8
	db 0x66   ; TODO I'm unable to get nasm to print these
	mov ds,ax ; two movs with a 0x66 (16 bit operand size)
	db 0x66   ; prefix, so I manually add the prefixes here
	mov es,ax ;
	xor ecx,ecx
	mov cx,si
	shl ecx,7
	mov esi,0x30000
	rep movsd
	jmp 0x18:.disable_protected_mode

.disable_protected_mode:
	bits 16
	mov ax,0x20
	mov ds,ax
	mov es,ax
	mov eax,cr0
	and al,0xfe
	mov cr0,eax
	jmp 0:.protected_mode_disabled

.protected_mode_disabled:
; reset ds and es
	mov ax,cs
	mov ds,ax
	mov es,ax
	sti
; loop while size is > 0x7f
	cmp ebp,strict dword 0x7f
	jbe .ret
	sub ebp,strict dword 0x7f
	jmp .loop
.ret:
	ret

.print_read_error:
	lea si,[read_error]
	jmp print_error




puts:
	push ax
	push bx
	mov ah,0xe
	xor bx,bx
	lodsb
.1:
	int 0x10
	lodsb
	cmp al,0
	jnz .1
	pop bx
	pop ax
	ret

putchar:
	push bx
	xor bx,bx
	mov ah,0xe
	int 0x10
	pop bx
	ret

print_hex_digit:
	add al,0x30
	cmp al,0x3a
	jb .1
	add al,0x7
.1:
	call putchar
	ret

print_hex_byte:
	mov al,bl
	shr al,4
	call print_hex_digit
	mov al,bl
	and al,0xf
	call print_hex_digit
	ret

print_hex_dword:
	push ax
	push ebx
	mov ebx,eax
	rol ebx,8
	call print_hex_byte
	rol ebx,8
	call print_hex_byte
	rol ebx,8
	call print_hex_byte
	rol ebx,8
	call print_hex_byte
	mov al,0x20
	call putchar
	pop ebx
	pop ax
	ret




version		db 'Linux/E2k loader, rev. 0.01', 13, 10, 0
kernel		db 13, 10, 'kernel 0x', 0
ramdisk		db 13, 10, 'ramdisk 0x', 0
read_error	db 'read error', 0
from		db 'from 0x', 0
bios_accessible_memory_size	db 'BIOS accessible memory size 0x', 0
wrong_memory_layout_requested	db 'wrong memory layout requested', 0

progress_bar:
	db '['
	times 30 db '.'
	db ']'
	times 31 db 8 ; these are backspaces
	db 0

.size_1_30th	dd 0
.size_remainder	dd 0
.remaining	dd 0
.sectors_copied	dd 0




gdt:
; structure of a descriptor:
; dw	segment limit 0-15
; dw	base address 0-15
; db	base address 16-23
; db	db access byte
; db	flags and segment limit 16-19
; db	base address 24-31

; base address 0x8140, segment limit 0x27, 16 bit
	dw 0x0027, 0x8140
	db 0x00, 0x00, 0x00, 0x00

; base address 0xff000000, segment limit 0xf0000000, 32 bit
	dw 0x0000, 0x0000
	db 0x00, 0x00, 0xff, 0xff

; base address 0xffcf9200, segment limit 0xf0000000, 32 bit
	dw 0x0000, 0x9200
	db 0xcf, 0x00, 0xff, 0xff

; base address 0xff4f9b00, segment limit 0xf0000000, 32 bit
	dw 0x0000, 0x9b00
	db 0x4f, 0x00, 0xff, 0xff

; base address 0xff009a00, segment limit 0xf0000000, 32 bit
	dw 0x0000, 0x9a00
	db 0x00, 0x00, 0xff, 0xff

; base address 0x9a00, segment limit 0, 16 bit
	dw 0x0000, 0x9200
	db 0x00, 0x00, 0x00, 0x00




	times 2044-($-$$) db 0

pvk     db 'PVK!'
