; CpS 230 Team Project - Kernel
; Zachary Hayes (zhaye769) and Ryan Longacre (rlong315)

bits 16

org 0x100 ; change to 0x100 when running as COM file, change to 0x0 when booting with bootloader

SECTION .text

start:
	mov		dx, cs
	mov		ds, dx
	
	; set up custom keyboard hardware interrupt
	cli
	mov		ax, 0
	mov		es, ax

	mov		dx, [es:0x9*4]
	mov		[previous9], dx
	mov		ax, [es:0x9*4+2]
	mov		[previous9+2], ax

	mov		dx, keyboard
	mov		[es:0x9*4], dx
	mov		ax, cs 
	mov		[es:0x9*4+2], ax
	sti
	
	; spawn tasks
	mov		dx, _main
	call	_spawn_new_task
	mov		dx, _taskA
	call	_spawn_new_task
	mov		dx, _taskB
	call	_spawn_new_task
	mov		dx, _rpnCalculator
	call	_spawn_new_task
	mov		dx, _gameOfLife
	call 	_spawn_new_task
	jmp		_main
	
terminate:
	; restore old keyboard hardware interrupt
	mov		ax, 0
	mov		es, ax
	mov		dx, [previous9]
	mov		[es:0x9*4], dx
	mov		ax, [previous9 + 2]
	mov		[es:0x9*4+2], ax
	
	mov		ah, 0x4c
	mov		al, 0
	int		0x21
	; terminates program; exit code 0
	
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
	mov		bl, 44
jumpA_begin:
	; print "Task A" in light blue
	mov		bh, 34
	mov		cl, 0 ; black background
	mov		ch, 9 ; light blue foreground
	mov		ax, taskA_str ; pointer to string
	mov		dh, 0 ; no blink
	call	_printString
		
	; increment column for next print and yield
	cmp		bl, 160 - 22 ; 22 is length of string
	jae		changeDir_A
	cmp		bl, 42
	jbe		changeDir_A
	cmp		byte [taskA_dir], 1 ; check direction flag
	je		moveRight_A
; move left
	sub		bl, 2
	jmp		yield_A
moveRight_A:
	add		bl, 2
	jmp		yield_A
changeDir_A:
	mov		al, 4 ; these next 4 lines evaluate to bh -= ((dir == 1) ? 2 : -2)
	imul	byte [taskA_dir]
	add		al, -2
	sub		bl, al
	xor		byte [taskA_dir], 1 ; flip direction flag
	
yield_A:
	call	_yield
	jmp		jumpA_begin

; Prints "I am task B" to screen
_taskB:
	mov		bl, 160 - 12 - 2 ; 12 is length of string's longest line
jumpB_begin:
	; print "Task B" in light purple
	mov		bh, 40
	mov		cl, 0 ; black background
	mov		ch, 0xd ; light purple foreground
	mov		ax, taskB_str ; pointer to string
	mov		dh, 0 ; no blink
	call	_printString
	mov		ah, 0x2c
	
	; increment column for next print and yield
	cmp		bl, 160 - 12 ; again, 12 is length of string's longest line
	jae		changeDir_B
	cmp		bl, 42
	jbe		changeDir_B
	cmp		byte [taskB_dir], 1 ; check direction flag
	je		moveRight_B
; move left
	sub		bl, 2
	jmp		yield_B
moveRight_B:
	add		bl, 2
	jmp		yield_B
changeDir_B:
	mov		al, 4 ; these next 4 lines evaluate to bh -= ((dir == 1) ? -2 : 2)
	imul	byte [taskB_dir]
	add		al, -2
	sub		bl, al
	xor		byte [taskB_dir], 1 ; flip direction flag
	
yield_B:
	call	_yield
	jmp		jumpB_begin
	
; task that prints a 19x19 version of Conway's Game of Life
_gameOfLife:
	push 	ax
	push	bx
	push 	cx
	push	dx
	
; set the position to start printing at 0, 0 (for now)
	mov		bl, 0
	mov		bh, 30
	
; update and print the grid
	mov 	ax, 0	
_y_loop:
	mov		dh, 0
_x_loop:
	
	; put the character to be printed into dl
	push 	bx
	mov		bx, ax
	mov		dl, [ds:gameOfLife_grid+bx]
	pop 	bx
	
	; set the colors
	mov		cl, 0
	mov		ch, 4
	
	
	; turn off blink
	push 	dx
	mov		dh, 0
	; print the character
	call 	_printChar
	pop 	dx
	
	inc		dh
	inc		ax
	
	cmp		dh, 20
	je		_x_loop_end
	jmp		_x_loop
_x_loop_end:
	; print a CRLF character to return to the next line
	inc		bh
	inc		bh
	mov		bl, 0
	
	cmp		ax, 200
	je		_y_loop_end
	jmp		_y_loop
_y_loop_end:
	

	pop		dx
	pop		cx
	pop		bx
	pop 	ax
	call	_yield
	jmp		_gameOfLife

; helper method for Game of Life
; takes the cell location in ax
; and returns the number of adjacent live cells in bx
_check_adjacent_cells:
	push 	ax

	mov 	bx, 0
	

	pop		ax
	ret

; helper method for _check_adjacent_cells
; takes a cell location in ax
; returns a corrected cell location in ax
_correct_cell_location:
	cmp		ax, 0
	jl		_less_than
	cmp		ax, 199
	jg		_greater_than
	jmp		_return
_less_than:
	add 	ax, 200
	jmp	 	_return
_greater_than:
	sub		ax, 200
_return:
	ret

	
; RPN Calculator task
; prints visuals such as expression being entered and result
; processes RPN string when enter is pressed
_rpnCalculator:
	cmp		byte [rpn_evaluate], 1
	je		rpn_doEvaluate
	jmp		rpn_printString ; skip to printing if no numbers to crunch
rpn_doEvaluate:
		mov		si, rpn_string - 1
		; si points to next character
	rpn_expression:
		inc		si
		; check if char is a number
		cmp		byte [si], '0'
		jge		rpn_aboveZero
		jmp		rpn_notNumber
	rpn_aboveZero:
		cmp		byte [si], '9'
		jle		rpn_isNumber
		jmp		rpn_notNumber
		
	rpn_isNumber:
		cmp		byte [rpn_enteringNum], 1
		je		rpn_addToCurrentNum
		; if not entering num, now we are
		; set flag and clear curNum
		mov		byte [rpn_enteringNum], 1
		mov		word [rpn_curNum], 0 ; set curNum to 0
	rpn_addToCurrentNum:
		mov		bx, [si] ; save input to bx
		and		bx, 0x00FF ; only want lower bits (input is a char)
		sub		bx, '0' ; convert input from ASCII to int value
		mov		ax, [rpn_curNum]
		mov		cx, 10 ; multiply curNum by 10, then add new char
		imul	cx
		add		ax, bx
		mov		word [rpn_curNum], ax
		jmp		rpn_expression
	
	rpn_notNumber:
		; below logic:
		;	if entering number, finish number (push to stack)
		;	then check for operator
		;		ignore character if not operator
		;		else perform operation
		cmp		byte [rpn_enteringNum], 1
		jne		rpn_checkOperator
		jmp		rpn_numberDone ; finish entering number

	rpn_checkOperator:
		; compare si to rpn_strPointer
		; if equal, print result and exit loop
		mov		ax, si
		sub		ax, rpn_string
		cmp		ax, [rpn_strPointer]
		jne		rpn_notEnd
		jmp		rpn_exprDone
	rpn_notEnd:
		; check each operator
		; if [si] matches one, do operation
		; else ignore char and get input again
		cmp		byte [si], '+'
		je		rpn_addition
		jmp		rpn_notPlus
	rpn_addition:
		call	_rpn_pop_value
		; after EVERY push or pop, we have to check DX to see if any errors occurred
		cmp		dx, 1
		jne		rpn_addPop1OK
		mov		ax, rpn_underflowStr
		jmp		rpn_error
	rpn_addPop1OK:
		mov		bx, ax ; save first value
		call	_rpn_pop_value
		cmp		dx, 1
		jne		rpn_addPop2OK
		mov		ax, rpn_underflowStr
		jmp		rpn_error
	rpn_addPop2OK:
		add		ax, bx
		call	_rpn_push_value
		cmp		dx, 1
		jne		rpn_addPushOK
		mov		ax, rpn_overflowStr
		jmp		rpn_error
	rpn_addPushOK:
		jmp		rpn_expression
	rpn_notPlus:
		cmp		byte [si], '-'
		je		rpn_subtraction
		jmp		rpn_notMinus
	rpn_subtraction:
		call	_rpn_pop_value
		cmp		dx, 1
		jne		rpn_subPop1OK
		mov		ax, rpn_underflowStr
		jmp		rpn_error
	rpn_subPop1OK:
		mov		bx, ax
		call	_rpn_pop_value
		cmp		dx, 1
		jne		rpn_subPop2OK
		mov		ax, rpn_underflowStr
		jmp		rpn_error
	rpn_subPop2OK:
		sub		ax, bx
		call	_rpn_push_value
		cmp		dx, 1
		jne		rpn_subPushOK
		mov		ax, rpn_overflowStr
		jmp		rpn_error
	rpn_subPushOK:
		jmp		rpn_expression
	rpn_notMinus:
		cmp		byte [si], '~'
		je		rpn_negation
		jmp		rpn_notTilde
	rpn_negation:
		call	_rpn_pop_value
		cmp		dx, 1
		jne		rpn_negPopOK
		mov		ax, rpn_underflowStr
		jmp		rpn_error
	rpn_negPopOK:
		neg		ax
		call	_rpn_push_value
		cmp		dx, 1
		jne		rpn_negPushOK
		mov		ax, rpn_overflowStr
		jmp		rpn_error
	rpn_negPushOK:
		jmp		rpn_expression
	rpn_notTilde:
		cmp		byte [si], '*'
		je		rpn_multiplication
		jmp		rpn_notAstrisk
	rpn_multiplication:
		call	_rpn_pop_value
		cmp		dx, 1
		jne		rpn_mulPop1OK
		mov		ax, rpn_underflowStr
		jmp		rpn_error
	rpn_mulPop1OK:
		mov		bx, ax
		call	_rpn_pop_value
		cmp		dx, 1
		jne		rpn_mulPop2OK
		mov		ax, rpn_underflowStr
		jmp		rpn_error
	rpn_mulPop2OK:
		imul	bx
		call	_rpn_push_value
		cmp		dx, 1
		jne		rpn_mulPushOK
		mov		ax, rpn_overflowStr
		jmp		rpn_error
	rpn_mulPushOK:
		jmp		rpn_expression
	rpn_notAstrisk:
		cmp		byte [si], '/'
		je		rpn_division
		jmp		rpn_notSlash
	rpn_division:
		call	_rpn_pop_value
		cmp		dx, 1
		jne		rpn_divPop1OK
		mov		ax, rpn_underflowStr
		jmp		rpn_error
	rpn_divPop1OK:
		mov		bx, ax
		call	_rpn_pop_value
		cmp		dx, 1
		jne		rpn_divPop2OK
		mov		ax, rpn_underflowStr
		jmp		rpn_error
	rpn_divPop2OK:
		cmp		bx, 0 ; check for divide by 0
		jne		rpn_continueDivide
		; divide by 0!
		mov		ax, rpn_div0Str
		jmp		rpn_error
	rpn_continueDivide:
		mov		dx, 0
		idiv	bx
		call	_rpn_push_value
		cmp		dx, 1
		jne		rpn_divPushOK
		mov		ax, rpn_overflowStr
		jmp		rpn_error
	rpn_divPushOK:
		jmp		rpn_expression
	rpn_notSlash:
		cmp		byte [si], '%'
		je		rpn_modulus
		jmp		rpn_expression ; if we get here, the character isn't an operator, ignore
	rpn_modulus:
		call	_rpn_pop_value
		cmp		dx, 1
		jne		rpn_modPop1OK
		mov		ax, rpn_underflowStr
		jmp		rpn_error
	rpn_modPop1OK:
		mov		bx, ax
		call	_rpn_pop_value
		cmp		dx, 1
		jne		rpn_modPop2OK
		mov		ax, rpn_underflowStr
		jmp		rpn_error
	rpn_modPop2OK:
		cmp		bx, 0 ; check for divide by 0
		jne		rpn_continueMod
		; divide by 0!
		mov		ax, rpn_div0Str
		jmp		rpn_error
	rpn_continueMod:
		mov		dx, 0
		idiv	bx
		mov		ax, dx ; remainder stored in dx
		call	_rpn_push_value
		cmp		dx, 1
		jne		rpn_modPushOK
		mov		ax, rpn_overflowStr
		jmp		rpn_error
	rpn_modPushOK:
		jmp		rpn_expression
		
	rpn_numberDone:
		mov		ax, word [rpn_curNum]
		call	_rpn_push_value
		cmp		dx, 1
		jne		rpn_curNumPushOK
		mov		ax, rpn_overflowStr
		jmp		rpn_error
	rpn_curNumPushOK:
		; set curNum & enteringNum to 0
		mov		word [rpn_curNum], 0
		mov		byte [rpn_enteringNum], 0
		; if char is 0 (NULL-terminator), done
		; else still need to process it
		cmp		byte [si], 0
		je		rpn_exprDone
		jmp		rpn_checkOperator
	
	rpn_exprDone:
		; set curNum & enteringNum to 0
		mov		word [rpn_curNum], 0
		mov		byte [rpn_enteringNum], 0
		; print value of expression
		call	_rpn_pop_value
		cmp		dx, 1
		jne		rpn_popAnsOK
		mov		ax, rpn_underflowStr
		jmp		rpn_error
	rpn_popAnsOK:
		; TODO: go digit-by-digit and convert decimal number to string, then print
		mov		si, rpn_resultStr
		add		si, 5 ; gets us past the '='
		mov		cx, ax ; to protect the answer, since idiv messes with AX
		; we'll divide by BX to get digits
		; largest number of digits that can fit in 16 bits is 5
		; so start with BX = 10000
		mov		bx, 10000
		cmp		cx, 0
		jge		rpn_decimalToString
		; negative answer, print '-' sign
		mov		byte [si], '-'
		inc		si
	rpn_decimalToString:
		cmp		bx, 0
		je		rpn_conversionDone
		; next digit is ans (in CX) / BX
		mov		dx, 0
		mov		ax, cx
		idiv	bx
		add		ax, '0' ; convert to ASCII char
		mov		byte [si], al ; and add to string
		; subtract digit * BX from CX to ditch the leading digit
		sub		ax, '0' ; get back to the decimal value
		imul	bx
		sub		cx, ax
		; divide BX by 10
		mov		dx, 0
		mov		ax, bx
		mov		bx, 10
		idiv	bx
		mov		bx, ax
		inc		si
		jmp		rpn_decimalToString
	rpn_conversionDone:
		mov		bl, 0
		mov		bh, 8
		mov		ch, 2
		mov		cl, 0
		mov		dh, 0
		mov		ax, rpn_resultStr
		call	_printString
		jmp		rpn_cleanUp
		
	; before jumping here, put error msg address in AX
	rpn_error:
		mov		bl, 0
		mov		bh, 8
		mov		ch, 4
		mov		cl, 0
		mov		dh, 0
		call	_printString
		
	rpn_cleanUp:
		mov		word [rpn_top], 0 ; reset rpn_top to top of rpn_stack
		call	_clearRPNString ; clear rpn_string
		mov		byte [rpn_evaluate], 0 ; turn off evaluate flag
		; and we're done!
		
rpn_printString:
	mov		bl, 0
	mov		bh, 6
	mov		cl, 0
	mov		ch, 7
	mov		dh, 0
	mov		ax, rpn_string
	call	_printString
	jmp		rpn_end
	
rpn_end:
	call	_yield
	jmp		_rpnCalculator

; helper function for _rpnCalculator
; pushes number in AX to rpn_stack
; clobbers DX
; returns 0 in DX if successful, 1 otherwise
_rpn_push_value:
	push	ax
	push	bx
	push	cx
	push	di
	; check for stack overflow
	cmp		word [rpn_top], 16
	; if rpn_top == rpn_stack + 16, stack is full, stack overflow error
	jne		doPush
	mov		dx, 1
	jmp		end_push_value

doPush:
	mov		di, rpn_stack
	add		di, [rpn_top]
	add		di, [rpn_top] ; add twice beacuse rpn_stack contains words (2 bytes)
	mov		[di], ax
	mov		dx, 0
	inc		word [rpn_top]

end_push_value:
	pop		di
	pop		cx
	pop		bx
	pop		ax
	ret

; helper function for _rpnCalculator
; pops number from rpn_stack
; clobbers AX, DX
; returns popped value in AX
;		  0 in DX if successful, 1 otherwise
_rpn_pop_value:
	push	bx
	push	cx
	push	di
	; check for stack underflow
	cmp		word [rpn_top], 0
	; if rpn_top == rpn_stack, stack is empty, stack underflow error
	jne		doPop
	mov		dx, 1
	jmp		end_pop_value

doPop:
	dec		word [rpn_top]
	mov		di, rpn_stack
	add		di, [rpn_top]
	add		di, [rpn_top] ; add twice beacuse rpn_stack contains words (2 bytes)
	mov		ax, [di]
	mov		dx, 0
	
end_pop_value:
	pop		di
	pop		cx
	pop		bx
	ret
	
; helper function for modifying <rpn_string>
; takes char in al and appends it to <rpn_string> at location of <rpn_strPointer>
; if al is 0, removes last char (replaces it with 0) and decrements <rpn_strPointer>
; if <rpn_strPointer> is at beginning/end of the <rpn_string>, function does nothing if
;	remove/append operation is requested
; clobbers nothing
; returns nothing
_addToRPNString:
	push	si
	push	ax
	push	bx
	push	cx
	push	dx
	cmp		byte [rpn_evaluate], 1
	je		end_addToRPNString
_notEvaluating:
	mov		si, rpn_string
	cmp		al, 0
	jne		rpnAppend
	jmp		rpnBackspace
rpnAppend:
	; if <rpn_strPointer> is pointing one past the end, do nothing
	cmp		word [rpn_strPointer], 54
	jne		doAppend
	jmp		end_addToRPNString
doAppend:
	add		si, [rpn_strPointer]
	mov		byte [si], al
	inc		word [rpn_strPointer]
	; move cursor ahead
	mov		ah, 0x03
	mov		bh, 0
	int		0x10
	inc		dl
	mov		ah, 0x02
	int		0x10
	jmp		end_addToRPNString
rpnBackspace:
	; if <rpn_strPointer> is pointing to beginning, do nothing
	cmp		word [rpn_strPointer], 0
	jne		doBackspace
	jmp		end_addToRPNString
doBackspace:
	dec		word [rpn_strPointer]
	add		si, [rpn_strPointer]
	mov		byte [si], " "
	; move cursor back
	mov		ah, 0x03
	mov		bh, 0
	int		0x10
	dec		dl
	mov		ah, 0x02
	int		0x10
	jmp		end_addToRPNString
end_addToRPNString:
	pop		dx
	pop		cx
	pop		bx
	pop		ax
	pop		si
	ret

; helper function for clearing <rpn_string>
; sets all characters of <rpn_string> to spaces and resets cursor position
; clobbers nothing
; returns nothing
_clearRPNString:
	push	si
	mov		si, rpn_string
	add		si, [rpn_strPointer]
clearLoop:
	cmp		si, rpn_string
	jne		clearChar
	jmp		end_clearRPNString
clearChar:
	dec		si
	mov		byte [si], " "
	jmp		clearLoop

end_clearRPNString:
	mov		byte [rpn_strPointer], 0
	; reset cursor
	mov		ah, 0x02
	mov		bh, 0
	mov		dh, 3
	mov		dl, 0
	int		0x10
	
	pop		si
	ret

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

; print NULL-terminated string to screen=
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
	mov		dl, [si]	; DL = current character
	inc		si			; advance SI to point at next character
	cmp		dl, 0		; if (DL == 0), stop
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
.check_offscreen:		; check if offscreen row or column
	cmp		bl, 160
	jae		.loop
	cmp		bh, 50
	jae		.end
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
	
; main function; draws headers/borders, monitors keypresses
_main:
	
	; set video mode
	mov		ah, 0x0
	mov		al, 0x3
	int		0x10
	
	; print headers/borders for other tasks
	mov		bl, 0 ; col
	mov		bh, 0 ; row
	mov		cl, 7 ; background
	mov		ch, 4 ; foreground
	mov		dh, 0 ; blink
	mov		ax, exit_header
	call	_printString
	
	mov		bl, 0
	mov		bh, 2
	mov		cl, 7
	mov		ch, 0
	mov		dh, 0
	mov		ax, rpn_header
	call	_printString
	
	mov		bl, 108
	mov		bh, 4
	mov		ch, 7
	mov		ax, rpn_rightBorder
	call	_printString
	
	mov		bl, 0
	mov		bh, 26
	mov		ch, 0
	mov		ax, gameOfLife_header
	call	_printString
	
	mov		bl, 40
	mov		bh, 30
	mov		ch, 7
	mov		ax, gameOfLife_rightBorder
	call	_printString
	
	; set cursor position to _rpnCalculator window
	mov		ah, 0x02
	mov		bh, 0
	mov		dh, 3
	mov		dl, 0
	int		0x10
	
infiniteLoop_main:
	
	; check for keypress
	cmp		byte [currentKey], 0x00
	jne		checkKey_leftShiftOn
	jmp		yield_Main ; no key pressed
checkKey_leftShiftOn:
	; check for shift to set <shift> boolean
	cmp		byte [currentKey], 0x2A ; left shift pressed
	jne		checkKey_rightShiftOn
	mov		byte [shift], 1
	jmp		yield_Main
checkKey_rightShiftOn:
	cmp		byte [currentKey], 0x36 ; right shift pressed
	jne		checkKey_leftShiftOff
	mov		byte [shift], 1
	jmp		yield_Main
checkKey_leftShiftOff:
	cmp		byte [currentKey], 0xAA ; left shift released
	jne		checkKey_rightShiftOff
	mov		byte [shift], 0
	jmp		yield_Main
checkKey_rightShiftOff:
	cmp		byte [currentKey], 0xB6 ; right shift released
	jne		checkKey_esc
	mov		byte [shift], 0
	jmp		yield_Main
checkKey_esc:
	; if ESC pressed, exit program
	cmp		byte [currentKey], 0x81
	jne		checkKey_space
	jmp		exit_program
checkKey_space:
	cmp		byte [currentKey], 0x39 ; spacebar
	jne		checkKey_backspace
	mov		al, ' '
	call	_addToRPNString
	jmp		yield_Main
checkKey_backspace:
	cmp		byte [currentKey], 0x0E ; backspace
	jne		checkKey_enter
	mov		al, 0
	call	_addToRPNString
	jmp		yield_Main
checkKey_enter:
	; if enter pressed, turn on rpn_evaluate flag
	; signals _rpnCalculator to evaluate the postfix string
	cmp		byte [currentKey], 0x1C ; enter
	jne		shiftBranch
	mov		byte [rpn_evaluate], 1
	jmp		yield_Main
shiftBranch:
	; start checking for character keypresses (numbers and operators only)
	; check operators first (no pattern)
	cmp		byte [shift], 1
	je		shiftOn
	jmp		shiftOff

shiftOn:
	; check keys that would be operators if shift is pressed (shift and = is +, shift and 8 is *, shift 5 is %)
	cmp		byte [currentKey], 0x0D ; =, i.e. +
	jne		checkShiftKey_8
	mov		al, '+'
	call	_addToRPNString
	jmp		yield_Main
checkShiftKey_8:
	cmp		byte [currentKey], 0x09 ; 8, i.e. *
	jne		checkShiftKey_5
	mov		al, '*'
	call	_addToRPNString
	jmp		yield_Main
checkShiftKey_5:
	cmp		byte [currentKey], 0x06 ; 5, i.e. %
	jne		checkShiftKey_backtick
	mov		al, '%'
	call	_addToRPNString
	jmp		yield_Main
checkShiftKey_backtick:
	cmp		byte [currentKey], 0x29 ; `, i.e. ~
	jne		doneShiftKey
	mov		al, '~'
	call	_addToRPNString
doneShiftKey:
	; no more keys to check with shift on
	jmp		yield_Main

shiftOff:
	; check for operators without shift
	cmp		byte [currentKey], 0x0C ; -
	jne		checkKey_slash
	mov		al, '-'
	call	_addToRPNString
	jmp		yield_Main
checkKey_slash:
	cmp		byte [currentKey], 0x35 ; /
	jne		checkKey_numpadPlus
	mov		al, '/'
	call	_addToRPNString
	jmp		yield_Main
checkKey_numpadPlus:
	cmp		byte [currentKey], 0x4E ; numpad +
	jne		checkKey_numpadMinus
	mov		al, '+'
	call	_addToRPNString
	jmp		yield_Main
checkKey_numpadMinus:
	cmp		byte [currentKey], 0x4A ; numpad -
	jne		checkKey_numpadStar
	mov		al, '-'
	call	_addToRPNString
	jmp		yield_Main
checkKey_numpadStar:
	cmp		byte [currentKey], 0x37 ; numpad *
	jne		checkKey_numpad0
	mov		al, '*'
	call	_addToRPNString
	jmp		yield_Main
checkKey_numpad0:
	; check for numbers
	; numpad numbers don't follow a pattern, so check those first
	cmp		byte [currentKey], 0x52 ; numpad 0
	jne		checkKey_numpad1
	mov		al, '0'
	call	_addToRPNString
	jmp		yield_Main
checkKey_numpad1:
	cmp		byte [currentKey], 0x4F ; numpad 1
	jne		checkKey_numpad2
	mov		al, '1'
	call	_addToRPNString
	jmp		yield_Main
checkKey_numpad2:
	cmp		byte [currentKey], 0x50 ; numpad 2
	jne		checkKey_numpad3
	mov		al, '2'
	call	_addToRPNString
	jmp		yield_Main
checkKey_numpad3:
	cmp		byte [currentKey], 0x51 ; numpad 3
	jne		checkKey_numpad4
	mov		al, '3'
	call	_addToRPNString
	jmp		yield_Main
checkKey_numpad4:
	cmp		byte [currentKey], 0x4B ; numpad 4
	jne		checkKey_numpad5
	mov		al, '4'
	call	_addToRPNString
	jmp		yield_Main
checkKey_numpad5:
	cmp		byte [currentKey], 0x4C ; numpad 5
	jne		checkKey_numpad6
	mov		al, '5'
	call	_addToRPNString
	jmp		yield_Main
checkKey_numpad6:
	cmp		byte [currentKey], 0x4D ; numpad 6
	jne		checkKey_numpad7
	mov		al, '6'
	call	_addToRPNString
	jmp		yield_Main
checkKey_numpad7:
	cmp		byte [currentKey], 0x47 ; numpad 7
	jne		checkKey_numpad8
	mov		al, '7'
	call	_addToRPNString
	jmp		yield_Main
checkKey_numpad8:
	cmp		byte [currentKey], 0x48 ; numpad 8
	jne		checkKey_numpad9
	mov		al, '8'
	call	_addToRPNString
	jmp		yield_Main
checkKey_numpad9:
	cmp		byte [currentKey], 0x49 ; numpad 9
	jne		checkKey_numbers
	mov		al, '9'
	call	_addToRPNString
	jmp		yield_Main
checkKey_numbers:
	; check non-numpad numbers (these follow a pattern)
	; numbers run from 0x02 to 0x0B, so we can check the range and get char by its difference from 0x02
	cmp		byte [currentKey], 0x02
	jl		yield_Main ; safe to bail at this point because we've checked all of the cases outside the range
	cmp		byte [currentKey], 0x0B
	jg		yield_Main
	jl		notZero
	; zero comes after other numbers, not before, so we have to handle it separately
	mov		al, '0'
	call	_addToRPNString
	jmp		yield_Main
notZero:
	mov		al, '0'
	dec		al
	add		al, [currentKey]
	call	_addToRPNString

yield_Main:
	mov		byte [currentKey], 0
	call	_yield
	; pause after drawing updates
	mov		ah, 0x86
	mov		cx, 0
	mov		dx, 0xFFFF
	int		0x15

	jmp		infiniteLoop_main

exit_program:
	mov		byte [currentKey], 0
	; set video mode once more to clear screen
	mov		ah, 0x0
	mov		al, 0x3
	int		0x10
	jmp		terminate
	
; custom keyboard hardware interrupt
keyboard:
	push	ax
	in		al, 0x60
	mov		byte [currentKey], al
	mov		al, 0x20
	out		0x20, al
	pop		ax
	iret
	
SECTION .data
	; global variables
	;	strings
	exit_header: db "                            -- Press ESC to exit --                             ", 0
	rpn_header: db "                    RPN Calculator                               Music          ", 0
	rpn_rightBorder: times 11 db " ", 13, 10
					 db 0
	gameOfLife_header:	db "   John Conway's                                                                ", 13, 10
						db "   Game of Life                              Graphics                           ", 0
	gameOfLife_grid: db ' *                    *                 ***                                                                                                                                                             '
	gameOfLife_rightBorder: times 10 db " ", 13, 10
							db 0
	
	; tasks A & B
	taskA_str: db "I am task A", 0
	taskB_str: db "I am", 13, 10, "task B", 0
	taskA_dir: db 1
	taskB_dir: db 0
	
	; RPN calculator
	rpn_string: times 54 db " " ; max length: 54
				db 0
	rpn_strPointer: dw 0 ; initialized to 0
	rpn_stack: times 16 dw 0
	rpn_top: dw 0
	rpn_curNum: dw 0
	rpn_enteringNum: db 0 ; bool variable to track if last input was a number
	rpn_evaluate: db 0
	rpn_resultStr: db "  =                                                   ", 0
	rpn_underflowStr: db "  Stack underflow!                                    ", 0
	rpn_overflowStr: db "  Stack overflow!                                     ", 0
	rpn_div0Str: db "  Divide by 0!                                        ", 0
	
	; custom keyboard interrupt
	;	current key scan code
	currentKey: db 0
	;	shift pressed boolean
	shift: db 0
	;	address of previous 0x09 interrupt
	previous9: dd 0

	; global variables for stacks
	current_task: db 0
	stacks: times (256 * 6) db 0 ; 6 fake stacks of size 256 bytes
	task_status: times 6 db 0 ; 0 means inactive, 1 means active
	stack_pointers: dw 0 ; the first pointer needs to be to the real stack !
					dw stacks + (256 * 1)
					dw stacks + (256 * 2)
					dw stacks + (256 * 3)
					dw stacks + (256 * 4)
					dw stacks + (256 * 5)
					dw stacks + (256 * 6)
					dw stacks + (256 * 7)
