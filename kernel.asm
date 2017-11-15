; CpS 230 Team Project - Kernel
; Zachary Hayes (zhaye769) and Ryan Longacre (rlong315)

bits 16

org 0x100

SECTION .text

start: jmp _main

; spawns new task
; dx should contain the address of the function to run
_spawn_new_task:
	; save current stack pointer
	mov bx, stack_pointers
	add bx, [current_task]
	add bx, [current_task] ; add twice because we have two bytes
	mov [bx], sp
	; switch to new stack
	mov cx, 0
	mov cl, [current_task]
	inc cl
sp_loop_for_available_stack:
	cmp cl, byte [current_task]
	jne sp_check_for_overflow
	jmp sp_no_available_stack
sp_check_for_overflow:
	cmp cl, 31
	jg sp_reset
	jmp sp_check_if_available
sp_reset:
	mov cl, 0
	jmp sp_loop_for_available_stack
sp_check_if_available:
	mov bx, task_status
	add bx, cx
	cmp byte [bx], 0
	je sp_is_available
	inc cx
	jmp sp_loop_for_available_stack
sp_is_available:
	mov bx, task_status
	add bx, cx
	mov byte [bx], 1
	; push a fake return address
	mov bx, stack_pointers
	add bx, cx
	add bx, cx
	mov sp, [bx]
	push dx
	; push registers
	pusha
	; push flags
	pushf
	; update stack pointer for task
	mov bx, stack_pointers
	add bx, cx
	add bx, cx ; add twice because we have two bytes
	mov [bx], sp
	; restore to original stack
sp_no_available_stack:
	mov bx, stack_pointers
	add bx, [current_task]
	add bx, [current_task] ; add twice because we have two bytes
	mov sp, [bx]
	ret

; yields processor from caller to next task
_yield:
	pusha ; push registers
	pushf ; push flags
	; save current stack pointer
	mov bx, stack_pointers
	add bx, [current_task]
	add bx, [current_task] ; add twice because we have two bytes
	mov [bx], sp
	; switch to new stack
	mov cx, 0
	mov cl, [current_task]
	inc cl
y_check_for_overflow:
	cmp cl, 31
	jg y_reset
	jmp y_check_if_enabled
y_reset:
	mov cl, 0
	jmp y_check_for_overflow
y_check_if_enabled:
	mov bx, task_status
	add bx, cx
	cmp byte [bx], 1
	je y_task_available
	inc cx
	jmp y_check_for_overflow
y_task_available:
	mov bx, cx
	mov [current_task], bx
	; update stack pointer
	mov bx, stack_pointers
	add bx, [current_task]
	add bx, [current_task] ; add twice because we have two bytes
	mov sp, [bx]
	; pop flags
	popf
	; pop registers
	popa
	ret

; Prints "I am task A" to screen
_taskA:
	;

; Prints "I am task B" to screen
_taskB:
	;

_printChar:
	; bx is location, bl is x, bh is y
	; cx is color, ch is foreground, cl is background
	; dh is blink
	; dl is ascii value
	push	ax
	push	bx
	push	cx
	push	dx

	mov		ax, 0xB800 ; where the graphics start in memory
	mov		es, ax
	mov		al, bh ; do the math to find the character offset
	mov		ah, 80
	mul		ah
	push	dx
	xor		dx, dx
	mov		dl, bl
	add		ax, dx
	pop		dx
	mov		bx, ax; offset to move the char to a location on the screen (y * 80) + x
	; bx now holds the right offset

	; move blink into position
	mov		al, dh
	shl		ax, 3
	; move background into position
	and		cl, 0x7
	and		al, cl
	shl		ax, 4
	; move foreground into position
	and		ch, 0xf
	and		al,	ch
	shl		ax, 8
	; move ascii char into position
	and		al, dl

	; move ax into dx, because ax is used for arguments to the video mode
	mov		dx, ax

	mov		ah, 0x0
	mov		al, 0x3
	int		0x10 ; set video mode

	mov		word [es:bx], ax ; print the character (with formatting) stored in ax in the location stored in bx

	pop		dx
	pop		cx
	pop		bx
	pop		ax
	; inc bl for printing next charachter
	inc		bl
	ret	; return to caller

; print NULL-terminated string from DS:DX to screen using BIOS (INT 0x10)
; takes NULL-terminated string pointed to by DS:DX
; prints to row, col stored in BH, BL (respectively)
; clobbers nothing
; returns nothing
_printString:
	push	ax		; save ax/cx/si
	push	cx
	push	si
	
	; set cursor to row BH, col BL
	push	dx ; save string pointer since we need dh, dl to move position
	mov		ah, 0x2
	mov		dh, bh
	mov		dl, bl
	int		0x10
	pop		dx
	
	mov		ah, 0x0e	; BIOS video services (int 0x10) function 0x0e: put char to screen
	
	mov		si, dx		; SI = pointer to string (offset only; segment assumed to be DS)
.loop: mov		al, [si]	; AL = current character
	inc		si			; advance SI to point at next character
	cmp		al, 0		; if (AL == 0), stop
	jz		.end
	int		0x10		; call BIOS via interrupt 0x10 (the ASCII char to print is in AL)
	jmp		.loop		; repeat
.end:
	pop		si ; restore si/cx/ax (de-clobber)
	pop		cx
	pop		ax
	ret		; return to caller
	
_main:
	; spawn other tasks, then print "Main" in loop until interrupted
	mov		dx, _taskA
	call	_spawn_new_task
	mov		dx, _taskB
	call	_spawn_new_task
infiniteLoop_main:
	; print "Main" in center of screen
	mov		dx, main_str
	mov		bh, 24
	mov		bl, 32
	call	_printString
	; test _printChar
	mov		bl, 10 ; y = 10
	mov		bh, 10 ; x = 10
	mov		cl, 0 ; black background
	mov		ch, 9 ; light blue foreground
	mov		dl, 65 ; ascii for 'A'
	mov		dh, 0 ; no blink
	call	_printChar

	; wait for a keypress so the user can see what happened
	mov ah, 0x0
	int 0x16

	; call	_yield
	; jmp		infiniteLoop_main
	
	mov	ah, 0x4c
	mov	al, 0
	int	0x21
	
SECTION .data
	; global variables
	main_str: db "Main", 0
	taskA_str: db "I am task A", 0
	taskB_str: db "I am task B", 0

	; global variables for stacks
	current_task: db 0
	stacks: times (256 * 31) db 0 ; 31 fake stacks of size 256 bytes
	task_status: times 32 db 0 ; 0 means inactive, 1 means active
	stack_pointers: dw 0 ; the first pointer needs to be to the real stack !
					dw stacks + (256 * 1)
					dw stacks + (256 * 2)
					dw stacks + (256 * 3)
					dw stacks + (256 * 4)
					dw stacks + (256 * 5)
					dw stacks + (256 * 6)
					dw stacks + (256 * 7)
					dw stacks + (256 * 8)
					dw stacks + (256 * 9)
					dw stacks + (256 * 10)
					dw stacks + (256 * 11)
					dw stacks + (256 * 12)
					dw stacks + (256 * 13)
					dw stacks + (256 * 14)
					dw stacks + (256 * 15)
					dw stacks + (256 * 16)
					dw stacks + (256 * 17)
					dw stacks + (256 * 18)
					dw stacks + (256 * 19)
					dw stacks + (256 * 20)
					dw stacks + (256 * 21)
					dw stacks + (256 * 22)
					dw stacks + (256 * 23)
					dw stacks + (256 * 24)
					dw stacks + (256 * 25)
					dw stacks + (256 * 26)
					dw stacks + (256 * 27)
					dw stacks + (256 * 28)
					dw stacks + (256 * 29)
					dw stacks + (256 * 30)
					dw stacks + (256 * 31)
	