; Part of the Commodore 64 Aa-machine
; frontend by Linus Akesson.

; Designed for the xa65 assembler.

; This small program will be loaded by
; the normal (slow) DOS routines.
; It installs itself at $1000, then
; loads the self-decompressing
; interpreter at address $8000 and
; jumps to it.

; Loader calls
; =====================================
; 1000	take over drive
; 1003	release drive (e.g. for save)
; 1006	turn drive motor off
; 1009	load a sector
;		x = linear sector lsb
;		y = linear sector msb
;		a = dest address msb
;		output c = success

resaddr	= $1000

	.word	$801
	* = $801
	.byt	$b,$8,<1,>1,$9e,"2061",0,0,0

	.(
	ldx	#0
loop
	lda	message,x
	beq	done

	jsr	$ffd2
	inx
	jmp	loop
done
	.)

	.(
	lda	#$e
	ldx	#4
loop
	sta	$d800,y
	iny
	bne	loop

	inc	loop+2
	dex
	bne	loop

	lda	#$6
	sta	$d021
	lda	#$16
	sta	$d018

	lda	nsector
	lsr
	lsr
	tax
	lda	#$6b
	sta	$400+40+22,x
	.)

	.(
loop
	lda	rescode,y
	sta	resaddr,y
	iny
	bne	loop
	.)

	.(
	lda	$ba
	beq	defba

	sta	gamedev
defba
	.)

	jsr	res_install

	lda	#$7f
	sta	$dc0d
	lda	#0
	sta	$d01a
	lda	#$3c
	sta	$dd02
	lda	#$35
	sta	1

	.(
loop
	ldx	firstsector
	ldy	firstsector+1
	jsr	res_load_entry

	lda	mod_dest+2
	and	#$7f
	ldx	#0
	lsr
	bcc	noc1

	inx
noc1
	lsr
	bcc	noc2

	inx
	inx
noc2
	tay
	lda	$400+40+22,y
	cmp	#$6b
	beq	skip

	lda	gfx,x
	sta	$400+40+22,y
skip
	inc	mod_dest+2
	dec	nsector
	beq	done

	inc	firstsector
	bne	loop

	inc	firstsector+1
	bne	loop ; always
done
	.)

	jsr	res_motoroff

	jmp	$8000

gfx
	.byt	$74
	.byt	$61
	.byt	$e7
	.byt	$a0

rescode
	* = resaddr

	jmp	res_install
	jmp	res_uninstall
	jmp	res_motoroff
res_load
	.(
	sta	mod_dest+2

	and	#$f0
	cmp	#$d0
	bne	noio

	lda	#gotbyte_io-mod_divert-2
	sta	mod_divert+1
	lda	mod_dest+2
	sta	mod_dest_io+2
noio
+res_load_entry
	jsr	sendcmd

	bit	$dd00
	bmi	*-3

	ldy	#$10
	sty	$dd00 ; pull

	; at least 11 cycles between
	; sty and cpx

	ldx	#$7f
	lda	#$80
	bmi	bitentry ; always
bitloop
	ror

	cpx	$dd00
	sty	$dd00 ; pull

	ror
mod_divert
	bcs	gotbyte

	bit	0
bitentry
	nop
	ldy	#$00

	cpx	$dd00
	sty	$dd00 ; release

	nop
	nop
	ldy	#$10
	jmp	bitloop
gotbyte
+mod_dest
	sta	$8000
	lda	#$80

	cpx	$dd00
	sta	$dd00 ; release

	inc	mod_dest+1
	bne	bitloop

	rts
gotbyte_io
	dec	1
mod_dest_io
	sta	$8000
	inc	1

	lda	#$80

	cpx	$dd00
	sta	$dd00 ; release

	inc	mod_dest_io+1
	bne	bitloop

	lda	#gotbyte-mod_divert-2
	sta	mod_divert+1
	rts
	.)

res_uninstall
	.(
	ldx	#0
	ldy	#3
	jmp	sendcmd
	.)

res_motoroff
	.(
	ldx	#1
	ldy	#3
	;jmp	sendcmd
	.)

sendcmd
	.(
	stx	shift
	tya

	asl	shift
	rol
	asl	shift
	rol
	asl	shift
	rol
	sta	shift+1

	bit	$dd00
	bmi	*-3

	ldy	#5
bitloop
	; ensure at least 32 cycles
	; between clock edges

	asl	shift
	rol	shift+1
	lda	shift+1
	and	#$20
	ora	#$10
	sta	$dd00

	asl	shift
	rol	shift+1
	nop
	nop
	nop
	nop
	nop
	lda	shift+1
	and	#$20
	sta	$dd00

	bit	0
	dey
	bne	bitloop

	lda	#0
	jsr	delay
	pha
	pla
	sta	$dd00
delay
	rts
	.)

res_install
	.(
	ldx	#<command
	ldy	#>command
	lda	#commandsz
	jsr	$ffbd

	lda	#15
	tay
	ldx	gamedev
	jsr	$ffba

	jmp	$ffc0
	.)

command
	.(
	.byt	"M-E"
	.word	$205

	; load into buffer 1 at $400
	lda	#18
	sta	$8
	lda	#2
	sta	$9
	lda	#1
	sta	$f9
	jsr	$d586

	jmp	$400
	.)
commandsz = * - command

shift
	.word	0

ressize	= * - resaddr
	.dsb	$ff-ressize,$dd
gamedev
	.byt	8

	* = rescode + (* - resaddr)

message
	.byt	$93,13," lOADING INTERPRETER ",$b3,0

	; The following parameters are
	; filled in by aambundle.

firstsector
	.word	0
nsector
	.byt	0
