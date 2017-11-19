; Bootloader that loads/runs the kernel
; program from the boot disk.
bits 16

section	.text

; The BIOS will load us into memory at 0000:7C00h; NASM needs
; to know this so it can generate correct absolute data references.
org	0x7C00

; jump over initial data and start executing code
start:	jmp	main

; .data "section" (although it's part of .text)
boot_msg	db "CpS 230 Team Project Kernel", 13, 10
			db "by Zachary Hayes and Ryan Longacre", 13, 10
			db "----------------------------------", 13, 10
			db "Press any key to boot kernel", 0
boot_disk	db 0 ; Variable to store the number of the disk we boot from
retry_msg	db "Error reading payload from disk; retrying...", 13, 10, 0

main:
	; Set DS == CS (so data addressing is normal/easy)
	mov		bx, cs
	mov		ds, bx
	; Save the boot disk number (we get it in register DL)
	mov		byte [boot_disk], dl
	
	; Set SS == 0x0800 (which will be the segment we load everything into later)
	mov		bx, 0x0800
	mov		ss, bx
	; Set SP == 0x0000 (stack pointer starts at the TOP of segment; first push decrements by 2, to 0xFFFE)
	mov		bx, 0x0000
	mov		sp, bx
	; Print the boot message/banner
	mov		dx, boot_msg
	call	puts
	; Wait for keypress, then read boot disk
	mov		ah, 0x00
	int		0x16
	
	mov		cl, 2
	jmp		read_disk
read_error:
	mov		dx, retry_msg
	call	puts
read_disk:
	; use BIOS raw disk I/O to load 4 sectors (starting at 2) from disk number <boot_disk> into memory at 0800:0000h (retry on failure)
	mov		ah, 0x2
	mov		al, 4
	mov		ch, 0
	mov		cl, 2
	mov		dh, 0
	mov		dl, [boot_disk]
	mov		bx, 0x0800
	mov		es, bx
	mov		bx, 0x0000
	int		0x13
	jc		read_error
	
	; Finally, jump to address 0800h:0000h (sets CS == 0x0800 and IP == 0x0000)
	jmp	0x0800:0x0000

; print NULL-terminated string from DS:DX to screen using BIOS (INT 10h)
; takes NULL-terminated string pointed to by DS:DX
; clobbers nothing
; returns nothing
puts:
	push	ax
	push	cx
	push	si
	
	mov	ah, 0x0e
	mov	cx, 1		; no repetition of chars
	
	mov	si, dx
.loop:	mov	al, [si]
	inc	si
	cmp	al, 0
	jz	.end
	int	0x10
	jmp	.loop
.end:
	pop	si
	pop	cx
	pop	ax
	ret

; make sure the boot sector signature starts 510 bytes from our origin
	times	510 - ($ - $$)	db	0

; BOOT SECTOR SIGNATURE (*must* be the last 2 bytes of the 512 byte boot sector)
	dw	0xaa55
