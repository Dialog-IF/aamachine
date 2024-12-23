; Part of the Commodore 64 Aa-machine
; frontend by Linus Akesson.

; Designed for the xa65 assembler.

; This is a small decruncher that
; unpacks compressed data (located
; immediately after this code) to
; address $1100 and jumps to it.

srcptr	= $02
destptr	= $04

	* = $8000

	lda	dataend
	sta	srcptr
	lda	dataend+1
	sta	srcptr+1
	lda	targetend
	sta	destptr
	lda	targetend+1
	sta	destptr+1

chunkloop
	lda	srcptr
	sec
	sbc	#1
	sta	srcptr
	bcs	noc3

	dec	srcptr+1
noc3
	lda	srcptr
	cmp	#<datastart

	ora	#$0e
	sta	$d020

	lda	srcptr+1
	sbc	#>datastart
	bcc	chunkdone

	ldy	#0
	lda	(srcptr),y
	bmi	copy

	tay
	eor	#$ff
	tax
	clc
	adc	srcptr
	sta	srcptr
	bcs	noc1

	dec	srcptr+1
noc1
	txa
	clc
	adc	destptr
	sta	destptr
	bcs	noc2

	dec	destptr+1
	sec
noc2
litloop
	lda	(srcptr),y
	sta	(destptr),y
	dey
	bpl	litloop

	jmp	chunkloop
copy
	tay
	and	#$1f
	tax
	tya
	and	#$60
	beq	long

	lsr
	lsr
	lsr
	lsr
	lsr
	tay
common
	; y = a = length - 1
	; x = offset - 1
	; c = 0

	eor	#$ff
	;clc
	adc	destptr
	sta	destptr
	bcs	noc4

	dec	destptr+1
	sec
noc4
	txa
	;sec
	adc	destptr
	sta	mod_copy+1
	lda	destptr+1
	adc	#0
	sta	mod_copy+2
cploop
mod_copy
	lda	!0,y
	sta	(destptr),y
	dey
	bpl	cploop

	bmi	chunkloop ; always
long
	txa
	tay
	iny
	iny

	ldx	srcptr
	bne	noc5

	dec	srcptr+1
noc5
	dex
	stx	srcptr

	ldx	#0
	lda	(srcptr,x)
	tax
	tya
	clc
	bcc	common ; always

chunkdone
	jmp	$1100

	; The following parameters are
	; filled in by the cruncher.

targetend
	.word	0
dataend
	.word	0
datastart
