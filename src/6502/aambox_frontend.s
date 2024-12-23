; aambox6502 aa-machine frontend
; by Linus Akesson.

; Designed for the xa65 assembler.

; The aambox is an imaginary 6502-based
; computer emulated by a commandline
; tool, to support automated testing
; of the engine. See aambox6502.c.

TRACE_INST	= 0
TRACE_STORE	= 0

DEFWIDTH	= 80
PREXTRA		= 2
PRSHIFT		= 0
HAVE_QUIT	= 1
HAVE_STATUS	= 0

wrappos		= $00
xpos		= $01
pendspc		= $02
f_temp		= $03
f_temp2		= $04
ioparam		= $05	; word

wrapbuf		= $280

	* = $0300

	cld
	ldx	#$ff
	txs

	lda	#0
	sta	wrappos
	sta	xpos
	sta	pendspc

	jsr	initengine0
	jsr	initengine1
	jsr	initengine2
	jsr	initengine3
	jsr	initengine4
	jsr	initengine5
	jmp	startengine

; Main text area

io_mputc
	; input a = char

	.(
	cmp	#$20
	beq	space

	ldx	xpos
	cpx	#DEFWIDTH
	bcs	wrap
postwrap
	ldx	wrappos
	sta	wrapbuf,x
	inc	wrappos
	inc	xpos

	cmp	#$2d
	beq	io_mflush

	rts
space
	jsr	io_mflush
	inc	pendspc
	inc	xpos
	rts
wrap
	pha
	jsr	io_mline_raw
	ldx	wrappos
	stx	xpos
	jsr	io_mflush
	pla
	jmp	postwrap
	.)

io_mclear
io_mline
	jsr	io_mflush
io_mline_raw
	.(
	lda	#10
	sta	$0200
	lda	#0
	sta	xpos
	sta	pendspc
	rts
	.)

io_mflush
	.(
	ldx	pendspc
	beq	nospc
spcloop
	lda	#$20
	sta	$0200
	dex
	bne	spcloop

	stx	pendspc
nospc
	;ldx	#0
	cpx	wrappos
	beq	done
loop
	lda	wrapbuf,x
	bpl	noext

	jsr	lookupchar
	bcs	skip

	ldy	#3
	lda	(ioparam),y
	cmp	#8
	bcs	big

	sta	f_temp
	iny
	lda	(ioparam),y
	lsr	f_temp
	ror
	lsr	f_temp
	ror
	lsr	f_temp
	ror
	lsr
	lsr
	lsr
	ora	#$c0
common
	sta	$0200
	lda	(ioparam),y
	and	#$3f
	ora	#$80
noext
	sta	$0200
skip
	inx
	cpx	wrappos
	bne	loop
done
	lda	#0
	sta	wrappos
	rts
big
	lsr
	lsr
	lsr
	lsr
	ora	#$e0
	sta	$0200
	lda	(ioparam),y
	sta	f_temp
	iny
	lda	(ioparam),y
	lsr	f_temp
	ror
	lsr	f_temp
	ror
	lsr	f_temp
	ror
	lsr	f_temp
	lsr
	lsr
	sec
	ror
	bmi	common ; always
	.)

io_mstyle
	; input a = style bits

	.(
	rts
	.)

io_mprogress
	; input x = progress
	; input y = total
	; where 0 <= x <= y
	; and y =
	; (width << PRSHIFT) - PREXTRA

	.(
	lda	#'['
	sta	$0200
	stx	f_temp
	sty	f_temp2
	ldx	#0
loop
	lda	#$20
	cpx	f_temp
	bcs	past

	lda	#$3d
past
	sta	$0200
	inx
	cpx	f_temp2
	bcc	loop

	lda	#']'
	sta	$0200
	rts
	.)

; Status bar area

io_sprepare
	; input a = height

	.(
	rts
	.)

io_slocate
	; input x = column
	; input y = row

	.(
	rts
	.)

io_sputc
	; input a = char

	.(
	rts
	.)

io_sprogress
	; input x = progress
	; input y = total
	; where 0 <= x <= y
	; and y =
	; (width << PRSHIFT) - PREXTRA

	.(
	rts
	.)

io_scommit
	.(
	rts
	.)

; Input

io_getc
	; output a = char

	.(
	jsr	io_mflush
	jsr	io_get_utf8
	cmp	#10
	bne	noret

	lda	#13
noret
	rts
	.)

io_gets
	; input ioparam = buffer
	; (room for 64 chars)
	; output y = length

	.(
	jsr	io_mflush
	ldy	#0
loop
	jsr	io_get_utf8
	cmp	#10
	beq	done

	cpy	#64
	beq	loop

	sta	(ioparam),y
	iny
	jmp	loop
done
	lda	#0
	sta	xpos
	sta	pendspc
	rts
	.)

io_get_utf8
	; output a = char

	.(
again
	lda	$0201
	bpl	done

	and	#$1f
	sta	f_temp
	lda	$0201
	asl
	asl
	lsr	f_temp
	ror
	lsr	f_temp
	ror
	sta	f_temp2

	tya
	pha
	lda	ioparam
	pha
	lda	ioparam+1
	pha

	ldx	#$80
loop
	txa
	jsr	lookupchar
	bcs	badchar

	ldy	#2
	lda	(ioparam),y
	bne	next

	iny
	lda	(ioparam),y
	cmp	f_temp
	bne	next

	iny
	lda	(ioparam),y
	cmp	f_temp2
	beq	found
next
	inx
	jmp	loop
badchar
	jsr	found
	jmp	again
found
	pla
	sta	ioparam+1
	pla
	sta	ioparam
	pla
	tay
	txa
done
	rts
	.)

; System

io_quit
	sta	$0202
	jmp	*

io_random
	; output x = lsb, y = msb
	; range is 0..7fff

	sta	$0230
	ldx	$0231
	ldy	$0232
	rts

io_restart
	sta	$0247
	rts

io_save
	; input x = size lsb
	; input y = size msb
	; data at SAVEADDR
	; output c = success

	.(
	lda	#<SAVEADDR
	sta	$0250
	lda	#>SAVEADDR
	sta	$0251
	stx	$0252
	sty	$0253
	sta	$0254
	sec
	rts
	.)

io_load
	; verify AASV header, 12 bytes
	; if ok, put file at SAVEADDR
	; and set c
	; otherwise, clear c

	.(
	lda	#<SAVEADDR
	sta	$0250
	lda	#>SAVEADDR
	sta	$0251
	sta	$0255
	lda	$0256
	lsr
	bcc	fail

	sta	$0247
fail
	rts
	.)

io_undosupp
	; output c = undo supported

	sec
	rts

io_saveundo
	; input x = byte size lsb
	; input y = byte size msb
	; input ioparam = start of data
	; output c = success

	.(
	lda	ioparam
	sta	$0240
	lda	ioparam+1
	sta	$0241
	stx	$0242
	sty	$0243
	sta	$0244
	sec
	rts
	.)

io_loadundo
	; input x = byte size lsb
	; input y = byte size msb
	; input ioparam = dest address
	; output a = status
	;	0 ok
	;	1 no more entries
	;	2 error

	.(
	lda	ioparam
	sta	$0240
	lda	ioparam+1
	sta	$0241
	stx	$0242
	sty	$0243
	sta	$0245
	lda	$0246
	rts
	.)

io_readpage

	; input x = physical ram target page
	; input ioparam = virtual address 23..8, l-e
	; output a = physical ram target page

	.(
	stx	$0212
	lda	ioparam
	sta	$0210
	lda	ioparam+1
	sta	$0211
	sta	$0213
	txa
	rts
	.)

#include "engine.s"

SAFEPG = (* + $ff) >> 8
RAMEND = $10000

SAVEADDR = SAFEPG << 8
