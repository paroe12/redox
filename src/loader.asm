use16

org 0x7C00

boot: ; dl comes with disk
    ; initialize segment registers
    xor ax, ax
    mov ds, ax
    mov es, ax
    mov ss, ax
    ; initialize stack
    mov sp, 0x7bfe

    mov [disk], dl

    mov si, name
    call print
    call print_line

    mov bh, 0
    mov bl, [disk]
    call print_num
    call print_line

    mov ax, (unfs_header - boot)/512
    mov bx, unfs_header
    mov cx, (kernel_file.end - unfs_header)/512
    xor dx, dx
    call load

    jmp startup

load:
    cmp cx, 127
    jbe .good_size

    pusha
    mov cx, 127
    call load
    popa
    add ax, 127
    add dx, 127*512/16
    sub cx, 127

    jmp load
.good_size:
    mov [DAPACK.addr], ax
    mov [DAPACK.buf], bx
    mov [DAPACK.count], cx
    mov [DAPACK.seg], dx

    mov si, .msg
    call print
    call print_line

    mov bx, [DAPACK.addr]
    call print_num
    call print_line

    mov bx, [DAPACK.buf]
    call print_num
    call print_line

    mov bx, [DAPACK.count]
    call print_num
    call print_line

    mov bx, [DAPACK.seg]
    call print_num
    call print_line

    mov dl, [disk]
    mov si, DAPACK
    mov ah, 0x42
    int 0x13
    jc error
    ret
.msg: db "Loading",0

print_char:
    mov ah, 0x0e
    int 0x10
    ret

print_num:
    mov cx, 4
.loop:
    mov al, bh
    shr al, 4
    and al, 0xF

    cmp al, 0xA
    jb .below_a

    add al, 'A' - '0' - 0xA
.below_a:
    add al, '0'

    push cx
    push bx
    call print_char
    pop bx
    pop cx

    shl bx, 4
    loop .loop

    ret

print_line:
    mov si, line
    call print
    ret

print:
.loop:
    lodsb
    or al, al
    jz .done
    call print_char
    jmp .loop
.done:
    ret

name: db "Redox Loader",0

line: db 13,10,0

error:
  mov si, .msg
  call print
  call print_line
.halt:
  cli
  hlt
  jmp .halt
.msg db "Could not read disk",13,10,0

disk: db 0

DAPACK:
        db	0x10
        db	0
.count: dw	0	; int 13 resets this to # of blocks actually read/written
.buf:   dw	0       ; memory buffer destination address (0:7c00)
.seg:   dw	0	; in memory page zero
.addr:  dd	0	; put the lba to read in this spot
        dd	0	; more storage bytes only for big lba's ( > 4 bytes )

times 510-($-$$) db 0
db 0x55
db 0xaa

unfs_header:
.signature:
    db 'U'
    db 'n'
    db 'F'
    db 'S'
.version:
    dd 0xFFFFFFFF
.name:
    db "Root Filesystem",0
align 256, db 0
.extents:
    dq (unfs_root_node_list - boot)/512
    dq (unfs_root_node_list.end - unfs_root_node_list)/512

    align 512, db 0
.end:

startup:
  ; a20
  in al, 0x92
  or al, 2
  out 0x92, al

  call memory_map

  call vesa

  call initialize.fpu
  call initialize.sse
  call initialize.pit
  call initialize.pic

  ; load protected mode GDT and IDT
  cli
  lgdt [gdtr]
  lidt [idtr]
  ; set protected mode bit of cr0
  mov eax, cr0
  or eax, 1
  mov cr0, eax

  ; far jump to load CS with 32 bit segment
  jmp 0x08:protected_mode

%include "asm/memory_map.asm"
%include "asm/vesa.asm"
%include "asm/initialize.asm"

protected_mode:
    use32
    ; load all the other segments with 32 bit data segments
    mov eax, 0x10
    mov ds, eax
    mov es, eax
    mov fs, eax
    mov gs, eax
    mov ss, eax
    ; set up stack
    mov esp, 0x1FFFF0

    ;rust init
    mov eax, [kernel_file + 0x18]
    mov [interrupts.handler], eax
    mov eax, kernel_file.font
    mov ebx, kernel_file.cursor
    int 255
;This is actually the idle process
.lp:
    sti
    hlt
    jmp .lp

gdtr:
    dw (gdt_end - gdt) + 1  ; size
    dd gdt                  ; offset

gdt:
    ; null entry
    dq 0
    ; code entry
    dw 0xffff       ; limit 0:15
    dw 0x0000       ; base 0:15
    db 0x00         ; base 16:23
    db 0b10011010   ; access byte - code
    db 0xcf         ; flags/(limit 16:19). flag is set to 32 bit protected mode
    db 0x00         ; base 24:31
    ; data entry
    dw 0xffff       ; limit 0:15
    dw 0x0000       ; base 0:15
    db 0x00         ; base 16:23
    db 0b10010010   ; access byte - data
    db 0xcf         ; flags/(limit 16:19). flag is set to 32 bit protected mode
    db 0x00         ; base 24:31
gdt_end:

%include "asm/interrupts.asm"

times (0xC000-0x1000)-0x7C00-($-$$) db 0

kernel_file:
  incbin "kernel.bin"
  align 512, db 0

.font:
  incbin "unifont.font"
  align 512, db 0

.cursor:
  incbin "cursor.bmp"
  align 512, db 0
.end:

unfs_root_node_list:
%macro file 2+
    unfs_node.%1:
    .name:
        db %2,0

        align 256, db 0

    .extents:
        dq (unfs_data.%1 - boot)/512
        dq (unfs_data.%1.end - unfs_data.%1)/512

        align 512, db 0
    .end:
%endmacro

%include "filesystem.gen"

%unmacro file 2+
unfs_root_node_list.end:

%macro file 2+
unfs_data.%1:
    incbin %2
    align 512, db 0
.end:
%endmacro

%include "filesystem.gen"

%unmacro file 2+
