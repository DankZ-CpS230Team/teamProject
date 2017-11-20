; CpS 230 Team Project - Kernel
; Zachary Hayes (zhaye769) and Ryan Longacre (rlong315)

bits 16

org 0x0 ; change to 0x100 when running as COM file, change to 0x0 when bootinjg with bootloader

SECTION .text

start:
	mov		dx, cs
	mov		ds, dx
	; spawn tasks
	mov		dx, _main
	call	_spawn_new_task
	mov		dx, _taskA
	call	_spawn_new_task
	mov		dx, _taskB
	call	_spawn_new_task
	jmp _main

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
	cmp cl, 6
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
	cmp cl, 6
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

; Prints "Task A" to screen
_taskA:
	mov		bl, 2
	sub		sp, 1 ; reserve space for local boolean to track direction (0 - left, 1 - right)
	mov		byte [bp + 1], 1
jumpA_begin:
	; print "Task A" in light blue
	mov		bh, 12
	mov		cl, 0 ; black background
	mov		ch, 9 ; light blue foreground
	mov		ax, taskA_str ; pointer to string
	mov		dh, 0 ; no blink
	call	_printString
		
	; increment column for next print and yield
	cmp		bl, 160 - 22 ; 22 is length of string
	jae		changeDir_A
	cmp		bl, 0
	jbe		changeDir_A
	cmp		byte [bp + 1], 1 ; check direction flag
	je		moveRight_A
; move left
	sub		bl, 2
	jmp		yield_A
moveRight_A:
	add		bl, 2
	jmp		yield_A
changeDir_A:
	mov		al, 4 ; these next 4 lines evaluate to bh -= ((dir == 1) ? 2 : -2)
	imul	byte [bp + 1]
	add		al, -2
	sub		bl, al
	xor		byte [bp + 1], 1 ; flip direction flag
	
yield_A:
	call	_yield
	jmp		jumpA_begin

; Prints "I am task B" to screen
_taskB:
	mov		bl, 160 - 12 - 2 ; 12 is length of string's longest line
	sub		sp, 1 ; reserve space for local boolean to track direction (0 - left, 1 - right)
	mov		byte [bp + 2], 0
jumpB_begin:
	; print "Task B" in light purple
	mov		bh, 20
	mov		cl, 0 ; black background
	mov		ch, 0xd ; light purple foreground
	mov		ax, taskB_str ; pointer to string
	mov		dh, 0 ; no blink
	call	_printString
	mov		ah, 0x2c
	
	; increment column for next print and yield
	cmp		bl, 160 - 12 ; again, 12 is length of string's longest line
	jae		changeDir_B
	cmp		bl, 0
	jbe		changeDir_B
	cmp		byte [bp + 2], 1 ; check direction flag
	je		moveRight_B
; move left
	sub		bl, 2
	jmp		yield_B
moveRight_B:
	add		bl, 2
	jmp		yield_B
changeDir_B:
	mov		al, 4 ; these next 4 lines evaluate to bh -= ((dir == 1) ? -2 : 2)
	imul	byte [bp + 2]
	add		al, -2
	sub		bl, al
	xor		byte [bp + 2], 1 ; flip direction flag
	
yield_B:
	call	_yield
	jmp		jumpB_begin

; prints a char to the screen using 0x10 interrupt
; bl and bh are thee coordinates of where the char gets printed
; cl is the background color, ch is the foreground color
; dh is whether or not the charachter blinks
; dl is the ascii value of the character to be printed
; video mode must already be set, or else it erases everything
; prints  char to row, col stored in BH, BL (respectively)
; clobbers nothing
; returns nothing
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
	mov		ax, 80
	mul		bh
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
	or		al, cl
	shl		ax, 4
	; move foreground into position
	and		ch, 0xf
	or		al,	ch
	shl		ax, 8
	; move ascii char into position
	or		al, dl

	; move ax into dx, because ax is used for arguments to the video mode
	mov		dx, ax

	mov		word [es:bx], dx ; print the character (with formatting) stored in ax in the location stored in bx

	pop		dx
	pop		cx
	pop		bx
	pop		ax
	inc		bl ; add one to the x, so the next char can be printed right next to it
	inc		bl	
	ret	; return to caller

; print NULL-terminated string from DS:DX to screen using BIOS (INT 0x10)
; takes NULL-terminated string pointed to by DS:AX
; prints to row, col stored in BH, BL (respectively)
; clobbers nothing
; returns nothing
_printString:
	push	ax	; save registers
	push	bx
	push	cx
	push	dx
	push	si
	
	mov		si, ax
	
	mov		al, bl ; store beginning of line col for new line jumps 

.loop:
	mov		dl, [si]	; AL = current character
	inc		si			; advance SI to point at next character
	cmp		dl, 0		; if (AL == 0), stop
	jz		.end
	cmp		dl,	10		; if newline, jump back to the beginning col
	je		.new
	cmp		dl, 13		; if carriage return, jump down a row
	je		.ret
	jmp		.check_offscreen	
.new:
	mov		bl, al		; jump back to the original col
	jmp		.loop		; don't print the character
.ret:
	inc		bh
	inc		bh			; increment one row
	jmp		.loop		; don't print the character
.check_offscreen:		; TODO: check if ofscreen
.print:
	call	_printChar	; use _printChar to print the char
	jmp		.loop		; repeat
.end:
	pop		si ; restore registers (de-clobber)
	pop		dx	
	pop		cx
	pop		bx
	pop		ax
	ret		; return to caller
	
; print "Main" in loop until interrupted
_main:	
	
infiniteLoop_main:
	; set video mode
	mov		ah, 0x0
	mov		al, 0x3
	int		0x10 

no_inc:
	
	; print "Main" in white
	mov		bl, 2 ; col 2
	mov		bh, 4 ; row 4
	mov		cl, 0 ; black background
	mov		ch, 7 ; white foreground
	mov		dh, 0 ; no blink
	mov		ax, main_str
	call	_printString

	call	_yield
	; pause after drawing updates
	mov		ah, 0x86
	mov		cx, 0
	mov		dx, 0xFFFF
	int		0x15

	jmp		infiniteLoop_main

	mov	ah, 0x4c
	mov	al, 0
	int	0x21
	
SECTION .data
	; global variables
	main_str: db "Main", 0
	taskA_str: db "I am task A", 0
	taskB_str: db "I am", 13, 10, "task B", 0

	; global variables for stacks
	current_task: db 0
	stacks: times (256 * 6) db 0 ; 5 fake stacks of size 256 bytes
	task_status: times 6 db 0 ; 0 means inactive, 1 means active
	stack_pointers: dw 0 ; the first pointer needs to be to the real stack !
					dw stacks + (256 * 1)
					dw stacks + (256 * 2)
					dw stacks + (256 * 3)
					dw stacks + (256 * 4)
					dw stacks + (256 * 5)
					dw stacks + (256 * 6)
					dw stacks + (256 * 7)
