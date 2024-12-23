; Commodore 64 Aa-machine frontend
; by Linus Akesson.

; Designed for the xa65 assembler.

; Memory map
; =====================================
;
;  0000 - 01ff	zero-page and stack
;  0200 - 03ff	kernal variables
;  0400 - 07ff	video matrix
;  0800 - 0fff	font and cursor sprite
;  1000 - 10ff	resident loader
;  1100 -~5000	interpreter code, 16 kB
; ~5000 -~b000	page buffers, 24 kB
; ~b000 - fcff	dynamic data, 19 kB
;  fd00 - fff9	statically linked data
;  fffa - ffff	vectors

TRACE_INST	= 0
TRACE_STORE	= 0
MEASURE_TIME	= 0

DEFWIDTH	= 40
PREXTRA		= 8
PRSHIFT		= 2
HAVE_QUIT	= 0
HAVE_STATUS	= 1

REPEATRATE	= 2
REPEATDELAY	= 25

CH_ARING	= $09
CH_PROGB	= $19
CH_PROGE	= $1a
CH_PROG0	= $1b
CH_PROG1	= $1c
CH_PROG2	= $1d
CH_PROG3	= $1e
CH_PROG4	= $1f

ioparam	= $02	; word
lfsr	= $04	; word
stline	= $06	; word
stcram	= $08	; word
iocram	= $0a	; word
iocram2	= $0c	; word
stxoffs	= $0e
currfg	= $0f

reutop	= $10
anyundo	= $11
undoend	= $12	; word
undopos	= $14	; word

kmatrix	= $18	; 8 bytes

keywpos	= $20
keyrpos	= $21
repkey	= $22
reprow	= $23
reptimr	= $24
keymod	= $25
inppos	= $26
inplen	= $27
nunread	= $28
inpmax	= $29
fnlen	= $2a
inpterm	= $2b
k_size	= $2c	; word

#if MEASURE_TIME
measure	= $2f
#endif

wrappos	= $30
xpos	= $31
pendspc	= $32
f_temp	= $33
f_temp2	= $34
statush	= $35
ypos	= $36
ioline	= $37	; word
ioline2	= $39	; word
xoutpos	= $3b
cursy	= $3c
motoron	= $3d
k_wpos	= $3e
currdev	= $3f

vm	= $400

KEY_DEL	= $08
KEY_RET	= $0d
KEY_UP	= $10
KEY_DWN	= $11
KEY_LFT	= $12
KEY_RGT	= $13

KEY_STP	= $80
KEY_F1	= $81
KEY_F2	= $82
KEY_F3	= $83
KEY_F4	= $84
KEY_F5	= $85
KEY_F6	= $86
KEY_F7	= $87
KEY_F8	= $88

KEY_PND	= $00
KEY_HOM	= $00
KEY_ESC	= $00
KEY_INS	= $00
KEY_CLR	= $00
KEY_RUN	= $00

load_install	= $1000
load_uninstall	= $1003
load_motoroff	= $1006
load_read	= $1009
load_gamedev	= $10ff

k_ptr	= $fb

; Memory area 0800-0fff is primarily
; used for the font. But not all
; characters are used by the engine.

; 0800-083f 00-07 cursor sprite
; 0840-0847 08    backspace
; 0848-084f 09    A-ring at init
; 0850-0867 0a-0c 24 unused bytes
; 0868-086f 0d    return
; 0870-087f 0e-0f filename buffer
; 0880-089f 10-13 cursor keys
; 08a0-08c7 14-18 wordwrap buffer
; 08c8-08ff 19-1f progress bar chars
; 0900-0bf7 20-7e ascii chars
; 0bf8-0bff 7f    keyboard queue
; 0c00-     80-   extended chars

fnbuf	= $0870	; 16 bytes
wrapbuf	= $08a0	; 40 bytes
keyq	= $0bf8	; 8 bytes

KEYQLEN		= 8
FNAMESZ	= 16

	* = $1100

c64_entry
	jsr	c64init
	jsr	io_clearall
	jmp	startengine

; Main text area

io_clearall
	.(
	lda	#0
	sta	nunread
	jsr	io_sprepare
	;jmp	io_mclear
	.)

io_mclear
	.(
	lda	nunread
	beq	allread

	jsr	moreprompt
allread
	lda	statush
	sta	ypos
	jsr	set_ioline

	lda	#25
	sec
	sbc	statush
	tax
yloop
	ldy	#39
	lda	#$20
xloop
	sta	(ioline),y
	dey
	bpl	xloop

	dex
	beq	ydone

	lda	ioline
	clc
	adc	#40
	sta	ioline
	bcc	yloop

	inc	ioline+1
	bne	yloop	; always
ydone
	stx	xpos
	stx	wrappos

	;jmp	set_ioline
	.)

set_ioline
	.(
	lda	#<vm+24*40
	ldx	#>vm+24*40
	ldy	ypos

	cpy	#24
	bcs	done
loop
	sec
	sbc	#40
	bcs	noc1

	dex
noc1
	iny
	cpy	#24
	bcc	loop
done
	sta	ioline
	sta	iocram
	txa
	sta	ioline+1
	eor	#>(vm^$d800)
	sta	iocram+1
	rts
	.)

io_mputc
	; input a = char

	.(
#if MEASURE_TIME
	lsr	measure
	bcc	nomeas

	inc	1
	sta	$de00
	dec	1
nomeas
#endif

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
	beq	dash

	rts
dash
	jmp	io_mflush
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

io_mline
	jsr	io_mflush
io_mline_raw
	.(
	lda	#0
	sta	xpos
	sta	xoutpos
	sta	pendspc
	inc	nunread

	ldx	ypos
	cpx	#24
	beq	scroll

	inc	ypos
	lda	ioline
	clc
	adc	#40
	sta	ioline
	sta	iocram
	bcc	noc1

	inc	ioline+1
	inc	iocram+1
noc1
done
	rts
scroll
	jsr	scrollvm
	lda	nunread
	clc
	adc	statush
	cmp	#24
	bcc	done

	;jmp	moreprompt
	.)

moreprompt
	.(
	inc	1
	ldy	#0
loop
	lda	moretxt,y
	beq	done

	sta	(ioline),y
	lda	#$0
	sta	(iocram),y
	iny
	bpl	loop
done
	sty	xoutpos
	dec	1
	jsr	io_getc_raw

	lda	#$20
	ldy	xoutpos
	dey
clr
	sta	(ioline),y
	dey
	bpl	clr

	iny
	sty	xoutpos
	rts
moretxt
	.byt	"[...]",0
	.)

scrollvm
	; move contents of vm
	; one line up,
	; clear last line
	; and set ioline to
	; last line

	; clobbers ioline2

	.(
	inc	1

	lda	#<vm
	sta	ioline
	sta	iocram
	lda	#>vm
	sta	ioline+1
	lda	#>$d800
	sta	iocram+1
	ldy	statush
	ldx	#24
stloop
	dey
	bmi	stdone

	dex
	lda	ioline
	clc
	adc	#40
	sta	ioline
	bcc	stloop

	inc	ioline+1
	jmp	stloop
stdone
	lda	ioline
	sta	iocram
	clc
	adc	#40
	sta	ioline2
	sta	iocram2
	lda	ioline+1
	adc	#0
	sta	ioline2+1
	eor	#>(vm^$d800)
	sta	iocram2+1
loop1
	ldy	#39
loop2
	lda	(ioline2),y
	sta	(ioline),y
	lda	(iocram2),y
	sta	(iocram),y
	dey
	bpl	loop2

	lda	ioline2
	sta	ioline
	sta	iocram
	clc
	adc	#40
	sta	ioline2
	sta	iocram2
	lda	ioline2+1
	sta	ioline+1
	eor	#>(vm^$d800)
	sta	iocram+1
	adc	#0
	sta	iocram2+1
	eor	#>(vm^$d800)
	sta	ioline2+1

	dex
	bne	loop1

	ldy	#39
	lda	#$20
loop3
	sta	(ioline),y
	dey
	bpl	loop3

	dec	1
	rts
	.)

io_mflush
	.(
	ldy	xoutpos
	ldx	pendspc
	beq	nospc
spcloop
	lda	#$20
	sta	(ioline),y
	iny
	dex
	bne	spcloop

	stx	pendspc
nospc
	;ldx	#0
	cpx	wrappos
	beq	done

	lda	1
	pha
	lda	#$35
	sta	1
loop
	lda	wrapbuf,x
	sta	(ioline),y
	lda	currfg
	sta	(iocram),y
	iny
	inx
	cpx	wrappos
	bne	loop

	pla
	sta	1
done
	sty	xoutpos
	lda	#0
	sta	wrappos
	rts
	.)

io_mstyle
	; input a = style bits

	.(
	pha
	jsr	io_mflush
	pla
	lsr
	and	#3
	tax
	lda	palette,x
	sta	currfg
	rts
palette
	.byt	$0	; normal
	.byt	$b	; bold
	.byt	$6	; italic
	.byt	$e	; italic bold
	.)

io_mprogress
	; input x = progress
	; input y = total
	; where 0 <= x <= y
	; and y =
	; (width << PRSHIFT) - PREXTRA
	; assume we're on a new line

	.(
	sty	f_temp
	inc	1
	lda	currfg
	ldy	#39
loop
	sta	(iocram),y
	dey
	bpl	loop
	dec	1

	iny
	sty	stxoffs

	lda	ioline
	sta	stline
	lda	ioline+1
	sta	stline+1
	ldy	f_temp
	jmp	io_sprogress
	.)

; Status bar area

io_sprepare
	; input a = height

	.(
	sta	statush
	ldx	ypos
	cpx	statush
	bcs	noadj

	sta	ypos
	lda	#0
	sta	xpos
	sta	xoutpos
	sta	wrappos
	jsr	set_ioline
noadj
	inc	1

	ldy	#39
	lda	#$20
clr0
	sta	wrapbuf,y
	dey
	bpl	clr0

	lda	#<vm+40
	sta	stline
	sta	stcram
	lda	#>vm+40
	sta	stline+1
	lda	#>$d800
	sta	stcram+1

	ldx	statush
	beq	done
clear
	dex
	beq	done

	ldy	#39
	lda	#$20
loop1
	sta	(stline),y
	dey
	bpl	loop1

	ldy	#39
	lda	#$f
loop2
	sta	(stcram),y
	dey
	bpl	loop2

	lda	stline
	clc
	adc	#40
	sta	stline
	sta	stcram
	bcc	clear

	inc	stline+1
	inc	stcram+1
	jmp	clear
done
	dec	1
	rts
	.)

io_slocate
	; input x = column
	; input y = row

	.(
	stx	stxoffs

	dey
	bpl	not0

	lda	#<wrapbuf
	sta	stline
	lda	#>wrapbuf
	sta	stline+1
	rts
not0
	lda	#<vm
	sta	stline
	lda	#>vm
	sta	stline+1
	clc
yloop
	lda	stline
	;clc
	adc	#40
	sta	stline
	bcc	noc1

	inc	stline+1
	clc
noc1
	dey
	bpl	yloop
ydone
	rts
	.)

io_sputc
	; input a = char

	.(
	ldy	stxoffs
	sta	(stline),y
	inc	stxoffs
	rts
	.)

io_sprogress
	; input x = progress
	; input y = total
	; where 0 <= x <= y
	; and y =
	; (width << PRSHIFT) - PREXTRA

	.(

	tya
	lsr
	lsr
	sta	mod_end+1
	txa
	lsr
	lsr
	sta	f_temp
	txa
	and	#3
	clc
	adc	#CH_PROG0
	sta	f_temp2

	ldy	stxoffs
	lda	#CH_PROGB
	sta	(stline),y
	iny
	ldx	#0
loop
	lda	#CH_PROG0
	cpx	f_temp
	bcs	notpast

	lda	#CH_PROG4
notpast
	bne	notat

	lda	f_temp2
notat
	sta	(stline),y
past
	iny
	inx
mod_end
	cpx	#0
	bcc	loop

	lda	#CH_PROGE
	sta	(stline),y
	rts
	.)

io_scommit
	.(
	inc	1
	ldy	#39
loop
	lda	wrapbuf,y
	sta	vm,y
	lda	#$f
	sta	$d800,y
	dey
	bpl	loop

	dec	1
	rts
	.)

; Input

io_getc
	; output a = char

	jsr	io_mflush
io_getc_raw
	jsr	pre_input
io_getc_raw2
	.(
	lda	ypos
	sta	cursy
	jsr	updatecursor
	lda	keywpos
	sta	keyrpos
again
	jsr	getkey
	bmi	again

	pha
	lda	#$ff
	sta	cursy
	jsr	updatecursor
	lda	#0
	sta	nunread
	pla

	rts
	.)

io_gets
	; input ioparam = buffer
	; (room for 64 chars)
	; output y = length

	.(
	jsr	io_mflush
	jsr	pre_input
	ldy	#0
	lda	#64
	ldx	#$80
#if MEASURE_TIME
	inc	1
	sta	$de00
	dec	1
#endif
	jsr	getinputline
	jsr	io_mline_raw
	lda	#0
	sta	nunread
#if MEASURE_TIME
	inc	1
	sta	$de00
	lda	#1
	sta	measure
	dec	1
#endif
	ldy	inplen
	rts
	.)

getinputline
	; input ioparam = buffer
	; input a = buffer size
	; input y = initial length
	; input x = term. char limit
	; output inplen = length
	; output a = terminating char

	.(
	sta	inpmax
	sty	inplen
	sty	inppos
	stx	inpterm
	lda	#0
	sta	nunread
redraw
	.(
	ldy	ypos
	cpy	#23
	bcc	noadj

	lda	inppos
	cmp	inplen
	lda	xpos
	adc	inplen

	cpy	#24
	bne	no24

	cmp	#41
	bcc	noadj

	pha
	jsr	scrollvm
	dec	ypos
	jsr	set_ioline
	pla
no24
	cmp	#81
	bcc	noadj

	jsr	scrollvm
	dec	ypos
	jsr	set_ioline
noadj
	inc	1

	lda	ioline
	sta	mod_draw+1
	sta	mod_draw2+1
	lda	ioline+1
	sta	mod_draw+2
	eor	#>(vm^$d800)
	sta	mod_draw2+2

	ldy	#0
	ldx	xpos
	cpy	inplen
	beq	drawdone
drawloop
	lda	(ioparam),y
mod_draw
	sta	!0,x
	lda	currfg
mod_draw2
	sta	!0,x
	inx
	iny
	cpy	inplen
	bcc	drawloop
drawdone
	dec	1

	txa
	tay
	lda	#$20
	sta	(ioline),y
	.)

reposition
	.(
	ldy	ypos
	lda	xpos
	clc
	adc	inppos
loop
	cmp	#40
	bcc	nowrap

	sbc	#40
	iny
	jmp	loop
nowrap
	sta	xoutpos
	sty	cursy
	jsr	updatecursor
	.)

	.(
keyloop
	jsr	getkey
	bmi	terminate

	cmp	#$20
	bcc	special

	ldy	inplen
	cpy	inpmax
	bcs	keyloop

	pha
insloop
	cpy	inppos
	beq	noins

	dey
	lda	(ioparam),y
	iny
	sta	(ioparam),y
	dey
	jmp	insloop
noins
	pla
	sta	(ioparam),y
	inc	inppos
	inc	inplen
	jmp	redraw
special
	cmp	#KEY_RET
	bne	noret
terminate
	cmp	inpterm
	bcs	keyloop

	pha

	ldx	#$ff
	stx	cursy
	jsr	updatecursor

	lda	xpos
	clc
	adc	inplen
lineloop
	cmp	#40
	bcc	linedone

	sbc	#40
	inc	ypos
	pha
	lda	ioline
	clc
	adc	#40
	sta	ioline
	sta	iocram
	bcc	noc1

	inc	ioline+1
	inc	iocram+1
noc1
	pla
	jmp	lineloop
linedone
	sta	xpos

	pla
	rts
noret
	cmp	#KEY_DEL
	bne	nodel

	ldy	inppos
	beq	keyloop

	cpy	inplen
	beq	deldone
delloop
	lda	(ioparam),y
	dey
	sta	(ioparam),y
	iny
	iny
	cpy	inplen
	bcc	delloop
deldone
	dec	inppos
	dec	inplen
	jmp	redraw
nodel
	cmp	#KEY_LFT
	bne	noleft

	ldx	inppos
	beq	keyloop0

	dec	inppos
reposition0
	jmp	reposition
noleft
	cmp	#KEY_RGT
	bne	noright

	ldx	inppos
	cpx	inplen
	bcs	specdone

	inx
	stx	inppos
	cpx	inplen
	bcc	reposition0

	jmp	redraw
noright
specdone
keyloop0
	jmp	keyloop
	.)
	.)

pre_input
	.(
	lda	motoron
	bpl	nomotor

	inc	1
	jsr	load_motoroff
	dec	1
nomotor
	rts
	.)

updatecursor
	.(
	inc	1
	lda	cursy
	bmi	nocurs

	asl
	asl
	asl
	;clc
	adc	#$32
	sta	$d001
	lda	xoutpos
	;clc
	adc	#3
	asl
	asl
	asl
	sta	$d000
	lda	#0
	adc	#0
	sta	$d010

	lda	#$fe
nocurs
	eor	#$ff
	sta	$d015
	dec	1
	rts
	.)

getkey
	.(
again
	ldx	keyrpos
wait
	cpx	keywpos
	beq	wait

	ldy	keyq,x
	inx
	txa
	and	#KEYQLEN-1
	sta	keyrpos

	lda	keymap,y
	beq	again

	rts

keymap

	.byt	KEY_DEL
	.byt	KEY_RET
	.byt	KEY_RGT
	.byt	KEY_F7
	.byt	KEY_F1
	.byt	KEY_F3
	.byt	KEY_F5
	.byt	KEY_DWN

	.byt	'3'
	.byt	'w'
	.byt	'a'
	.byt	'4'
	.byt	'z'
	.byt	's'
	.byt	'e'
	.byt	0

	.byt	'5'
	.byt	'r'
	.byt	'd'
	.byt	'6'
	.byt	'c'
	.byt	'f'
	.byt	't'
	.byt	'x'

	.byt	'7'
	.byt	'y'
	.byt	'g'
	.byt	'8'
	.byt	'b'
	.byt	'h'
	.byt	'u'
	.byt	'v'

	.byt	'9'
	.byt	'i'
	.byt	'j'
	.byt	'0'
	.byt	'm'
	.byt	'k'
	.byt	'o'
	.byt	'n'

	.byt	'+'
	.byt	'p'
	.byt	'l'
	.byt	'-'
	.byt	'.'
	.byt	$3a	; colon
	.byt	'@'
	.byt	','

	.byt	KEY_PND
	.byt	'*'
	.byt	';'
	.byt	KEY_HOM
	.byt	0
	.byt	'='
	.byt	$5e	; arrow up
	.byt	'/'

	.byt	'1'
	.byt	KEY_ESC	; arrow left
	.byt	0
	.byt	'2'
	.byt	' '
	.byt	0
	.byt	'q'
	.byt	KEY_STP

	.byt	KEY_INS
	.byt	0
	.byt	KEY_LFT
	.byt	KEY_F8
	.byt	KEY_F2
	.byt	KEY_F4
	.byt	KEY_F6
	.byt	KEY_UP

	.byt	'#'
	.byt	'W'
	.byt	'A'
	.byt	'$'
	.byt	'Z'
	.byt	'S'
	.byt	'E'
	.byt	0

	.byt	'%'
	.byt	'R'
	.byt	'D'
	.byt	'&'
	.byt	'C'
	.byt	'F'
	.byt	'T'
	.byt	'X'

	.byt	$27	; apostrophe
	.byt	'Y'
	.byt	'G'
	.byt	'('
	.byt	'B'
	.byt	'H'
	.byt	'U'
	.byt	'V'

	.byt	')'
	.byt	'I'
	.byt	'J'
	.byt	0
	.byt	'M'
	.byt	'K'
	.byt	'O'
	.byt	'N'

	.byt	0
	.byt	'P'
	.byt	'L'
	.byt	0
	.byt	'>'
	.byt	'['
	.byt	0
	.byt	'<'

	.byt	0
	.byt	0
	.byt	']'
	.byt	KEY_CLR
	.byt	0
	.byt	0
	.byt	0
	.byt	'?'

	.byt	'!'
	.byt	0
	.byt	0
	.byt	$22	; double quote
	.byt	0
	.byt	0
	.byt	'Q'
	.byt	KEY_RUN

	.)

; System

io_quit
	inc	1
	jsr	load_uninstall
	jmp	*

io_random
	; output x = lsb, y = msb
	; range is 0..7fff

	.(
	inc	1
	lda	$dc04
	eor	lfsr+1
	tax
	lda	$dc05
	eor	lfsr
	and	#$7f
	tay
	dec	1
	;jmp	run_lfsr
	.)

run_lfsr
	.(
	asl	lfsr
	rol	lfsr+1
	bcc	noc

	lda	lfsr
	eor	#$2d
	sta	lfsr
noc
	rts
	.)

io_undosupp
	; output c = undo supported

	lda	reutop
	cmp	#1
	rts

io_save
	; input x = size lsb
	; input y = size msb
	; data at SAVEADDR
	; output c = success

	.(
	stx	k_size
	sty	k_size+1

	jsr	k_enable
	jsr	askfilename
	bcc	cancel

	jsr	k_begin
	jsr	k_dev_present
	beq	present

	jsr	k_status_err_dnp
	jmp	err
present
	jsr	k_initialize

	jsr	k_setfnbuf
	lda	#0
	ldx	currdev
	tay
	jsr	$ffba

	lda	#<SAVEADDR
	clc
	adc	k_size
	tax
	lda	#>SAVEADDR
	adc	k_size+1
	tay
	lda	#<SAVEADDR+2
	sta	k_ptr
	lda	#>SAVEADDR+2
	sta	k_ptr+1
	lda	#k_ptr
	jsr	$ffd8
	ror
	eor	#$80
	sta	k_size+1
	jsr	k_status_raw

	lda	wrapbuf
	ora	wrapbuf+1
	cmp	#$30
	beq	noerr
err
	lda	#0
	sta	k_size+1
noerr
	jsr	io_mline
cancel
	jsr	k_disable
	asl	k_size+1
	rts
	.)

k_enable
	.(
	inc	1	; io
	jsr	load_uninstall
	lda	#$03
	sta	$dd00
	lda	#$3f
	sta	$dd02
	dec	1
	jsr	k_begin
	jsr	k_close15
	;jmp	k_end
	.)

k_end
	.(
	lda	#$7f
	sta	$dc0d
	dec	1
	jsr	swapzp
	lda	#1
	sta	$d019
	sta	$d01a
	dec	1
	rts
	.)

k_begin
	.(
	inc	1	; io
	lda	#0
	sta	$d01a
	lda	#$f
	sta	$d021
	jsr	swapzp
	inc	1	; kernal
	lda	$dc0d
	lda	#$81
	sta	$dc0d
	rts
	.)

k_disable
	.(
	lda	reutop
	cmp	#$3
	bcc	noreu

	inc	1
	lda	#$3c
	sta	$dd02
	lda	#0
	sta	$dd00
	dec	1
	rts
noreu
	lda	currdev
	pha
	lda	load_gamedev
	sta	currdev
again
	jsr	k_begin

	jsr	k_initialize

	ldx	#<cmd1
	ldy	#>cmd1
	lda	#cmd1sz
	jsr	k_openclose15

	ldx	#<cmd2
	ldy	#>cmd2
	lda	#cmd2sz
	jsr	k_open15

	ldx	#15
	jsr	$ffc6
	ldy	#0
loop
	sty	k_wpos
	jsr	$ffcf
	ldy	k_wpos
	sta	wrapbuf,y
	iny
	cpy	#4
	bcc	loop

	lda	#15
	jsr	k_closeclr
	jsr	k_end

	ldy	#1+12
check
	lda	(hdbase),y
	cmp	wrapbuf-1-12,y
	bne	wrongdisk

	iny
	cpy	#1+12+4
	bne	check

	pla
	sta	currdev

	jsr	k_begin
	jsr	load_install
	lda	#$3c
	sta	$dd02
	lda	#0
	sta	$dd00
	jsr	k_end
	inc	1
	bit	$dd00
	bmi	*-3
	dec	1
	rts
wrongdisk
	ldy	#iotxt_wrongdisk
	jsr	ioputs
	jsr	io_mflush
wait
	jsr	io_getc_raw2
	cmp	#$0d
	bne	wait

	jmp	again
cmd1
	.byt	"M-E"
	.word	$205

	; load into buffer 1 at $400
	lda	#18
	sta	$8
	lda	#5
	sta	$9
	lda	#1
	sta	$f9
	jmp	$d586
cmd1sz	= * - cmd1

cmd2
	.byt	"M-R"
	.word	$400+12+8+12
	.byt	4
cmd2sz	= * - cmd2
	.)

swapzp
	.(
	ldx	#0
loop
	ldy	savezp,x
	lda	$80,x
	sta	savezp,x
	sty	$80,x
	inx
	bpl	loop

	rts
	.)

k_dev_present
	; output z = device present

	.(
	lda	#0
	sta	$90
	lda	currdev
	jsr	$ffb1	; listen
	lda	#$6f
	jsr	$ff93	; seclsn/second
	jsr	$ffae	; unlsn
	lda	$90
	rts
	.)

k_initialize
	.(
	ldx	#<cmd
	ldy	#>cmd
	lda	#2
	jmp	k_openclose15
cmd
	.byt	"I0"
	.)

k_status_err_dnp
	lda	#5 ; device not present
	bpl	k_status_err ; always

k_command
	.(
	jsr	k_begin

	jsr	k_dev_present
	bne	k_status_err_dnp

	lda	k_wpos
	beq	k_status_raw

	ldx	#0
	stx	k_wpos
	ldx	#<wrapbuf
	ldy	#>wrapbuf
	jsr	k_open15
	bcs	k_status_err

	jsr	k_close15
	;jmp	k_status_raw
	.)

k_status_raw
	.(
	lda	#0
	sta	k_wpos
	jsr	k_open15
	bcc	noerr
+k_status_err
	pha
	jsr	$ffe7 ; clall
	pla
	jsr	grab_rom_error
	jmp	done
noerr
	ldx	#15
	jsr	$ffc6
loop
	jsr	$ffb7
	bne	eof

	jsr	$ffcf
	cmp	#$0d
	beq	loop

	ldy	k_wpos
	sta	wrapbuf,y
	iny
	sty	k_wpos
	jmp	loop
eof
	lda	#15
	jsr	k_closeclr
done
	jsr	k_end
	lda	k_wpos
	sta	wrappos
	clc
	rts
	.)

k_close2clr
	lda	#2
k_closeclr
	jsr	$ffc3
	jmp	$ffcc

k_openclose15
	jsr	k_open15
k_close15
	lda	#15
	jmp	$ffc3

k_setfnbuf
	ldx	#<fnbuf
	ldy	#>fnbuf
	lda	fnlen
	jmp	$ffbd

k_opendir
	.(
	jsr	k_begin
	jsr	k_dev_present
	bne	k_status_err_dnp

	jsr	k_initialize
	ldx	#<dollar
	ldy	#>dollar
	lda	#1
	jsr	$ffbd
	lda	#2
	ldx	currdev
	ldy	#0
	jsr	k_setlfsopen
	bcs	k_status_err

	ldx	#2
	jsr	$ffc6
	jsr	k_end
	sec
	rts
dollar
	.byt	$24
	.)

k_readdir
	.(
	sta	k_wpos
	jsr	k_begin
skiploop
	jsr	getbyte
	dec	k_wpos
	bne	skiploop

	jsr	getbyte
	sta	ioparam
	jsr	getbyte
	sta	ioparam+1
	jsr	k_end
	jsr	convertnumber
	ldy	#0
numloop
	lda	(ioparam),y
	beq	numdone

	sta	wrapbuf,y
	iny
	jmp	numloop
numdone
	sty	k_wpos
	lda	#$20
	jsr	putbyte
	jsr	k_begin
readloop
	jsr	getbyte
	cmp	#0
	beq	done

	cmp	#$12 ; reverse on
	beq	readloop

	jsr	putbyte
	jmp	readloop
eof
	pla
	pla
	clc
done
	php
	jsr	k_end
	lda	k_wpos
	sta	wrappos
	plp
	rts
getbyte
	jsr	$ffb7
	bne	eof

	jmp	$ffcf
putbyte
	ldy	k_wpos
	sta	wrapbuf,y
	inc	k_wpos
	rts
	.)

k_open15
	.(
	jsr	$ffbd
	ldx	currdev
	lda	#15
	tay
	;jmp	k_setlfsopen
	.)

k_setlfsopen
	.(
	jsr	$ffba
	jmp	$ffc0
	.)

grab_rom_error
	; input a = error code

	.(
	asl
	tax
	inc	1	; basic
	lda	$a328-2,x
	sta	k_ptr
	lda	$a329-2,x
	sta	k_ptr+1
	ldy	#0
loop
	lda	(k_ptr),y
	pha
	and	#$7f
	sta	wrapbuf,y
	iny
	pla
	bpl	loop

	sty	k_wpos
	dec	1
	rts
	.)

askfilename
	.(
	ldy	#iotxt_enterfname
	jsr	ioputs
reprompt
	lda	#0
	sta	xpos
	sta	xoutpos
	sta	wrappos
	sta	pendspc
	ldy	#iotxt_prompt
	jsr	ioputs
	lda	currdev
	cmp	#10
	bcc	no10

	lda	#$31
	jsr	io_mputc
	lda	currdev
	sec
	sbc	#10
no10
	ora	#$30
	jsr	io_mputc

	ldy	#iotxt_prompt2
	jsr	ioputs
	jsr	io_mflush

	lda	#<fnbuf
	sta	ioparam
	lda	#>fnbuf
	sta	ioparam+1
	ldy	fnlen
	lda	#FNAMESZ
	ldx	#$ff
	jsr	getinputline
	pha
	jsr	upperline
	ldy	inplen
	sty	fnlen
	pla

	cmp	#$0d
	bne	noret

	jsr	io_mline_raw
	lda	#0
	sta	nunread
	lda	inplen
	cmp	#1
	rts
noret
	cmp	#KEY_F1
	bne	nof1

	ldx	currdev
	cpx	#15
	bcs	reprompt

	inc	currdev
	jmp	reprompt
nof1
	cmp	#KEY_F2
	bne	nof2

	ldx	currdev
	cpx	#9
	bcc	reprompt

	dec	currdev
	jmp	reprompt
nof2
	cmp	#KEY_F3
	bne	nof3

	jsr	io_mline_raw
	jsr	k_opendir
	bcc	direrr

	lda	#4
dirloop
	jsr	k_readdir
	bcc	dirdone

	jsr	io_mline
	lda	#2
	jmp	dirloop
dirdone
	jsr	k_begin
	jsr	k_close2clr
	jsr	k_status_raw
direrr
	jsr	io_mline
	jmp	reprompt
nof3
	cmp	#KEY_F7
	bne	nof7

	.(
	jsr	io_mline_raw
	lda	#'@'
	jsr	io_mputc
	jsr	io_mflush
	lda	#<wrapbuf
	sta	ioparam
	lda	#>wrapbuf
	sta	ioparam+1
	ldy	#0
	lda	#40
	ldx	#$80
	jsr	getinputline
	jsr	upperline
	ldy	inplen
	sty	k_wpos
	jsr	io_mline_raw
	jsr	k_command
	jsr	io_mline
	jmp	reprompt
	.)
nof7
	cmp	#KEY_STP
	bne	nostp

	jsr	io_mline_raw
	clc
	rts
nostp
	jmp	reprompt
	.)

io_load
	; verify AASV header, 12 bytes
	; if ok, put file at SAVEADDR
	; and set c
	; otherwise, clear c

	.(
	lda	#0
	sta	k_size+1
	jsr	k_enable
	jsr	askfilename
	bcs	nocancel

	jmp	done
nocancel
	jsr	k_begin
	jsr	k_dev_present
	beq	present

	jsr	k_status_err_dnp
	jmp	err
present
	jsr	k_initialize
	jsr	k_setfnbuf
	lda	#2
	ldx	currdev
	tay
	jsr	k_setlfsopen
	bcs	openerr

	ldx	#2
	jsr	$ffc6
	ldy	#0
readloop
	sty	k_wpos
	jsr	$ffb7
	bne	readerr

	jsr	$ffcf
	ldy	k_wpos
	sta	wrapbuf,y
	iny
	cpy	#12
	bcc	readloop

	jsr	k_close2clr
	jsr	k_end

	ldy	#11
chkloop
	cpy	#6
	beq	chkskip

	cpy	#7
	beq	chkskip

	lda	wrapbuf,y
	cmp	form0000aasv,y
	bne	badfile
chkskip
	dey
	bpl	chkloop

	jsr	k_begin
	lda	#1
	ldx	currdev
	tay
	jsr	$ffba

	lda	#0
	jsr	$ffd5
	bcs	loaderr

	jsr	k_end
	inc	k_size+1
	jmp	done
badfile
	ldy	#iotxt_badfile
	jsr	ioputs
	jmp	err
readerr
	jsr	k_close2clr
loaderr
	jsr	k_status_raw
	jmp	err
openerr
	jsr	k_status_err
err
	jsr	io_mline
done
	jsr	k_disable
	lsr	k_size+1
	bcs	clearundo

	rts
	.)

io_restart
clearundo
	; preserves c

	.(
	lda	undopos
	sta	undoend
	lda	undopos+1
	sta	undoend+1
	lda	#0
	sta	anyundo
	rts
	.)

io_saveundo
	; input x = byte size lsb
	; input y = byte size msb
	; input ioparam = start of data
	; output c = success

	.(
	lda	reutop
	cmp	#1
	bcs	ok

	rts
ok
	inc	1
	sta	$df06
	stx	$df07
	sty	$df08
	lda	ioparam
	sta	$df02
	lda	ioparam+1
	sta	$df03

	ldx	undopos
	ldy	undopos+1
	jsr	nextundoslot
	stx	undopos
	sty	undopos+1
	stx	$df04
	sty	$df05

	lda	anyundo
	bne	notfirst

	inc	anyundo
	bne	wasfirst ; always
notfirst
	cpx	undoend
	bne	notrim

	cpy	undoend+1
	bne	notrim

	jsr	nextundoslot
wasfirst
	stx	undoend
	sty	undoend+1
notrim
	lda	#$a0
	jsr	startreu
	sec
	rts
	.)

nextundoslot
	.(
	txa
	sec
	sbc	$df07
	tax
	tya
	sbc	$df08
	bcs	nowrap

	lda	#0
	sec
	sbc	$df07
	tax
	lda	#0
	sbc	$df08
	clc
nowrap
	tay
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
	lda	reutop
	beq	err

	lda	anyundo
	beq	empty

	inc	1
	lda	reutop
	sta	$df06
	stx	$df07
	sty	$df08
	lda	ioparam
	sta	$df02
	lda	ioparam+1
	sta	$df03

	ldx	undopos
	cpx	undoend
	bne	notlast

	ldy	undopos+1
	cpy	undoend+1
	bne	notlast

	dec	anyundo
notlast
	lda	undopos
	sta	$df04
	clc
	adc	$df07
	sta	undopos
	tax
	lda	undopos+1
	sta	$df05
	adc	$df08
	sta	undopos+1
	tay
	bcc	nowrap

	ldx	#0
	ldy	#0
	jsr	nextundoslot
wraploop
	stx	undopos
	sty	undopos+1
	jsr	nextundoslot
	bcs	wraploop
nowrap
	lda	#$a1
	jsr	startreu
	lda	#0
	rts
err
	lda	#2
	rts
empty
	lda	#1
	rts
	.)

startreu
	.(
	sta	$df01
	lda	statush
	beq	now

	asl
	asl
	asl
	;clc
	adc	#$33
wait
	cmp	$d012
	bcs	wait

	bit	$d011
	bmi	wait
now
	dec	1
	sta	$ff00
	rts
	.)

io_readpage

	; input x = physical ram target page
	; input ioparam = virtual address 23..8, l-e
	; output a = physical ram target page

	.(
	txa
again
	pha
	inc	1
	ldx	#$ff
	stx	motoron
	ldx	ioparam
	ldy	ioparam+1
	jsr	load_read
	dec	1
	bcc	err

	pla
	rts
err
	jsr	io_mline
	ldy	#iotxt_wrongdisk
	jsr	ioputs
wait
	jsr	io_getc
	cmp	#$0d
	bne	wait

	pla
	jmp	again
	.)

ioputs
	; input y = offset in iotxtbase

	.(
loop
	sty	f_temp2
	lda	iotxtbase,y
	beq	done

	cmp	#10
	bne	nonl

	jsr	io_mline
	jmp	wasnl
nonl
	jsr	io_mputc
wasnl
	ldy	f_temp2
	iny
	jmp	loop
done
	rts
	.)

iotxtbase
iotxt_enterfname = *-iotxtbase
	.asc	"Insert savedisk and enter a filename.",10
	.asc	"[STOP=cancel,F1/F2=device,F3=dir,F7=cmd]",10
	.asc	0
iotxt_prompt = *-iotxtbase
	.asc	"Device ",0
iotxt_prompt2 = *-iotxtbase
	.asc	", filename",$3a," ",0
iotxt_wrongdisk = *-iotxtbase
	.asc	"Insert storydisk and press RETURN.",10,0
iotxt_badfile = *-iotxtbase
	.asc	"Not a valid savefile.",0

upperline
	.(
	ldy	#0
	beq	start
loop
	lda	(ioparam),y
	cmp	#'a'
	bcc	no

	cmp	#'z'+1
	bcs	no

	eor	#$20
	sta	(ioparam),y
no
	iny
start
	cpy	inplen
	bcc	loop

	rts
	.)

irq
	.(
	pha
	lda	1
	pha
	lda	#$35
	sta	1
	;dec	$d020
	txa
	pha
	tya
	pha

	jsr	scankeyboard

	lda	statush
	beq	nost

	asl
	asl
	asl
	;clc
	adc	#$32
	sta	$d012
	lda	#<irq2
	sta	$fffe
	lda	#>irq2
	sta	$ffff

	lda	#$b
	sta	$d021
nost
	pla
	tay
	pla
	tax
	;inc	$d020
	lsr	$d019
	pla
	sta	1
	pla
	.)

nmi
	rti

irq2
	.(
	;dec	$d020
	pha
	lda	1
	pha
	lda	#$35
	sta	1

	lda	#$ff
	sta	$d012
	lda	#<irq
	sta	$fffe
	lda	#>irq
	sta	$ffff

	nop
	nop
	nop
	nop
	nop

	lda	#$f
	sta	$d021

	lsr	$d019
	pla
	sta	1
	pla
	;inc	$d020
	rti
	.)

scankeyboard
	.(
	.(
	dec	reptimr
	bne	norep

	lda	repkey
	bmi	norep

	ora	keymod
	ldx	keywpos
	sta	keyq,x
	inx
	txa
	and	#KEYQLEN-1
	sta	keywpos

	lda	#REPEATRATE
	sta	reptimr
norep
	.)

	.(
	lda	#$00
	sta	$dc00
again
	lda	$dc01
	cmp	$dc01
	bne	again

	cmp	#$ff
	bne	somepressed

	sta	repkey
	ldx	#7
loop
	sta	lastmatrix,x
	dex
	bpl	loop

	rts
somepressed
	.)

	.(
	ldx	#7
	lda	#$7f
next
	sta	$dc00
	pha
again
	lda	$dc01
	cmp	$dc01
	bne	again

	sta	kmatrix,x
	;sec
	pla
	ror
	dex
	bpl	next
	.)

	.(
	ldx	#0
	lda	kmatrix+1
	bmi	nolshift

	ldx	#$40
	ora	#$80
	sta	kmatrix+1
nolshift
	lda	kmatrix+6
	bit	mul8+2	; $10
	bne	norshift

	ldx	#$40
	ora	#$10
	sta	kmatrix+6
norshift
	lda	kmatrix+7
	ora	#$24
	sta	kmatrix+7

	stx	keymod
	.)

	.(
	lda	repkey
	bmi	nounrep

	ldx	reprow
	and	#7
	tay
	lda	pow2,y
	and	kmatrix,x
	beq	nounrep

	lda	#$ff
	sta	repkey
nounrep
	.)

	.(
	ldx	#7
rowloop
	lda	kmatrix,x
	eor	#$ff
	and	lastmatrix,x
	beq	nextrow

	ldy	#7
keyloop
	asl
	bcc	nextbit

	pha

	stx	reprow
	tya
	ora	mul8,x

	ldx	keywpos
	cmp	#1	; return
	beq	norep

	sta	repkey
norep
	ora	keymod
	sta	keyq,x

	lda	#REPEATDELAY
	sta	reptimr

	inx
	txa
	and	#KEYQLEN-1
	sta	keywpos
	ldx	reprow

	pla
nextbit
	dey
	bpl	keyloop
nextrow
	lda	kmatrix,x
	sta	lastmatrix,x
	dex
	bpl	rowloop
	.)

	rts
pow2
	.byt	$01,$02,$04,$08
	.byt	$10,$20,$40,$80
mul8
	.byt	0,8,16,24,32,40,48,56
	.)

savezp
	.dsb	128,0
lastmatrix
	.dsb	8,$ff

c64_footprint = *-c64_entry

#include "engine.s"

	; Anything past this point gets
	; overwritten by initengine5

c64init
	.(
	.(
	ldx	#0
loop
	lda	$80,x
	sta	savezp,x
	inx
	bpl	loop
	.)

	.(
	ldx	#$3f-2
	lda	#0
loop
	sta	2,x
	dex
	bpl	loop
	.)

	.(
	lda	#$20
	sta	vm+$3f8
	.)

	.(
	lda	load_gamedev
	sta	currdev
	.)

	.(
	ldy	#4
	inx
	;ldx	#0
loop
	lda	fontsrc,x
	sta	$800,x
	inx
	bne	loop

	inc	loop+2
	inc	loop+5
	dey
	bne	loop
	.)

	inc	lfsr
	dec	repkey
	dec	cursy

	lda	#$1b
	sta	$d011
	lda	#$12
	sta	$d018

	lda	#$f
	sta	$d020
	sta	$d021

	lda	#$8
	sta	$d027
	lda	#$00
	sta	$d015
	sta	$d017
	sta	$d01d
	sta	$d01c
	lda	#$01
	sta	$d01b

	lda	#<irq
	sta	$fffe
	lda	#>irq
	sta	$ffff
	lda	#$ff
	sta	$d012

	;lda	#$ff
	sta	$dc02

	lda	#$34
	sta	1

	lda	#<nmi
	sta	$fffa
	lda	#>nmi
	sta	$fffb

	jsr	initengine0

	jsr	io_clearall
	ldx	#<itxt_banner
	ldy	#>itxt_banner
	jsr	initprogress

	.(
	inc	1

	lda	#$7f
	sta	$dc00
again
	lda	$dc01
	cmp	$dc01
	bne	again

	and	#$20
	bne	noskip

	ldx	#<itxt_reuskip
	ldy	#>itxt_reuskip
	jsr	initprogress
	jmp	reudone
poketable
	.byt	$b0
	.byt	<poketable
	.byt	>poketable
	.byt	$f8
	.byt	$ff
	.byt	$ff
	.byt	8
	.byt	0
	.byt	0
	.byt	0
peektable
	.byt	$b1
	.byt	<mod_check
	.byt	>mod_check
	.byt	$f8+5
	.byt	$ff
	.byt	$ff
	.byt	1
	.byt	0
noskip
	ldx	#$ff
fill
	stx	poketable+5
	ldy	#9
wrloop1
	lda	poketable,y
	sta	$df01,y
	dey
	bpl	wrloop1

	dex
	cpx	#$ff
	bne	fill

	ldx	#1
check
	stx	peektable+5
	ldy	#7
wrloop2
	lda	peektable,y
	sta	$df01,y
	dey
	bpl	wrloop2

mod_check = * + 1
	cpx	#$ff
	bne	checkdone

	inx
	bne	check
checkdone
	dex
	bne	gotreu

	ldx	#<itxt_noreu
	ldy	#>itxt_noreu
	jsr	initprogress
	jmp	reudone
gotreu
	stx	reutop
	txa
	ldx	#8
bitloop
	dex
	asl
	bcc	bitloop

	lda	reusizelsb,x
	ldy	reusizemsb,x
	tax
	jsr	initprogress
	ldx	#<itxt_reufound
	ldy	#>itxt_reufound
	jsr	initprogress

	lda	reutop
	cmp	#$03
	bcs	dofill

	jmp	reudone
dofill
	ldx	#<itxt_reufill
	ldy	#>itxt_reufill
	jsr	initprogress

	ldx	#0
	stx	$df04
	stx	$df07
	stx	$df02
	lda	#1
	sta	$df08
	lda	#$0f
	sta	$df03
	ldy	#0
	stx	iocram2
	sty	iocram2+1
	stx	$df05
	sty	$df06
	jsr	load_read
	lda	#$b0
	sta	$df01

	; iocram2 = current page
	; ioparam = last page of image
	lda	$0f05
	sta	ioparam+1
	lda	$0f06
	sta	ioparam
preload
	ldx	iocram2
	ldy	iocram2+1
	dec	1
	jsr	initprogressbar
	inc	1

	ldx	iocram2
	ldy	iocram2+1
	cpx	ioparam
	bne	notpredone

	cpy	ioparam+1
	beq	predone
notpredone
	inx
	bne	noc1

	iny
noc1
	lda	#$0f
	stx	iocram2
	sty	iocram2+1
	stx	$df05
	sty	$df06
	jsr	load_read
	lda	#$b0
	sta	$df01
	jmp	preload
predone
	dec	1
	jsr	io_mline_raw
	inc	1
	jsr	load_uninstall

	ldy	#reuloadersz-1
reuinstall
	lda	reuloadersrc,y
	sta	reuloaderorg,y
	dey
	bpl	reuinstall
reudone
	.)

	lda	#$01
	sta	$d019
	sta	$d01a
	dec	1

	ldx	#<itxt_ldstory
	ldy	#>itxt_ldstory
	jsr	initprogress
	jsr	initengine1
	jsr	initengine2

	ldx	#<itxt_ldlangdict
	ldy	#>itxt_ldlangdict
	jsr	initprogress
	jsr	initengine3

	ldx	#<itxt_ldlook
	ldy	#>itxt_ldlook
	jsr	initprogress
	jsr	initengine4

	.(
	lda	#$80
loop
	sta	f_temp
	jsr	lookupchar
	bcc	notdone

	jmp	done
notdone
	; reuse variables
	;   stline = start index
	;   stcram = end index
	;   ioline2 = pivot index
	;   iocram2 = entry address

	ldy	#2
	lda	(ioparam),y
	bne	notfound

	lda	#0
	sta	stline
	sta	stline+1
	lda	#<nfontextchar
	sta	stcram
	lda	#>nfontextchar
	sta	stcram+1
search
	lda	stline
	cmp	stcram
	lda	stline+1
	sbc	stcram+1
	bcs	notfound

	lda	stcram
	clc
	adc	stline
	sta	ioline2
	lda	stcram+1
	adc	stline+1
	lsr
	ror	ioline2

	sta	iocram2+1
	lda	ioline2
	asl
	rol	iocram2+1
	asl
	rol	iocram2+1
	;clc
	adc	ioline2
	sta	iocram2
	lda	iocram2+1
	adc	ioline2+1
	asl	iocram2
	rol
	sta	iocram2+1

	lda	#<fontsrc+$400-2
	;clc
	adc	iocram2
	sta	iocram2
	lda	#>fontsrc+$400-2
	adc	iocram2+1
	sta	iocram2+1

	ldy	#4
	lda	(ioparam),y
	dey
	cmp	(iocram2),y
	lda	(ioparam),y
	dey
	sbc	(iocram2),y
	bcc	was_lt

	ldy	#4
	lda	(ioparam),y
	dey
	cmp	(iocram2),y
	bne	was_gt

	lda	(ioparam),y
	dey
	cmp	(iocram2),y
	beq	found
was_gt
	lda	ioline2
	clc
	adc	#1
	sta	stline
	lda	ioline2+1
	adc	#0
	sta	stline+1
	jmp	search
notfound
	lda	#<fontsrc+8*8
	sta	stline
	lda	#>fontsrc+8*8
	sta	stline+1
	jmp	put
was_lt
	lda	ioline2
	sta	stcram
	lda	ioline2+1
	sta	stcram+1
	jmp	search
found
	lda	iocram2
	clc
	adc	#4
	sta	stline
	lda	iocram2+1
	adc	#0
	sta	stline+1
put
	ldy	#7
putloop
	lda	(stline),y
mod_putdest
	sta	$c00,y
	dey
	bpl	putloop

	lda	mod_putdest+1
	clc
	adc	#8
	sta	mod_putdest+1
	bcc	noc1

	inc	mod_putdest+2
	clc
noc1
	lda	f_temp
	adc	#1
	jmp	loop
done
	; use remaining space
	; as page buffers

pageloop
	inc	mod_putdest+2
	lda	mod_putdest+2
	cmp	#$10
	bcs	pagedone

	jsr	initaddpage
	jmp	pageloop
pagedone
	.)

	ldx	#<itxt_ldinit
	ldy	#>itxt_ldinit
	jsr	initprogress
	jmp	initengine5
	.)

initprogress
	.(
	stx	stline
	sty	stline+1
	ldy	#0
loop
	sty	f_temp2
	lda	(stline),y
	beq	done

	cmp	#10
	bne	nonl

	jsr	io_mline
	jmp	wasnl
nonl
	jsr	io_mputc
wasnl
	ldy	f_temp2
	iny
	jmp	loop
done
	rts
	.)

reuloadersrc
	* = $1000
reuloaderorg
	.(
	jmp	dummy
	jmp	dummy
	jmp	dummy

	; x = linear sector lsb
	; y = linear sector msb
	; a = dest address msb
	; output c = success

	sta	$df03
	stx	$df05
	sty	$df06
	ldx	#0
	stx	$df02
	stx	$df04
	stx	$df07
	inx
	stx	$df08
	lda	#$a1
	sta	$df01

	lda	statush
	beq	now

	asl
	asl
	asl
	;clc
	adc	#$33
wait
	cmp	$d012
	bcs	wait
now
	dec	1
	sta	$ff00
	inc	1
	sec
dummy
	rts
	.)
reuloadersz = *-reuloaderorg
	* = reuloadersrc+reuloadersz

reusizelsb
	.byt	<itxt_128k
	.byt	<itxt_256k
	.byt	<itxt_512k
	.byt	<itxt_1m
	.byt	<itxt_2m
	.byt	<itxt_4m
	.byt	<itxt_8m
	.byt	<itxt_16m
reusizemsb
	.byt	>itxt_128k
	.byt	>itxt_256k
	.byt	>itxt_512k
	.byt	>itxt_1m
	.byt	>itxt_2m
	.byt	>itxt_4m
	.byt	>itxt_8m
	.byt	>itxt_16m

itxt_banner
	.asc    CH_ARING,"-machine C64 interpreter v"
	.asc	VERSION
	.asc	10,"by Linus ",CH_ARING,"kesson",10,0
itxt_ldstory
	.asc	"Preparing story...",10,0
itxt_ldlangdict
	.asc	"  Language and dictionary",10,0
itxt_ldlook
	.asc	"  Layout and styling",10,0
itxt_ldinit
	.asc	"  Initial state",10,0

itxt_reuskip
	.asc	"C= key held, skipping REU check.",10,0
itxt_noreu
	.asc	"No REU detected. Undo is disabled.",10,0
itxt_reufound
	.asc	"B REU detected. Undo is enabled.",10,0
itxt_reufill
	.asc	"Loading entire story into REU.",10,10,0

itxt_128k
	.asc	"128 K",0
itxt_256k
	.asc	"256 K",0
itxt_512k
	.asc	"512 K",0
itxt_1m
	.asc	"1 M",0
itxt_2m
	.asc	"2 M",0
itxt_4m
	.asc	"4 M",0
itxt_8m
	.asc	"8 M",0
itxt_16m
	.asc	"16 M",0

fontsrc
	.bin	0,0,"font.bin"
nfontextchar = (*-(fontsrc+$400))/10

SAFEPG = (* + $ff) >> 8
RAMEND = $10000

; reinterpret "FO" as a load address
SAVEADDR = $4f44
