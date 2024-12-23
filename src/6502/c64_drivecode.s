; Part of the Commodore 64 Aa-machine
; frontend by Linus Akesson.

; Designed for the xa65 assembler.

; This code runs on the floppy drive.

; Serial protocol
; ---------------

; drive busy -- nothing is pulled
; drive ready for command -- pulls data
; host sends 10 bits at clock edges
; (both positive and negative)
; (drive releases data on first clock)
; drive busy -- nothing is pulled
; if load command...

; drive ready to transmit -- pulls data
; host pulls clock
; drive outputs first data bit
; host receives 8*256 bits at clock
; edges (positive and negative)
; host pulls clock one last time
; drive pulls data if reading went ok
; (i.e. disk ID matched)
; host releases clock
; drive releases data
; drive busy -- nothing is pulled

; commands are transmitted msb first
; data is transmitted lsb first

; command 0..662
;	load sector
; command 768 ($300)
;	uninstall loader
; command 769 ($301)
;	turn off led and motor

; disk addressing
; =====================================
; track 1, linear sectors 0..20
; track 2, linear sectors 21..41
; ...
; track 17, linear sectors 336..356
; track 19, linear sectors 356..374
; ...
; track 35, linear sectors 647..663

#define SAX1800 .byt $8f,$00,$18

INTERLEAVE = 11

buffer	= $600

	* = $400

	lda	#18
	sta	$a
	lda	#10
	sta	$b
	lda	#2
	sta	$f9
	jsr	$d586	; read block into $500

getcommand
	sei
	lda	$1800
	and	#$60
	ora	#$03
	tax

	ldy	#$00
	sty	cmdmsb
	lda	#$40
	sta	cmdlsb

	lda	#$02
	sta	$1800
cmdloop
	cpx	$1800
	bcs	*-3

	sty	$1800

	lda	$1800
	lsr
	rol	cmdlsb
	rol	cmdmsb

	cpx	$1800
	bcc	*-3

	lda	$1800
	lsr
	rol	cmdlsb
	rol	cmdmsb
	bcc	cmdloop

	lda	cmdmsb
	cmp	#$03
	bne	nospecial

	lda	cmdlsb
	bne	nouninst

	lda	$1c00
	; motor and led on
	ora	#$0c
	sta	$1c00
	cli
	rts
nouninst
	lda	$1c00
	; motor and led off
	and	#$f3
	sta	$1c00

	lda	#$a0 ; wait for spinup
	sta	$20
	lda	#$3c ; spinup timeout
	sta	$48

	jmp	getcommand
nospecial
	; convert to t&s

	ldx	#1
	lda	cmdlsb
trloop
	cmp	nsector-1,x
	bcs	nexttr

	ldy	cmdmsb
	beq	foundtr

	sec
nexttr
	inx
	sbc	nsector-2,x
	bcs	trloop

	dec	cmdmsb
	bpl	trloop ; always
foundtr
	tay
	lda	#0
	;clc
interleave
	dey
	bmi	founds

	adc	#INTERLEAVE
	cmp	nsector-1,x
	bcc	interleave

	sbc	nsector-1,x
	clc
	bcc	interleave
founds
	stx	$c
	sta	$d

	; motor and led on
	lda	$1c00
	ora	#$0c
	sta	$1c00

	lda	#$80
	sta	$03

	cli
waitjob
	bit	$03
	bmi	waitjob

	sei

	lda	#$01 ; all ok
	cmp	$03
	bne	transfer

	asl
	bne	transfer ; always

nsector
	.dsb	17,21
	.byt	0	; track 18
	.dsb	6,19
	.dsb	6,18
	.dsb	5,17

cmdlsb
	.byt	0
cmdmsb
	.byt	0

	; keep the transfer loop
	; on a single page

	.dsb	$500-*,$ee

transfer
	pha

	lda	$1800
	and	#$60
	ora	#$03
	tax

	ldy	#0

	lda	#$02
	bne	sendentry ; always
sendloop
	cpx	$1800
	bcs	*-3
	SAX1800

	lsr

	cpx	$1800
	bcc	*-3
	SAX1800

	lsr

	cpx	$1800
	bcs	*-3
	SAX1800

	lsr

	cpx	$1800
	bcc	*-3
	SAX1800

	lsr

	cpx	$1800
	bcs	*-3
	SAX1800

	lsr
	iny
	beq	senddone

	cpx	$1800
	bcc	*-3
sendentry
	SAX1800

	lda	buffer,y
	asl

	cpx	$1800
	bcs	*-3
	SAX1800

	lda	buffer,y

	cpx	$1800
	bcc	*-3
	SAX1800

	lsr
	bpl	sendloop ; always
senddone
	cpx	$1800
	bcc	*-3
	SAX1800

	pla	; status code

	cpx	$1800
	bcs	*-3
	SAX1800

	cpx	$1800
	bcc	*-3
	sty	$1800

	jmp	getcommand

	.dsb	$600-*,$ee
