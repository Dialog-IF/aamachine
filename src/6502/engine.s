; Aa-machine engine.
; Copyright 2019-2020 Linus Akesson.

; Generic 6502 code; no undocumented op
; codes are used. Can execute from ROM.

; This file should be included from a
; platform-specific frontend.
; Initialization routines may be placed
; immediately afterwards; they will be
; overwritten by the engine.

; Designed for the xa65 assembler.

#define PAGE .dsb ((*+$ff)&$ff00)-*,0

specreg = $40	; 26 bytes
inst	= $40	; 4 bytes, b-e
cont	= $44	; 4 bytes, b-e
rtop	= $48	; word, b-e
renv	= $4a	; word, b-e
rcho	= $4c	; word, b-e
rsim	= $4e	; word, b-e
raux	= $50	; word, b-e
rtrl	= $52	; word, b-e
rsta	= $54	; word, b-e
rstc	= $56	; word, b-e
rcwl	= $58
rspc	= $59

divsp	= $5a
rstyle	= $5b
rtrace	= $5c
rupper	= $5d
phytmp	= $5e	; word

inbase	= $60	; word
rambase	= $62	; word
auxbase	= $64	; word
hpbase	= $66	; word
lngbase	= $68	; word
decoder = $6a	; word
mapbase	= $6c	; word
freeptr	= $6e	; word

memptr	= $70	; word
memptr2	= $72	; word
workptr	= $74	; word
physize = $76	; word
vtsize	= $78	; word
vtptr	= $7a	; word
vtmsb	= $7c
evict	= $7d
firstpg	= $7e
endpg	= $7f

operlsb	= $80	; 6 bytes
opermsb	= $86	; 6 bytes
result	= $8c	; word, b-e
rpair	= $8e	; word, b-e

dictch	= $90	; word
endbase	= $92	; word
dicttbl	= $94	; word
dictpiv	= $96	; word
dicta	= $98	; word
dictb	= $9a	; word
endpos	= $9c
wordend	= $9d
dictlen	= $9e

stflag	= $a0	; 00/ff/80
screenw	= $a1
undosz	= $a2	; word
stybase	= $a4	; word
stleft	= $a6
stposx	= $a7
stposy	= $a8
stsizey	= $a9
stendx	= $aa
stdivsp	= $ab
stfullw	= $ac
nspan	= $ad

numer	= $b0	; word
denom	= $b2	; word
quot	= $b4	; word
remain	= $b6	; word
hdbase	= $b8	; word
escbits	= $ba
escbnd	= $bb	; ff if old encoding
stoptbl	= $bc	; word
nosbpos	= $be	; index in stoptbl
nosapos	= $bf	; index in stoptbl

codeseg	= $c0	; 3 bytes, b-e, minus 1
envbase	= $c8	; word
heapsz	= $ca	; word, b-e
auxsz	= $cc	; word, b-e
ramsz	= $ce	; word, b-e

zporg	= $d0	; 24 bytes of code

inittmp	= $f3	; word, b-e
temp	= $f5
pcmsb	= $f6
pcbank	= $f7
phydata	= $f8	; word
virdata	= $fa	; 3 bytes, b-e
count	= $fd
savedsp	= $fe
bits	= $ff

initdata = SAFEPG << 8

HEAPEND	= RAMEND-$300

regs	= HEAPEND+$000	; 64 words, b-e
inpbuf	= HEAPEND+$080	; 64 bytes
divstk	= HEAPEND+$0c0	; 8 words, b-e

UNDOEND	= HEAPEND+$0d0

; each of the following is CH_N bytes
chnklsb	= HEAPEND+$0d0+0*CH_N
chnkssb	= HEAPEND+$0d0+1*CH_N
chnkmsb	= HEAPEND+$0d0+2*CH_N

databuf = HEAPEND+$0f0	; 8 bytes
filesz	= HEAPEND+$0f8	; 3 bytes, b-e

; for each physical page, what
; virtual page owns it (initialized
; to one more than the highest
; virtual page number)
phy2lsb = HEAPEND+$100	; 256 bytes
phy2msb = HEAPEND+$200	; 256 bytes

; CPU vectors at $fffa are safe
; because the heap ends more than
; six pages from the end.
; Likewise, there are six free
; bytes at the end of phy2lsb.

intbuf	= phy2lsb + $fa	; 6 bytes

ridx	= regs+2*$3f

FIELD_PARENT	= 0
FIELD_CHILD	= 1
FIELD_SIBLING	= 2

SPC_AUTO	= 0
SPC_NO		= 1
SPC_PENDING	= 2
SPC_SPACE	= 3
SPC_LINE	= 4
SPC_PAR		= 5

STY_WIDTH	= 0
STY_HEIGHT	= 1
STY_MTOP	= 2
STY_MBOTTOM	= 3
STY_STYON	= 4
STY_STYOFF	= 5
STY_FLAGS	= 6

STYF_RELW	= $01
STYF_RELH	= $02
STYF_FLOATL	= $40
STYF_FLOATR	= $80

engine_firstaddr

swapin
	; input x = virtual 22..16
	; input y = virtual 15..8 
	; output a = physical 15..8
	; clobbers x, y

	.(
	txa
	clc
	adc	vtmsb
	sta	vtptr+1
	lda	(vtptr),y
	beq	fault

	tax
	lda	phy2msb,x
	ora	#$80
	sta	phy2msb,x
	txa
	rts
fault
	stx	ioparam+1
	sty	ioparam

	; round-robin page eviction

	ldx	evict
evagain
	inx
	cpx	endpg
	bne	nowrap

	ldx	firstpg
nowrap
	stx	evict

	; second chance

	lda	phy2msb,x
	bpl	nosecond

	and	#$7f
	sta	phy2msb,x
	bpl	evagain	; always
nosecond
	; protect page of current pc

	cpx	`phypc+1
	beq	evagain

	; x = physical target page

	txa
	sta	(vtptr),y

	; mark previous owner as
	; out-of-core (initially this
	; is a dummy index past the
	; end of the array)

	lda	phy2msb,x
	clc
	adc	vtmsb
	sta	vtptr+1
	ldy	phy2lsb,x
	lda	#0 ; out-of-core
	sta	(vtptr),y

	; install the new owner

	lda	ioparam
	sta	phy2lsb,x
	lda	ioparam+1
	sta	phy2msb,x

	jmp	io_readpage
	.)

readdata
	; input virdata = address, b-e
	; input a = number of bytes
	; to load into databuf
	; clobbers phydata, physize
	; increments virdata by size

	.(
	sta	physize
	lda	#0
	sta	physize+1
	lda	#<databuf
	sta	phydata
	lda	#>databuf
	sta	phydata+1
	;jmp	readdatato
	.)

readdatato
	; input virdata = source, b-e
	; input phydata = dest, l-e
	; input physize = size, l-e
	; clobbers physize, memptr
	; increments virdata by size
	; increments phydata by size

	.(
	lda	#0
	sec
	sbc	physize
	sta	physize
	lda	#0
	sbc	physize+1
	sta	physize+1
bigloop
	ldx	virdata+0
	ldy	virdata+1
	jsr	swapin
	sta	memptr+1
	ldy	virdata+2
	ldx	#0
loop
	lda	(memptr),y
	sta	(phydata,x)

	inc	phydata
	beq	wrap2
postwrap2
	inc	physize
	beq	wrap1
postwrap1
	iny
	bne	loop

	sty	virdata+2
	inc	virdata+1
	bne	bigloop

	inc	virdata+0
	jmp	bigloop
wrap1
	inc	physize+1
	bne	postwrap1

	iny
	sty	virdata+2
	bne	noc1

	inc	virdata+1
	bne	noc1

	inc	virdata+0
noc1
	rts
wrap2
	inc	phydata+1
	jmp	postwrap2
	.)

puts
	; input phydata = string in ram

	.(
	ldy	#0
loop
	sty	temp
	lda	(phydata),y
	beq	done

	jsr	vio_putc
	ldy	temp
	iny
	jmp	loop
done
	rts
	.)

vio_putc
	.(
	cmp	#$20
	beq	noupper

	bit	rupper
	bpl	noupper

	cmp	#'a'
	bcc	clrupper

	tax
	bmi	ext

	cmp	#'z'+1
	bcs	clrupper

	eor	#$20
clrupper
	inc	rupper
noupper
	bit	stflag
	bmi	st

	jmp	io_mputc
st
	bvc	skip

	ldx	stposx
	cpx	stendx
	bcs	skip

	inc	stposx
	jmp	io_sputc
skip
	rts
ext
	jsr	lookupchar
	ldy	#1
	lda	(ioparam),y
	jmp	clrupper
	.)

vio_line
	.(
	lda	rspc
	cmp	#SPC_LINE
	bcs	skip

	bit	stflag
	bmi	st

	jsr	io_mline
	lda	#SPC_LINE
	sta	rspc
skip
	rts
st
	bvc	skip

	ldy	stposy
	cpy	stsizey
	beq	skip

	iny
	sty	stposy
	ldx	stleft
	stx	stposx
	jsr	io_slocate
	lda	#SPC_LINE
	sta	rspc
	rts
	.)

vio_vspace
	.(
	pha
	jsr	vio_line
	pla

	clc
	adc	#SPC_LINE-1

	bit	stflag
	bmi	st
loop
	cmp	rspc
	bcc	done

	pha
	jsr	io_mline
	pla
	inc	rspc
	jmp	loop
done
	rts
st
	bvc	done

	ldy	stposy
stloop
	cmp	rspc
	bcc	stdone
	
	cpy	stsizey
	beq	stskip

	iny
stskip
	inc	rspc
	jmp	stloop
stdone
	sty	stposy
	ldx	stleft
	stx	stposx
	jmp	io_slocate
	.)

vio_getc
	.(
	jsr	io_getc
	;jmp	tolower
	.)

tolower
	.(
	cmp	#'A'
	bcc	noupper

	tax
	bmi	ext

	cmp	#'Z'+1
	bcs	noupper

	eor	#$20
noupper
	rts
ext
	jsr	lookupchar
	ldy	#0
	lda	(ioparam),y
	rts
	.)

vio_gets
	.(
	lda	#<inpbuf
	sta	ioparam
	lda	#>inpbuf
	sta	ioparam+1
	jsr	io_gets
	sty	count
	sty	temp
	dey
	bmi	done
loop
	sty	temp
	lda	inpbuf,y
	jsr	tolower
	ldy	temp
	sta	inpbuf,y
	dey
	bpl	loop
done
	rts
	.)

setwidth
	.(
	sta	screenw
	rts
	.)

unstyle
	.(
	lda	stflag
	bne	skip

	lda	#0
	sta	rstyle

	ldx	#0
loop
	cpx	divsp
	bcs	done

	lda	divstk,x
	sta	temp
	lda	divstk+1,x
	asl
	rol	temp
	asl
	rol	temp
	asl
	rol	temp
	;clc
	adc	stybase
	sta	phydata
	lda	temp
	adc	stybase+1
	sta	phydata+1

	ldy	#STY_STYOFF
	lda	(phydata),y
	eor	#$ff
	and	rstyle
	ldy	#STY_STYON
	ora	(phydata),y
	sta	rstyle

	inx
	inx
	jmp	loop
done
	lda	rstyle
	jmp	io_mstyle
skip
	rts
	.)

initengine5
	; Prefetch some CODE.

	.(
	lda	freeptr+1
	sta	endpg
	.)

	.(
	lda	#>initsegment
	sta	firstpg
	.)

	.(
#if 1
	; prefill 50% of the page cache

	lda	endpg
	sec
	sbc	firstpg
	lsr
	sta	count

	lda	codeseg+0
	sta	virdata+0
	lda	codeseg+1
	sta	virdata+1
loop
	ldx	virdata+0
	ldy	virdata+1
	cpx	filesz+0
	bcc	inrange

	cpy	filesz+1
	bcs	done
inrange
	jsr	swapin

	inc	virdata+1
	bne	noc1

	inc	virdata+0
noc1
	dec	count
	bne	loop
done
#endif
	;jmp	restartgame
	.)

restartgame
	.(
	lda	chnklsb+CH_INIT
	sec
	sbc	#2
	sta	virdata+2
	lda	chnkssb+CH_INIT
	sbc	#0
	sta	virdata+1
	lda	chnkmsb+CH_INIT
	sbc	#0
	sta	virdata+0
	lda	#2
	jsr	readdata

	lda	inbase
	sta	phydata
	lda	inbase+1
	sta	phydata+1
	lda	databuf+1
	sta	physize
	lda	databuf+0
	sta	physize+1
	jsr	readdatato

	ldy	phydata
	lda	#0
	sta	phydata
	ldx	phydata+1
	lda	#$3f
clrmem
	cpy	#<HEAPEND
	bne	noend

	cpx	#>HEAPEND
	beq	clrdone
noend
	sta	(phydata),y
	iny
	sta	(phydata),y
	iny
	bne	clrmem

	inx
	stx	phydata+1
	jmp	clrmem
clrdone

	lda	#0
	sta	regs+0
	sta	regs+1
	sta	rtrace

	;jmp	restartvm
	.)

restartvm
	.(
	lda	#0
	sta	stflag
	sta	rupper
	sta	rstyle
	sta	divsp
	sta	nspan
	ldy	#2
clrreg
	sta	regs,y
	iny
	bpl	clrreg

	ldy	#25
clr2
	sta	specreg,y
	dey
	bpl	clr2

	sty	rsim+0
	sty	rsim+1

	lda	#SPC_LINE
	sta	rspc

	inc	inst+3

	lda	heapsz+0
	sta	renv+0
	sta	rcho+0
	lda	heapsz+1
	sta	renv+1
	sta	rcho+1

	lda	auxsz+0
	sta	rtrl+0
	lda	auxsz+1
	sta	rtrl+1

	rts
	.)

#if 0
show_metadata
	.(
	lda	chnklsb+CH_META
	sta	virdata+2
	lda	chnkssb+CH_META
	sta	virdata+1
	lda	chnkmsb+CH_META
	sta	virdata+0
	lda	#1
	jsr	readdata

	lda	databuf
	sta	count
	beq	done
loop
	lda	#1
	jsr	readdata
	ldx	databuf
	cpx	#7
	bcc	known

	ldx	#0
known
	lda	headerlsb,x
	sta	phydata
	lda	headermsb,x
	sta	phydata+1
	jsr	puts
chloop
	lda	#1
	jsr	readdata
	lda	databuf
	beq	chdone

	cmp	#10
	beq	nl

	jsr	vio_putc
	jmp	chloop
nl
	lda	#1
	jsr	vio_vspace
	jmp	chloop
chdone
	lda	#SPC_AUTO
	sta	rspc
	jsr	vio_line
	dec	count
	bne	loop
done
	rts
headerlsb
	.byt	<head0
	.byt	<head1
	.byt	<head2
	.byt	<head3
	.byt	<head4
	.byt	<head5
	.byt	<head6
headermsb
	.byt	>head0
	.byt	>head1
	.byt	>head2
	.byt	>head3
	.byt	>head4
	.byt	>head5
	.byt	>head6
head0
	.asc	"?: ",0
head1
	.asc	"Title: ",0
head2
	.asc	"Author: ",0
head3
	.asc	"Noun: ",0
head4
	.asc	"Blurb: ",0
head5
	.asc	"Release date: ",0
head6
	.asc	"Compiler: ",0
	.)
#endif

lookupchar
	; input a = char, 80..ff
	; output c = no such char
	; output ioparam =
	;	two reserved bytes
	;	followed by 3-byte
	;	unicode value
	;	(big-endian)
	; clobbers y
	; preserves x

	.(
	and	#$7f
	pha
	ldy	#3
	lda	(lngbase),y
	clc
	adc	lngbase
	sta	ioparam
	dey
	lda	(lngbase),y
	adc	lngbase+1
	sta	ioparam+1
	ldy	#0
	pla
	cmp	(ioparam),y
	bcs	done

	pha
	asl
	asl
	bcc	noc1

	inc	ioparam+1
	clc
noc1
	ora	#1
	;clc
	adc	ioparam
	sta	ioparam
	bcc	noc2

	inc	ioparam+1
	clc
noc2
	pla
	;clc
	adc	ioparam
	sta	ioparam
	bcc	done

	inc	ioparam+1
	clc
done
	rts
	.)

startengine
	tsx
	stx	savedsp
	jmp	fetchinst

jumpvirdata
	lda	virdata+0
	sta	inst+1
	lda	virdata+1
	sta	inst+2
	lda	virdata+2
	sta	inst+3
	bne	fetchinst1

	ora	inst+2
	ora	inst+1
	beq	failure
fetchinst
	lda	inst+3
fetchinst1
	clc
	adc	codeseg+2
	sta	`pclsb
	lda	inst+2
	adc	codeseg+1
	sta	pcmsb
	tay
	lda	inst+1
	adc	codeseg+0
	sta	pcbank
	tax
	jsr	swapin
	sta	`phypc+1
	jmp	ldyfetchnext

refetchnext
	ldy	pcmsb
	ldx	pcbank
	jsr	swapin
	sta	`phypc+1
	jmp	ldyfetchnext

op_fail
ext0_scrpt_on
failure
	.(
	ldx	savedsp
	txs

	lda	rcho+0
	sta	phydata+1
	lda	rcho+1
	asl
	rol	phydata+1
	;clc
	adc	hpbase
	sta	phydata
	lda	phydata+1
	adc	hpbase+1
	sta	phydata+1

	ldy	#9
	lda	(phydata),y
	sta	inst+1
	iny
	lda	(phydata),y
	sta	inst+2
	iny
	lda	(phydata),y
	sta	inst+3
	jmp	fetchinst
	.)

#if TRACE_INST
traceinst
	.(
	tya
	pha
	clc
	sbc	codeseg+2
	tay
	lda	pcmsb
	sbc	codeseg+1
	tax
	lda	pcbank
	sbc	codeseg+0
	sta	$0220
	stx	$0220
	sty	$0220
	sta	$0222
	pla
	tay
	rts
	.)
#endif

fetchbyteor0
	bcc	fetchbyte

fetch0
	.(
	lda	#0
	sta	operlsb,x
	inx
	rts
	.)

fetchwordorvbyte
	bcc	fetchword

fetchvbyte
	lda	#0
	sta	opermsb,x
	; drop through

fetchbyte
	.(
	iny
	beq	wrap
postwrap
	lda	(phypc),y
	sta	operlsb,x
	inx
	rts
wrap
	jsr	pcwrap
	beq	postwrap
	.)

fetchword
	.(
	iny
	beq	wrap1
postwrap1
	lda	(phypc),y
	sta	opermsb,x
	iny
	beq	wrap2
postwrap2
	lda	(phypc),y
	sta	operlsb,x
	inx
	rts
wrap1
	jsr	pcwrap
	beq	postwrap1
wrap2
	jsr	pcwrap
	beq	postwrap2
	.)

fetchfield0
	.(
	bcs	was0

	jsr	fetchvalderef
	jmp	fetchindex
was0
	lda	#0
	sta	operlsb+0
	sta	opermsb+0
	inx
	;jmp	fetchindex
	.)

fetchindex
	.(
	iny
	beq	wrap1
postwrap1
	lda	(phypc),y
	cmp	#$c0
	bcs	large

	sta	operlsb,x
	lda	#0
	sta	opermsb,x
	inx
	rts
large
	and	#$3f
	sta	opermsb,x
	iny
	beq	wrap2
postwrap2
	lda	(phypc),y
	sta	operlsb,x
	inx
	rts
wrap1
	jsr	pcwrap
	beq	postwrap1
wrap2
	jsr	pcwrap
	beq	postwrap2
	.)

fetchvalue
	.(
	iny
	beq	wrap1
postwrap1
	lda	(phypc),y
	bpl	constant

	sty	`pclsb
	asl
	bpl	register

	; env slot
	and	#$7f
	tay
	lda	(envbase),y
	sta	opermsb,x
	iny
	lda	(envbase),y
	sta	operlsb,x
	inx
	ldy	`pclsb
	rts
constant
	sta	opermsb,x
	iny
	beq	wrap2
postwrap2
	lda	(phypc),y
	sta	operlsb,x
	inx
	rts
register
	tay
	lda	regs,y
	sta	opermsb,x
	lda	regs+1,y
	sta	operlsb,x
	inx
	ldy	`pclsb
	rts
wrap1
	jsr	pcwrap
	beq	postwrap1
wrap2
	jsr	pcwrap
	beq	postwrap2
	.)

fetchcode
	; output virdata

	.(
	iny
	beq	wrap1
postwrap1
	lda	(phypc),y
	beq	fail

	bmi	abs

	pha

	tya
	sec
	sbc	codeseg+2
	sta	virdata+2
	lda	pcmsb
	sbc	codeseg+1
	sta	virdata+1
	lda	pcbank
	sbc	codeseg+0
	sta	virdata+0

	pla
	cmp	#$40
	bcc	small

	cmp	#$60
	bcc	forward

	ora	#$e0
	pha
	iny
	beq	wrap5
postwrap5
	lda	(phypc),y
	sec
	adc	virdata+2
	sta	virdata+2
	pla
	adc	virdata+1
	sta	virdata+1
	bcs	noc3

	dec	virdata+0
noc3
	rts
forward
	and	#$1f
	pha
	iny
	beq	wrap4
postwrap4
	lda	(phypc),y
	sec
	adc	virdata+2
	sta	virdata+2
	pla
	adc	virdata+1
	sta	virdata+1
	bcc	noc2

	inc	virdata+0
noc2
	rts
small
	;clc
	adc	virdata+2
	sta	virdata+2
	bcc	noc1

	inc	virdata+1
	bne	noc1

	inc	virdata+0
noc1
	rts
abs
	and	#$7f
	sta	virdata+0
	iny
	beq	wrap2
postwrap2
	lda	(phypc),y
	sta	virdata+1
	iny
	beq	wrap3
postwrap3
	lda	(phypc),y
	sta	virdata+2
	rts
wrap1
	jsr	pcwrap
	beq	postwrap1
fail
	sta	virdata+0
	sta	virdata+1
	sta	virdata+2
	rts
wrap2
	jsr	pcwrap
	beq	postwrap2
wrap3
	jsr	pcwrap
	beq	postwrap3
wrap4
	jsr	pcwrap
	beq	postwrap4
wrap5
	jsr	pcwrap
	beq	postwrap5
	.)

fetchstring
	; output virdata

	.(
	iny
	beq	wrap1
postwrap1
	lda	(phypc),y
	bpl	tiny

	cmp	#$c0
	bcs	long

	and	#$3f
	sta	virdata+1
	lda	#0
	sta	virdata+0
	beq	lastpart
long
	and	#$3f
	sta	virdata+0

	iny
	beq	wrap3
postwrap3
	lda	(phypc),y
	sta	virdata+1
lastpart
	iny
	beq	wrap2
postwrap2
	lda	(phypc),y
	sta	virdata+2
	rts
tiny
	asl
	sta	virdata+2
	lda	#0
	sta	virdata+0
	sta	virdata+1
	rts
wrap1
	jsr	pcwrap
	beq	postwrap1
wrap2
	jsr	pcwrap
	beq	postwrap2
wrap3
	jsr	pcwrap
	beq	postwrap3
	.)

ldystorefetchnext
	ldy	`pclsb
storefetchnext
	.(
	iny
	beq	wrap1
postwrap1
	lda	(phypc),y
	jsr	storehere
	jmp	fetchnext
wrap1
	jsr	pcwrap
	beq	postwrap1
	.)

storehere
	.(
#if TRACE_STORE
	php
	ldx	result+0
	stx	$0220
	ldx	result+1
	stx	$0220
	stx	$0221
	plp
#endif
	bpl	store

	sty	`pclsb
	ldx	result+0
	stx	opermsb+4
	ldx	result+1
	stx	operlsb+4

	asl
	bpl	ureg

	; unify with env slot

	and	#$7f
	tay
	lda	(envbase),y
	sta	opermsb+5
	iny
	lda	(envbase),y
	sta	operlsb+5
	jsr	unify
	ldy	`pclsb
	rts
ureg
	; unify with register

	tax
	lda	regs+0,x
	sta	opermsb+5
	lda	regs+1,x
	sta	operlsb+5
	jsr	unify
	ldy	`pclsb
	rts
store
	asl
	bpl	sreg

	; store to env slot

	sty	`pclsb
	and	#$7f
	tay
	lda	result+0
	sta	(envbase),y
	iny
	lda	result+1
	sta	(envbase),y
	ldy	`pclsb
	rts
sreg
	; store to register

	tax
	lda	result+0
	sta	regs+0,x
	lda	result+1
	sta	regs+1,x
	rts
	.)

pcwrap
	; output y = 0
	; output z is set
	; preserves x

	.(
	stx	temp
	inc	pcmsb
	bne	nobank
	inc	pcbank
nobank
	ldy	pcmsb
	ldx	pcbank
	jsr	swapin
	sta	`phypc+1
	ldx	temp
	ldy	#0
	rts
	.)

alloc_var
	; output result = tagged value

	.(
	lda	rtop+1
	sta	result+1
	lda	rtop+0
	ora	#$80
	sta	result+0

	inc	rtop+1
	bne	noc1

	inc	rtop+0
noc1
	lda	renv+1
	cmp	rtop+1
	lda	renv+0
	sbc	rtop+0
	bcc	heaperr

	lda	rcho+1
	cmp	rtop+1
	lda	rcho+0
	sbc	rtop+0
	bcc	heaperr

	lda	result+0
	sta	phydata+1
	lda	result+1
	asl
	rol	phydata+1
	clc
	adc	hpbase
	sta	phydata+0
	lda	phydata+1
	adc	hpbase+1
	sta	phydata+1
	ldy	#0
	tya
	sta	(phydata),y
	iny
	sta	(phydata),y

	rts
heaperr
	lda	#1
	jmp	error
	.)

push_pair
	; input result = tail
	; output phydata
	; output result
	; output y = 1
	; clobbers rpair

	.(
	jsr	alloc_pair
	ldy	#3
	lda	result+1
	sta	(phydata),y
	lda	result+0
	dey
	sta	(phydata),y
	dey
	lda	rpair+0
	sta	result+0
	lda	rpair+1
	sta	result+1
	rts
	.)

alloc_pair
	; output rpair = tagged value
	; output phydata

	.(
	lda	rtop+0
	sta	temp
	ora	#$c0
	sta	rpair+0
	lda	rtop+1
	sta	rpair+1
	asl
	rol	temp
	;clc
	adc	hpbase
	sta	phydata
	lda	temp
	adc	hpbase+1
	sta	phydata+1

	lda	rtop+1
	clc
	adc	#2
	sta	rtop+1
	bcc	noc4

	inc	rtop+0
noc4
	lda	renv+1
	cmp	rtop+1
	lda	renv+0
	sbc	rtop+0
	bcc	heaperr

	lda	rcho+1
	cmp	rtop+1
	lda	rcho+0
	sbc	rtop+0
	bcc	heaperr

	rts
heaperr
	lda	#1
	jmp	error
	.)

push_aux
	; input oper0
	; clobbers phydata, y

	.(
	lda	raux+1
	cmp	rtrl+1
	lda	raux+0
	sbc	rtrl+0
	bcs	full

	lda	raux+0
	sta	temp
	lda	raux+1
	asl
	rol	temp
	;clc
	adc	auxbase
	sta	phydata
	lda	temp
	adc	auxbase+1
	sta	phydata+1

	ldy	#0
	lda	opermsb+0
	sta	(phydata),y
	lda	operlsb+0
	iny
	sta	(phydata),y

	inc	raux+1
	bne	noc1

	inc	raux+0
noc1
	rts
full
	lda	#2
	jmp	error
	.)

pushchoice
	; input a = number of args
	; input virdata = next pc
	; clobbers x, y, count
	; clobbers phydata, temp
	.(
	sta	count
	clc
	adc	#9

	.(
	sta	temp

	lda	rcho+1
	pha
	lda	rcho+0
	pha

	lda	renv+1
	cmp	rcho+1
	lda	renv+0
	sbc	rcho+0
	bcs	usecho

	lda	renv+1
	sec
	sbc	temp
	sta	rcho+1
	lda	renv+0
	sbc	#0
	sta	rcho+0
	jmp	gotit
overflow
	lda	#1
	jmp	error
usecho
	lda	rcho+1
	sec
	sbc	temp
	sta	rcho+1
	bcs	noc1

	dec	rcho+0
noc1
gotit
	lda	rcho+1
	cmp	rtop+1
	lda	rcho+0
	sbc	rtop+0
	bcc	overflow

	lda	rcho+0
	sta	phydata+1
	lda	rcho+1
	asl
	rol	phydata+1
	;clc
	adc	hpbase
	sta	phydata
	lda	phydata+1
	adc	hpbase+1
	sta	phydata+1
	.)

	ldy	#0
	lda	renv+0
	sta	(phydata),y
	iny
	lda	renv+1
	sta	(phydata),y
	iny
	lda	rsim+0
	sta	(phydata),y
	iny
	lda	rsim+1
	sta	(phydata),y
	iny
	lda	#0
	sta	(phydata),y
	iny
	lda	cont+1
	sta	(phydata),y
	iny
	lda	cont+2
	sta	(phydata),y
	iny
	lda	cont+3
	sta	(phydata),y
	iny
	lda	#0
	sta	(phydata),y
	iny
	lda	virdata+0
	sta	(phydata),y
	iny
	lda	virdata+1
	sta	(phydata),y
	iny
	lda	virdata+2
	sta	(phydata),y
	iny
	pla
	sta	(phydata),y
	iny
	pla
	sta	(phydata),y
	iny
	lda	rtop+0
	sta	(phydata),y
	iny
	lda	rtop+1
	sta	(phydata),y
	iny
	lda	rtrl+0
	sta	(phydata),y
	iny
	lda	rtrl+1
	sta	(phydata),y
	iny
	lda	count
	beq	done

	ldx	#0
loop
	lda	regs,x
	inx
	sta	(phydata),y
	iny
	lda	regs,x
	inx
	sta	(phydata),y
	iny
	dec	count
	bne	loop
done
	rts
	.)

ifyes
	.(
	jsr	fetchcode

	bit	`opcode
	bmi	skip

	jmp	jumpvirdata
skip
	jmp	fetchnext
	.)

ifno
	.(
	jsr	fetchcode

	bit	`opcode
	bpl	skip

	jmp	jumpvirdata
skip
	jmp	fetchnext
	.)

derefoper0y
	ldx	#0+1
	jmp	dereflastoper

derefoper2y
	ldx	#2+1
	jmp	dereflastoper

derefoper4y
	ldx	#4+1
	jmp	dereflastoper

derefoper5y
	ldx	#5+1
	jmp	dereflastoper

fetchvalnum
	.(
	jsr	fetchvalderef
	lda	opermsb-1,x
	bmi	fail

	cmp	#$40
	bcc	fail

	rts
fail
	jmp	failure
	.)

fetchvalderef
	; clobbers phydata

	.(
	jsr	fetchvalue

	lda	opermsb-1,x
	bpl	done0

	sty	`pclsb
	jsr	loop
	ldy	`pclsb
done0
	rts

+dereflastoper
	lda	opermsb-1,x
	bpl	done
loop
	cmp	#$a0
	bcs	done

	and	#$1f
	sta	temp
	lda	operlsb-1,x
	asl
	rol	temp
	;clc
	adc	hpbase
	sta	phydata
	lda	temp
	adc	hpbase+1
	sta	phydata+1

	ldy	#1
	lda	(phydata),y
	bne	notzero

	dey
	cmp	(phydata),y
	beq	unbound

	iny
notzero
	sta	operlsb-1,x
	dey
	lda	(phydata),y
	sta	opermsb-1,x
	bmi	loop
done
	rts
unbound
	lda	opermsb-1,x
	rts
	.)

pushlongterm
	; input oper4 (clobbered)
	; input/output phytmp
	; input physize = end of ram
	; clobbers phydata

	.(
	jsr	derefoper4y

	cmp	#$e0
	bcc	noext

	and	#$1f
	sta	temp
	lda	operlsb+4
	asl
	rol	temp
	;clc
	adc	hpbase
	sta	phydata
	pha
	lda	temp
	adc	hpbase+1
	sta	phydata+1
	pha
	ldy	#2
	lda	(phydata),y
	sta	opermsb+4
	iny
	lda	(phydata),y
	sta	operlsb+4
	jsr	pushlongterm
	pla
	sta	phydata+1
	pla
	sta	phydata
	ldy	#0
	lda	(phydata),y
	sta	opermsb+4
	iny
	lda	(phydata),y
	sta	operlsb+4
	jsr	pushlongterm
	lda	#$81
	bne	simple1
noext
	cmp	#$c0
	bcs	pair

	cmp	#$80
	bcc	simple

	lda	physize
	cmp	hpbase
	lda	physize+1
	sbc	hpbase+1
	bcs	varok

	lda	#4
	jmp	error
varok
	lda	#$80
simple1
	sta	opermsb+4
	lda	#0
	sta	operlsb+4
	; drop through
simple
	lda	phytmp
	cmp	physize
	bne	notfull

	lda	phytmp+1
	cmp	physize+1
	beq	full
notfull
	ldy	#0
	lda	opermsb+4
	sta	(phytmp),y
	iny
	lda	operlsb+4
	sta	(phytmp),y
	lda	phytmp
	clc
	adc	#2
	sta	phytmp
	bcc	noc1

	inc	phytmp+1
noc1
	rts
full
	lda	phytmp
	cmp	hpbase
	lda	phytmp+1
	sbc	hpbase+1
	lda	#2
	bcs	wasaux

	lda	#6
wasaux
	jmp	error
pair
	ldx	#$c0
	ldy	#0
listloop
	iny
	bne	noc2

	inx
noc2
	txa
	pha
	tya
	pha

	ldy	#2

	lda	opermsb+4
	and	#$1f
	sta	temp
	lda	operlsb+4
	asl
	rol	temp
	;clc
	adc	hpbase
	sta	phydata
	pha
	lda	temp
	adc	hpbase+1
	sta	phydata+1
	pha

	ldy	#0
	lda	(phydata),y
	sta	opermsb+4
	iny
	lda	(phydata),y
	sta	operlsb+4
	jsr	pushlongterm

	pla
	sta	phydata+1
	pla
	sta	phydata

	ldy	#3
	lda	(phydata),y
	sta	operlsb+4
	dey
	lda	(phydata),y
	sta	opermsb+4

	jsr	derefoper4y

	cmp	#$3f
	beq	listend

	and	#$e0
	cmp	#$c0
	bne	improper

	pla
	tay
	pla
	tax
	jmp	listloop
improper
	jsr	pushlongterm
	pla
	sta	operlsb+4
	pla
	ora	#$e0
	sta	opermsb+4
	jmp	simple
listend
	pla
	sta	operlsb+4
	pla
	sta	opermsb+4
	jmp	simple
	.)

poplongterm
	; input/output phytmp
	; output result
	; clobbers phydata, rpair

	.(
	lda	phytmp
	sec
	sbc	#2
	sta	phytmp
	bcs	noc1

	dec	phytmp+1
noc1
	ldy	#1
	lda	(phytmp),y
	sta	result+1
	dey
	lda	(phytmp),y
	sta	result+0
	bmi	complex

	rts
complex
	cmp	#$80
	bne	novar

	jmp	alloc_var
novar
	cmp	#$81
	bne	noext

	jsr	alloc_pair
	lda	rpair+0
	pha
	lda	rpair+1
	pha
	lda	phydata
	pha
	lda	phydata+1
	pha

	jsr	poplongterm

	pla
	tax
	sta	phydata+1
	pla
	sta	phydata
	pha
	txa
	pha

	ldy	#0
	lda	result+0
	sta	(phydata),y
	iny
	lda	result+1
	sta	(phydata),y

	jsr	poplongterm

	pla
	sta	phydata+1
	pla
	sta	phydata

	ldy	#2
	lda	result+0
	sta	(phydata),y
	iny
	lda	result+1
	sta	(phydata),y

	pla
	sta	result+1
	pla
	ora	#$e0
	sta	result+0
	rts
noext
	cmp	#$c0
	bcs	list

	rts
list
	ldx	#$00
	ldy	#$3f
	cmp	#$e0
	and	#$1f
	pha
	lda	result+1
	pha
	bcc	listloop

	jsr	poplongterm
	ldx	result+1
	ldy	result+0
listloop
	txa
	pha
	tya
	pha
	; pushed count msb
	; pushed count lsb
	; pushed tail lsb
	; pushed tail msb

	jsr	alloc_pair

	ldy	#2
	pla
	sta	(phydata),y
	iny
	pla
	sta	(phydata),y

	lda	rpair+1
	pha
	lda	rpair+0
	pha

	jsr	poplongterm

	pla
	sta	rpair+0
	and	#$1f
	sta	temp
	pla
	sta	rpair+1
	asl
	rol	temp
	;clc
	adc	hpbase
	sta	phydata
	lda	temp
	adc	hpbase+1
	sta	phydata+1

	ldy	#0
	lda	result+0
	sta	(phydata),y
	iny
	lda	result+1
	sta	(phydata),y

	pla
	tax
	pla
	tay

	dex
	bne	noc5

	dey
	bmi	listdone
noc5
	tya
	pha
	txa
	pha
	ldx	rpair+1
	ldy	rpair+0
	jmp	listloop
listdone
	lda	rpair+1
	sta	result+1
	lda	rpair+0
	sta	result+0
	rts
	.)

error
	.(
	sta	regs+1
	lda	#$40
	sta	regs+0
	ldx	savedsp
	txs
	jsr	vio_line
	jsr	restartvm
	jmp	startengine
	.)

puthex
	.(
	pha
	lsr
	lsr
	lsr
	lsr
	tax
	lda	hexdigit,x
	jsr	vio_putc
	pla
	and	#$0f
	tax
	lda	hexdigit,x
	jsr	vio_putc
	lda	#SPC_AUTO
	sta	rspc
	rts
hexdigit
	.asc	"0123456789abcdef"
	.)

syncspace
	.(
	lda	rspc
	beq	yes

	cmp	#SPC_PENDING
	bne	no
yes
	lda	#$20
	jsr	vio_putc
	lda	#SPC_SPACE
	sta	rspc
no
	rts
	.)

printvalue
	; input oper0 (clobbered)
	; clobbers phydata, virdata, phytmp
	; clobbers oper4 or workptr ?
	; clobbers physize
	; clobbers databuf, memptr
	; clobbers count, ioparam, temp

	.(
	jsr	derefoper0y
	lda	opermsb+0
	bpl	simple

	jmp	complex
simple
	cmp	#$40
	bcc	nonum

	and	#$3f
	sta	ioparam+1
	lda	operlsb+0
	sta	ioparam
	jmp	printnumber
nonum
	cmp	#$3e
	bne	nochar

	lda	operlsb+0
	jmp	vio_putc
nochar
	bcc	nonil

	lda	#'['
	jsr	vio_putc
	lda	#']'
	jmp	vio_putc
nonil
	cmp	#$20
	bcc	noword

	and	#$1f
	tay
	lda	operlsb+0

	;jmp	printdict

+printdict
	; input a = word id lsb
	; input y = word id msb
	; clobbers temp, phytmp, count

	.(
	jsr	find_dict
dictloop
	ldy	#0
	lda	(phytmp),y
	jsr	vio_putc

	inc	phytmp
	bne	noc3

	inc	phytmp+1
noc3
	dec	count
	bne	dictloop

	rts
	.)
noword
	lda	#$23
	jsr	vio_putc

	lda	chnklsb+CH_TAGS
	sta	virdata+2
	lda	chnkssb+CH_TAGS
	sta	virdata+1
	lda	chnkmsb+CH_TAGS
	sta	virdata+0
	ora	virdata+1
	ora	virdata+2
	beq	objdone

	lda	operlsb+0
	asl
	rol	opermsb+0

	;clc
	adc	virdata+2
	sta	virdata+2
	lda	opermsb+0
	adc	virdata+1
	sta	virdata+1
	bcc	noc1

	inc	virdata+0
noc1
	lda	#2
	jsr	readdata

	lda	chnklsb+CH_TAGS
	clc
	adc	databuf+1
	sta	virdata+2
	lda	chnkssb+CH_TAGS
	adc	databuf+0
	sta	virdata+1
	lda	chnkmsb+CH_TAGS
	adc	#0
	sta	virdata+0
objloop
	lda	#1
	jsr	readdata
	lda	databuf
	beq	objdone

	jsr	vio_putc
	jmp	objloop
objdone
	rts
complex
	cmp	#$e0
	bcc	noext

	and	#$1f
	sta	temp
	lda	operlsb+0
	asl
	rol	temp
	;clc
	adc	hpbase
	sta	phydata
	lda	temp
	adc	hpbase+1
	sta	phydata+1

	ldy	#1
	lda	(phydata),y
	sta	operlsb+0
	dey
	lda	(phydata),y
	sta	opermsb+0
	bmi	extchars

	lda	phydata
	pha
	lda	phydata+1
	pha

	jsr	printvalue

	pla
	sta	phydata+1
	pla
	sta	phydata
	ldy	#3
	lda	(phydata),y
	sta	operlsb+0
	dey
	lda	(phydata),y
	sta	opermsb+0
extchars
#if 0
	lda	#'+'
	jsr	vio_putc
#endif
extloop
	lda	opermsb+0
	cmp	#$3f
	beq	extdone

	and	#$3f
	sta	temp
	lda	operlsb+0
	asl
	rol	temp
	;clc
	adc	hpbase
	sta	phydata
	lda	temp
	adc	hpbase+1
	sta	phydata+1

	ldy	#3
	lda	(phydata),y
	sta	operlsb+0
	dey
	lda	(phydata),y
	sta	opermsb+0
	ldy	#0
	lda	(phydata),y
	iny
	cmp	#$40
	lda	(phydata),y
	bcc	nonumchar

	ora	#$30
nonumchar
	jsr	vio_putc
	jmp	extloop
extdone
	rts
noext
	cmp	#$c0
	bcs	list

	lda	#'$'
	jmp	vio_putc
list
	lda	#'['
	jsr	vio_putc
listloop
	lda	opermsb+0
	and	#$9f
	sta	opermsb+0
	pha
	lda	operlsb+0
	pha

	jsr	printvalue

	pla
	clc
	adc	#1
	sta	operlsb+0
	pla
	adc	#0
	sta	opermsb+0
	jsr	derefoper0y

	lda	opermsb+0
	cmp	#$3f
	beq	properend

	pha
	lda	#$20
	jsr	vio_putc
	pla

	and	#$e0
	cmp	#$c0
	beq	listloop

	lda	#'|'
	jsr	vio_putc
	lda	#$20
	jsr	vio_putc
	jsr	printvalue
properend
	lda	#']'
	jmp	vio_putc
	.)

printnumber
	; input ioparam (l-e)
	; clobbers ioparam

	.(
	jsr	convertnumber
	ldy	#0
loop
	sty	count
	lda	(ioparam),y
	beq	done

	jsr	vio_putc
	ldy	count
	iny
	jmp	loop
done
	rts
	.)

find_dict
	; input a = word id lsb
	; input y = word id msb
	; output count = length
	; output phytmp = chars
	; clobbers temp

	.(
	; phytmp = word id * 3

	sty	temp
	sty	phytmp+1
	sta	phytmp
	asl
	rol	temp
	;clc
	adc	phytmp
	sta	phytmp
	lda	temp
	adc	phytmp+1
	sta	phytmp+1

	; phytmp = dict entry

	lda	phytmp
	clc
	adc	dicttbl
	sta	phytmp
	lda	phytmp+1
	adc	dicttbl+1
	sta	phytmp+1

	; count = length
	; phytmp = actual chars

	ldy	#0
	lda	(phytmp),y
	sta	count
	ldy	#2
	lda	(phytmp),y
	clc
	adc	dictch
	pha
	dey
	lda	(phytmp),y
	adc	dictch+1
	sta	phytmp+1
	pla
	sta	phytmp
	rts
	.)

convertnumber
	; input ioparam (l-e)
	; output ioparam = pointer
	; to null-terminated string

	.(
	ldx	#4
	ldy	#0
	sty	temp
digitloop
countloop
	lda	ioparam
	cmp	pow10lsb,x
	lda	ioparam+1
	sbc	pow10msb,x
	bcc	countdone

	lda	ioparam
	;sec
	sbc	pow10lsb,x
	sta	ioparam
	lda	ioparam+1
	sbc	pow10msb,x
	sta	ioparam+1
	iny
	bne	countloop ; always
countdone
	tya
	beq	skip

	ora	#$30
	jsr	putbyte
	ldy	#$30
skip
	dex
	bpl	digitloop

	dey
	bpl	nonzero

	lda	#$30
	jsr	putbyte
nonzero
	lda	#<intbuf
	sta	ioparam
	lda	#>intbuf
	sta	ioparam+1
	lda	#0
putbyte
	ldy	temp
	sta	intbuf,y
	inc	temp
	rts

pow10lsb
	.byt	<1
	.byt	<10
	.byt	<100
	.byt	<1000
	.byt	<10000
pow10msb
	.byt	>1
	.byt	>10
	.byt	>100
	.byt	>1000
	.byt	>10000
	.)

printstring
	; input virdata
	; input quot = expand dollar
	; clobbers bits, numer, denom

	.(
	lda	virdata+2
	clc
	adc	chnklsb+CH_WRIT
	sta	virdata+2
	lda	virdata+1
	adc	chnkssb+CH_WRIT
	sta	virdata+1
	tay
	lda	virdata+0
	adc	chnkmsb+CH_WRIT
	sta	virdata+0
	tax

	jsr	swapin
	sta	memptr+1
	ldy	virdata+2
	lda	(memptr),y
	sta	bits

	ldy	#0
	sec
	rol	bits
bitloop
	bcc	in0

	iny
in0
	lda	(decoder),y
	bmi	ctrl

	cmp	#$5f
	beq	escchar

	clc
	adc	#$20

	cmp	#$24
	bne	nodollar

	ldx	quot
	bmi	nodollar

	lda	regs,x
	sta	opermsb+0
	inx
	lda	regs,x
	sta	operlsb+0
	inx
	txa
	pha
	lda	virdata+0
	pha
	lda	virdata+1
	pha
	lda	virdata+2
	pha
	lda	memptr+1
	pha
	jsr	printvalue
	pla
	sta	memptr+1
	pla
	sta	virdata+2
	pla
	sta	virdata+1
	pla
	sta	virdata+0
	pla
	sta	quot
	jmp	wasdollar
nodollar
	jsr	vio_putc
wasdollar
	ldy	#0
	beq	nextbit
ctrl
	cmp	#$80
	beq	done

	asl
	tay
nextbit
	asl	bits
	bne	bitloop

	sty	temp
	inc	virdata+2
	beq	wrap1
postwrap1
	ldy	virdata+2
	lda	(memptr),y
	ldy	temp
	sec
	rol
	sta	bits
	bne	bitloop	; always
done
	rts
escchar
	lda	escbits
	sta	denom

	lda	#0
	sta	numer
	sta	numer+1
escloop
	asl	bits
	beq	escbyte
escloop2
	rol	numer
	rol	numer+1
	dec	denom
	bne	escloop

	bit	escbnd
	bmi	oldesc

	lda	numer+1
	bne	escdict

	lda	numer
	cmp	escbnd
	bcs	escdict

	;clc
	adc	#$a0
esccommon
	jsr	vio_putc
	ldy	#0
	beq	nextbit
oldesc
	lda	numer
	ora	#$80
	bmi	esccommon ; always
escdict
	lda	numer
	sec
	sbc	escbnd
	sta	numer
	bcs	noc3

	dec	numer+1
noc3
	lda	#$20
	jsr	vio_putc

	lda	numer
	ldy	numer+1
	jsr	printdict
	ldy	#0
	beq	nextbit
escbyte
	inc	virdata+2
	beq	wrap2
postwrap2
	ldy	virdata+2
	lda	(memptr),y
	sec
	rol
	sta	bits
	bne	escloop2 ; always
wrap1
	inc	virdata+1
	bne	noc1

	inc	virdata+0
noc1
	ldy	virdata+1
	ldx	virdata+0
	jsr	swapin
	sta	memptr+1
	jmp	postwrap1
wrap2
	inc	virdata+1
	bne	noc2

	inc	virdata+0
noc2
	ldy	virdata+1
	ldx	virdata+0
	jsr	swapin
	sta	memptr+1
	jmp	postwrap2
	.)

op_add_num
	.(
	bcs	wasinc

	jsr	fetchvalnum
	jsr	fetchvalnum

	lda	operlsb+0
	clc
	adc	operlsb+1
	sta	result+1
	lda	opermsb+0
	and	#$3f
	adc	opermsb+1
	bmi	fail
ok
	sta	result+0
	jmp	storefetchnext
wasinc
	jsr	fetchvalnum

	lda	operlsb+0
	;sec
	adc	#0
	sta	result+1
	lda	opermsb+0
	adc	#0
	bpl	ok
fail
	jmp	failure
	.)

op_add_raw
	.(
	bcs	wasinc

	jsr	fetchvalue
	jsr	fetchvalue
	lda	operlsb+0
	clc
	adc	operlsb+1
	sta	result+1
	lda	opermsb+0
	adc	opermsb+1
common
	sta	result+0
	jmp	storefetchnext
wasinc
	jsr	fetchvalue
	lda	operlsb+0
	clc
	adc	#1
	sta	result+1
	lda	opermsb+0
	adc	#0
	jmp	common
	.)

op_assign
	.(
	bcs	wasbyte

	jsr	fetchvalue
	jmp	wasval
wasbyte
	jsr	fetchvbyte
wasval
	lda	opermsb+0
	sta	result+0
	lda	operlsb+0
	sta	result+1
	jmp	storefetchnext
	.)

op_aux_pop_chk
	.(
	jsr	fetchvalderef
	sty	`pclsb

	lda	#1
reloop
	sta	count
loop
	ldx	raux+1
	bne	nowrap

	dec	raux+0
nowrap
	dex
	stx	raux+1

	lda	raux+0
	sta	temp
	txa
	asl
	rol	temp
	;clc
	adc	auxbase
	sta	phydata
	lda	temp
	adc	auxbase+1
	sta	phydata+1

	ldy	#0
	lda	(phydata),y
	iny
	ora	(phydata),y
	beq	done

	lda	(phydata),y
	eor	operlsb+0
	bne	loop

	dey
	lda	(phydata),y
	eor	opermsb+0
	bne	loop

	jmp	reloop ; count = 0
done
	lda	count
	bne	fail

	jmp	ldyfetchnext
fail
	jmp	failure
	.)

op_aux_pop_list
	.(
	sty	`pclsb
	jsr	pop_aux_list
	jmp	ldystorefetchnext
	.)

op_aux_pop_mtch
	.(
	jsr	fetchvalue
	sty	`pclsb

	lda	rtop
	pha
	lda	rtop+1
	pha

	jsr	pop_aux_list

	; oper0 is list of keys
	; result is popped list
loop
	jsr	derefoper0y

	lda	opermsb+0
	and	#$e0
	cmp	#$c0
	bne	done

	lda	opermsb+0
	and	#$1f
	sta	temp
	lda	operlsb+0
	asl
	rol	temp
	;clc
	adc	hpbase
	sta	phydata
	lda	temp
	adc	hpbase+1
	sta	phydata+1

	ldy	#0
	lda	(phydata),y
	sta	opermsb+1
	iny
	lda	(phydata),y
	sta	operlsb+1
	iny
	lda	(phydata),y
	sta	opermsb+0
	iny
	lda	(phydata),y
	sta	operlsb+0

	; oper1 is current key

	lda	result+0
	sta	opermsb+2
	lda	result+1
	sta	operlsb+2

	; oper2 is list iterator
matchloop
	jsr	derefoper2y

	lda	opermsb+2
	and	#$e0
	cmp	#$c0
	bne	nomatch

	lda	opermsb+2
	and	#$9f
	sta	opermsb+2
	sta	opermsb+4
	lda	operlsb+2
	sta	operlsb+4
	lda	opermsb+1
	sta	opermsb+5
	lda	operlsb+1
	sta	operlsb+5
	jsr	would_unify
	bcs	loop

	inc	operlsb+2
	bne	matchloop

	inc	opermsb+2
	jmp	matchloop
done
	pla
	sta	rtop+1
	pla
	sta	rtop

	jmp	ldyfetchnext
nomatch
	jmp	failure
	.)

pop_aux_list
	; output result
	; clobbers oper4
	; clobbers phytmp
	; clobbers phydata, rpair

	.(
	lda	raux+0
	sta	temp
	lda	raux+1
	asl
	rol	temp
	;clc
	adc	auxbase
	sta	phytmp
	lda	temp
	adc	auxbase+1
	sta	phytmp+1

	lda	#$3f
	ldx	#0
loop
	sta	opermsb+4
	stx	operlsb+4

	jsr	poplongterm
	lda	result+0
	ora	result+1
	beq	done

	jsr	alloc_pair
	ldy	#0
	lda	result+0
	sta	(phydata),y
	lda	result+1
	iny
	sta	(phydata),y
	lda	opermsb+4
	iny
	sta	(phydata),y
	lda	operlsb+4
	iny
	sta	(phydata),y

	lda	rpair+0
	ldx	rpair+1
	jmp	loop
done
	lda	phytmp
	sec
	sbc	auxbase
	sta	raux+1
	lda	phytmp+1
	sbc	auxbase+1
	lsr
	ror	raux+1
	sta	raux+0

	lda	opermsb+4
	sta	result+0
	lda	operlsb+4
	sta	result+1
	rts
	.)

op_aux_push_raw
	jsr	fetchwordorvbyte

aux_push_raw_1
	sty	`pclsb
	jsr	push_aux
	jmp	ldyfetchnext

op_aux_push_val
	.(
	bcc	val

	lda	#0
	sta	operlsb+0
	sta	opermsb+0
	beq	aux_push_raw_1
val
	jsr	fetchvalue
	sty	`pclsb
+aux_push_val
	lda	raux+0
	sta	temp
	lda	raux+1
	asl
	rol	temp
	;clc
	adc	auxbase
	sta	phytmp
	lda	temp
	adc	auxbase+1
	sta	phytmp+1

	; heap marks end of aux
	lda	hpbase
	sta	physize
	lda	hpbase+1
	sta	physize+1

	lda	opermsb+0
	sta	opermsb+4
	lda	operlsb+0
	sta	operlsb+4

	jsr	pushlongterm

	lda	phytmp
	sec
	sbc	auxbase
	sta	raux+1
	lda	phytmp+1
	sbc	auxbase+1
	lsr
	sta	raux+0
	ror	raux+1

	jmp	ldyfetchnext
	.)

op_bad
	.(
	sty	`pclsb
	ldy	#0
	sty	stflag
	ror
	jsr	puthex

	lda	#<text
	sta	phydata
	lda	#>text
	sta	phydata+1
	jsr	puts

	lda	`pclsb
	clc
	sbc	codeseg+2
	pha
	lda	pcmsb
	sbc	codeseg+1
	pha
	lda	pcbank
	sbc	codeseg+0
	jsr	puthex
	pla
	jsr	puthex
	pla
	jsr	puthex
	jsr	vio_line
	jsr	io_mflush
	jmp	io_quit
text
	.asc	" at ",0
	.)

op_chk_eq
	.(
	jsr	fetchwordorvbyte
	jsr	fetchcode

	lda	ridx+1
	eor	operlsb+0
	bne	no

	lda	ridx+0
	eor	opermsb+0
	bne	no

	jmp	jumpvirdata
no
	jmp	fetchnext
	.)

op_chk_eq_2
	.(
	php
	jsr	fetchwordorvbyte
	plp
	jsr	fetchwordorvbyte
	jsr	fetchcode

	lda	ridx+1
	eor	operlsb+0
	bne	no1

	lda	ridx+0
	eor	opermsb+0
	bne	no1

	jmp	jumpvirdata
no1
	lda	ridx+1
	eor	operlsb+1
	bne	no2

	lda	ridx+0
	eor	opermsb+1
	bne	no2

	jmp	jumpvirdata
no2
	jmp	fetchnext
	.)

op_chk_gt
	.(
	bcs	byte

	jsr	fetchvalue
	jmp	common
byte
	; spec says byte not vbyte
	; but we want msb = 0
	jsr	fetchvbyte
common
	jsr	fetchcode

	lda	operlsb+0
	cmp	ridx+1
	lda	opermsb+0
	sbc	ridx+0
	bcc	yes

	jmp	fetchnext
yes
	jmp	jumpvirdata
	.)

op_chk_gt_eq
	.(
	jsr	fetchwordorvbyte
	jsr	fetchcode

	lda	ridx+1
	cmp	operlsb+0
	lda	ridx+0
	sbc	opermsb+0
	bcc	lt

	lda	ridx+1
	cmp	operlsb+0
	bne	gt

	lda	ridx+0
	cmp	opermsb+0
	bne	gt

	jsr	fetchcode
gt
	jmp	jumpvirdata
lt
	jsr	fetchcode
	jmp	fetchnext
	.)

op_chk_wordmap
	.(
	jsr	fetchindex
	jsr	fetchcode
	sty	`pclsb

	lda	operlsb+0
	asl
	rol	opermsb+0
	;clc
	adc	mapbase
	sta	phydata
	lda	opermsb+0
	adc	mapbase+1
	sta	phydata+1

	ldy	#3
	lda	(phydata),y
	clc
	adc	mapbase
	sta	phytmp
	dey
	lda	(phydata),y
	adc	mapbase+1
	sta	phytmp+1

	; phytmp points to map

	ldy	#0
	sty	dicta
	sty	dicta+1
	lda	(phytmp),y
	sta	dictb+1
	iny
	lda	(phytmp),y
	asl
	rol	dictb+1
	asl
	rol	dictb+1
	sta	dictb

	lda	phytmp
	clc
	adc	#2
	sta	phytmp
	bcc	noc1

	inc	phytmp+1
noc1
	; phytmp points to the table
	; dicta/dictb are indices * 4
findloop
	lda	dicta
	cmp	dictb
	lda	dicta+1
	sbc	dictb+1
	bcs	do_jump

	lda	dicta
	;clc
	adc	dictb
	and	#$f8
	sta	dictpiv
	lda	dicta+1
	adc	dictb+1
	ror
	sta	dictpiv+1
	ror	dictpiv

	lda	phytmp
	;clc
	adc	dictpiv
	sta	phydata
	lda	phytmp+1
	adc	dictpiv+1
	sta	phydata+1

	ldy	#1
	lda	ridx+1
	cmp	(phydata),y
	dey
	lda	ridx+0
	sbc	(phydata),y
	bcc	was_lt

	lda	ridx+0
	cmp	(phydata),y
	bne	was_gt

	iny
	lda	ridx+1
	cmp	(phydata),y
	beq	found
was_gt
	lda	dictpiv
	clc
	adc	#4
	sta	dicta
	lda	dictpiv+1
	adc	#0
	sta	dicta+1
	jmp	findloop
was_lt
	lda	dictpiv
	sta	dictb
	lda	dictpiv+1
	sta	dictb+1
	jmp	findloop
single
	and	#$1f
	sta	opermsb+0
	jsr	push_aux
do_jump
	jmp	jumpvirdata
found
	ldy	#3
	lda	(phydata),y
	sta	operlsb+0
	dey
	lda	(phydata),y
	sta	opermsb+0
	bne	not0

	ldx	operlsb+0
	beq	dontjump
not0
	cmp	#$e0
	bcs	single

	lda	operlsb+0
	;clc
	adc	mapbase
	sta	phytmp
	lda	opermsb+0
	adc	mapbase+1
	sta	phytmp+1
pushloop
	ldy	#0
	lda	(phytmp),y
	beq	do_jump

	cmp	#$e0
	bcc	pushsmall

	and	#$1f
	sta	opermsb+0
	iny
	lda	(phytmp),y
	sta	operlsb+0
	jsr	push_aux

	lda	phytmp
	clc
	adc	#2
	sta	phytmp
	bcc	pushloop

	inc	phytmp+1
	jmp	pushloop
pushsmall
	sta	operlsb+0
	sty	opermsb+0
	jsr	push_aux

	inc	phytmp
	bne	pushloop

	inc	phytmp+1
	jmp	pushloop
dontjump
	jmp	ldyfetchnext
	.)

op_cut_choice
	.(
	lda	rcho+0
	sta	phydata+1
	lda	rcho+1
	asl
	rol	phydata+1
	;clc
	adc	hpbase
	sta	phydata
	lda	phydata+1
	adc	hpbase+1
	sta	phydata+1
	sty	`pclsb
	ldy	#6*2
	lda	(phydata),y
	sta	rcho+0
	iny
	lda	(phydata),y
	sta	rcho+1
	jmp	ldyfetchnext
	.)

op_div_num
	.(
	jsr	fetchvalnum
	jsr	fetchvalnum
	sty	`pclsb

	lda	opermsb+0
	and	#$3f
	sta	numer+1
	lda	operlsb+0
	sta	numer

	lda	opermsb+1
	and	#$3f
	sta	denom+1
	lda	operlsb+1
	sta	denom

	ora	denom+1
	beq	fail

	jsr	div16

	lda	quot+1
	ora	#$40
	sta	result+0
	lda	quot
	sta	result+1

	jmp	ldystorefetchnext
fail
	jmp	failure
	.)

op_embed
	.(
	php
	jsr	fetchvalderef
	sty	`pclsb
	plp
	bcs	canembed

	lda	rcwl
	bne	skip

	inc	operlsb+0
	bne	noc1

	inc	opermsb+0
noc1
	lda	opermsb+0
	and	#$3f
	asl	operlsb+0
	rol
	sta	opermsb+0

	lda	chnklsb+CH_URLS
	;clc
	adc	operlsb+0
	sta	virdata+2
	lda	chnkssb+CH_URLS
	adc	opermsb+0
	sta	virdata+1
	lda	chnkmsb+CH_URLS
	adc	#0
	sta	virdata+0
	lda	#2
	jsr	readdata

	lda	chnklsb+CH_URLS
	clc
	adc	databuf+1
	sta	virdata+2
	lda	chnkssb+CH_URLS
	adc	databuf+0
	sta	virdata+1
	lda	chnkmsb+CH_URLS
	adc	#0
	sta	virdata+0
	lda	#3
	jsr	readdata

	jsr	syncspace
	lda	#'['
	jsr	vio_putc

	lda	databuf+0
	sta	virdata+0
	lda	databuf+1
	sta	virdata+1
	lda	databuf+2
	sta	virdata+2
	lda	#$ff
	sta	quot
	jsr	printstring

	lda	#']'
	jsr	vio_putc
	lda	#SPC_AUTO
	sta	rspc
skip
	jmp	ldyfetchnext
canembed
	lda	#0
	sta	result
	sta	result+1
	jmp	ldystorefetchnext
	.)

op_en_lv_div
	.(
	bcc	enter

	jmp	leave
skip
	jmp	ldyfetchnext
err
	lda	#7
	jmp	error
enter
	jsr	fetchindex
	sty	`pclsb
	lda	rcwl
	bne	skip

	lda	nspan
	bne	err

	ldx	divsp
	lda	opermsb+0
	sta	divstk,x
	lda	operlsb+0
	sta	divstk+1,x
	inx
	inx
	stx	divsp

	asl
	rol	opermsb+0
	asl
	rol	opermsb+0
	asl
	rol	opermsb+0
	;clc
	adc	stybase
	sta	phydata
	lda	opermsb+0
	adc	stybase+1
	sta	phydata+1

	bit	stflag
	bpl	no_en_fl

	bvc	skip1

	ldy	#STY_FLAGS
	lda	(phydata),y
	cmp	#STYF_FLOATL
	bcc	no_en_fl

	tax
	lsr	; rel-width -> c

	ldy	#STY_WIDTH
	lda	(phydata),y
	bcc	norelw

	sta	quot
	lda	stfullw
	sta	denom
	lda	#0
	sta	denom+1
	sta	quot+1
	jsr	mul16
	lda	#100
	sta	denom
	lda	#0
	sta	denom+1
	jsr	div16
	lda	quot
norelw
	tay

	cpx	#STYF_FLOATR
	bcs	floatr

	;clc
	adc	stleft
	tax
	pha
	lda	stendx
	pha
	lda	stfullw
	pha

	stx	stendx
	sty	stfullw
	jmp	floatcommon
floatr
	lda	stleft
	pha
	tya
	eor	#$ff
	;sec
	adc	stendx
	tax
	pha
	lda	stfullw
	pha

	stx	stleft
	sty	stfullw
floatcommon
	ldx	stleft
	stx	stposx
	ldy	#0
	sty	stposy
	jsr	io_slocate

	lda	#SPC_LINE
	sta	rspc
no_en_fl
	ldy	#STY_MTOP
	lda	(phydata),y
	jsr	vio_vspace
	jsr	unstyle
skip1
	jmp	ldyfetchnext
leave
	sty	`pclsb
	lda	rcwl
	bne	skip1

	ldx	divsp
	dex
	dex
	stx	divsp

	lda	divstk,x
	sta	temp
	lda	divstk+1,x
	asl
	rol	temp
	asl
	rol	temp
	asl
	rol	temp
	;clc
	adc	stybase
	sta	phydata
	lda	temp
	adc	stybase+1
	sta	phydata+1

	bit	stflag
	bpl	no_lv_fl

	bvc	skip2

	ldy	#STY_FLAGS
	lda	(phydata),y
	cmp	#STYF_FLOATL
	bcc	no_lv_fl

	pla
	sta	stfullw
	pla
	sta	stendx
	pla
	sta	stleft

	sta	stposx
	tax
	ldy	#0
	sty	stposy
	jsr	io_slocate

	lda	#SPC_LINE
	sta	rspc
	bne	post_lv_fl ; always
no_lv_fl
	ldy	#STY_MBOTTOM
	lda	(phydata),y
	jsr	vio_vspace
post_lv_fl
	jsr	unstyle
skip2
	jmp	ldyfetchnext
	.)

op_en_lv_span
	.(
	bcs	leave

	jsr	fetchindex
	sty	`pclsb
	lda	rcwl
	bne	skip

	ldx	divsp
	lda	opermsb+0
	sta	divstk,x
	lda	operlsb+0
	sta	divstk+1,x
	inx
	inx
	stx	divsp

	inc	nspan
done
	jsr	unstyle
skip
	jmp	ldyfetchnext
leave
	sty	`pclsb
	lda	rcwl
	bne	skip

	dec	nspan

	dec	divsp
	dec	divsp
	bpl	done ; always
	.)

op_en_lv_st
	.(
	bcs	leave

	jsr	fetch0
	jmp	enter_status
leave
	sty	`pclsb
	lda	#SPC_PAR
	sta	rspc

	lda	rcwl
	bne	skip

	dec	divsp
	dec	divsp

	ldx	stflag
	;lda	#0
	sta	stflag

	inx
	bne	skip

	jsr	io_scommit
skip
	jmp	ldyfetchnext
	.)

op_en_st_1
	.(
	jsr	fetchbyte
	;jmp	enter_status
	.)

enter_status
	.(
	jsr	fetchindex
	sty	`pclsb

	jsr	vio_line
	lda	#SPC_PAR
	sta	rspc

	lda	rcwl
	bne	skip

	lda	stflag
	ora	nspan
	bne	err

	ldx	divsp
	lda	opermsb+1
	sta	divstk,x
	lda	operlsb+1
	sta	divstk+1,x
	inx
	inx
	stx	divsp
	stx	stdivsp

	asl
	rol	opermsb+1
	asl
	rol	opermsb+1
	asl
	rol	opermsb+1
	;clc
	adc	stybase
	sta	phydata
	lda	opermsb+1
	adc	stybase+1
	sta	phydata+1

	lda	operlsb+0
	beq	top

	sec
	ror	stflag
	bcc	skip ; always
top
	ldy	#STY_FLAGS
	lda	(phydata),y
	and	#STYF_RELH
	bne	relh

	ldy	#STY_HEIGHT
	lda	(phydata),y
	bne	nozero
relh
	lda	#1
nozero
	cmp	#20
	bcc	nobig

	lda	#19
nobig
	sta	stsizey
	jsr	io_sprepare

	dec	stflag

	ldx	screenw
	stx	stfullw
	stx	stendx
	ldx	#0
	stx	stleft
	stx	stposx
	ldy	#0
	sty	stposy
	jsr	io_slocate
skip
	jmp	ldyfetchnext
err
	lda	#7
	jmp	error
	.)

op_ext0
	.(
	jsr	fetchbyte
	sty	`pclsb

	ldy	operlsb+0
	cpy	#N_EXT0
	bcs	ext0_bad

	lda	ext0_lsb,y
	sta	phydata
	lda	ext0_msb,y
	sta	phydata+1
	jmp	(phydata)
	.)

ext0_bad
	.(
	lda	#$70
	jsr	puthex
	ldy	`pclsb
	lda	operlsb+0
	asl
	jmp	op_bad
	.)

op_get_cho
	.(
	lda	rcho+0
	sta	result+0
	lda	rcho+1
	sta	result+1
	jmp	storefetchnext
	.)

op_get_input
	.(
	sty	`pclsb
	bcs	key

	jsr	syncspace
	jsr	vio_gets
	lda	count
	sta	wordend

	lda	#$3f
	sta	result+0
	lda	#0
	sta	result+1
charloop
	dec	count
	bmi	chardone

	ldx	count
	lda	inpbuf,x
	cmp	#$20
	beq	spc

	ldy	#0
findstop
	lda	(stoptbl),y
	beq	charloop

	cmp	inpbuf,x
	beq	gotstop

	iny
	bne	findstop ; always
gotstop
	inc	count
	jsr	parseword
	dec	count
	jsr	parseword
	jmp	charloop
spc
	inc	count
	jsr	parseword
	dec	count
	dec	wordend
	jmp	charloop
chardone
	inc	count
	jsr	parseword

	lda	#SPC_LINE
	sta	rspc
	bne	store	; always
key
	jsr	syncspace
	jsr	vio_getc
	ldx	#$3e
	cmp	#$30
	bcc	nodigkey

	cmp	#$3a
	bcs	nodigkey

	and	#$0f
	ldx	#$40
nodigkey
	stx	result+0
	sta	result+1
store
	jmp	ldystorefetchnext
	.)

parseword
	; input count = first pos
	; input wordend = past last pos
	; cons output into result
	; store count into wordend
	; clobbers oper4, rpair
	; clobbers phydata
	; clobbers endpos

	.(
	lda	wordend
	sec
	sbc	count
	beq	done

	jsr	parseword_sub
	jsr	push_pair
	lda	operlsb+4
	sta	(phydata),y
	dey
	lda	opermsb+4
	sta	(phydata),y
done
	rts
	.)

parseword_sub
	; input count = first pos
	; input wordend = past last pos
	; input a = length = wordend - count
	; output oper4
	; store count into wordend
	; clobbers rpair, phydata, endpos

	.(
	cmp	#1
	bne	long

	dec	wordend
	ldx	wordend
	lda	inpbuf,x

	ldx	#$3e

	cmp	#$30
	bcc	done1

	cmp	#$3a
	bcs	done1

	ldx	#$40
	and	#$0f
done1
	stx	opermsb+4
	sta	operlsb+4
	rts
long
	; use oper4 to build ending

	lda	#$3f
	sta	opermsb+4
	lda	#0
	sta	operlsb+4
	sta	endpos
endloop
	; at least one char left

	ldy	endpos
endloop2
	lda	(endbase),y
	beq	endfail

	cmp	#$01
	bne	nocheck

	jmp	check
nocheck
	iny
	ldx	wordend
	cmp	inpbuf-1,x
	beq	match

	iny
	sty	endpos
	bne	endloop2 ; always
match
	lda	(endbase),y
	sta	endpos
endfail
	; shift char and keep going

	jsr	alloc_pair
	ldy	#$3e
	dec	wordend
	ldx	wordend
	lda	inpbuf,x
	cmp	#$30
	bcc	nodigit

	cmp	#$3a
	bcs	nodigit

	and	#$0f
	ldy	#$40
nodigit
	pha
	tya
	ldy	#0
	sta	(phydata),y
	iny
	pla
	sta	(phydata),y
	iny
	lda	opermsb+4
	sta	(phydata),y
	iny
	lda	operlsb+4
	sta	(phydata),y
	lda	rpair+0
	sta	opermsb+4
	lda	rpair+1
	sta	operlsb+4

	cpx	count
	bne	endloop

	jsr	alloc_pair
	ldy	#0
	lda	opermsb+4
	sta	(phydata),y
	iny
	lda	operlsb+4
	sta	(phydata),y
	iny
	lda	#$3f
	sta	(phydata),y
	iny
	lda	#0
	sta	(phydata),y
	lda	rpair+0
	ora	#$e0
	sta	opermsb+4
	lda	rpair+1
	sta	operlsb+4
	rts
check
	lda	wordend
	sec
	sbc	count
	cmp	#2
	bcc	endfail

	ldy	#0
	sty	dicta
	sty	dicta+1
	lda	(dictch),y
	sta	dictb+1
	iny
	lda	(dictch),y
	sta	dictb
dictloop
	lda	dicta
	cmp	dictb
	lda	dicta+1
	sbc	dictb+1
	bcc	dictnofail

	inc	endpos
	ldy	endpos
	cpy	#1
	bne	numfail

	; we were checking the full
	; word, and it wasn't in the
	; dictionary.
	; check for a number

	lda	#0
	sta	quot
	sta	quot+1

	ldx	count
chknum
	lda	inpbuf,x
	cmp	#$30
	bcc	numfail

	cmp	#$3a
	bcs	numfail

	ldy	quot+1
	cpy	#>1639+256
	bcs	numfail ; too large

	pha
	lda	#0
	sta	denom+1
	lda	#10
	sta	denom
	jsr	mul16

	pla
	and	#$0f
	clc
	adc	numer
	sta	quot
	lda	numer+1
	adc	#0
	cmp	#$40
	bcs	numfail ; too large
	sta	quot+1

	inx
	cpx	wordend
	bne	chknum

	lda	count
	sta	wordend

	lda	quot+1
	ora	#$40
	sta	opermsb+4
	lda	quot
	sta	operlsb+4
	rts
numfail
	jmp	endloop2
dictnofail
	lda	dicta
	;clc
	adc	dictb
	sta	dictpiv
	lda	dicta+1
	adc	dictb+1
	ror
	sta	dictpiv+1
	ror	dictpiv

	; phydata = dictpiv * 3

	lda	dictpiv+1
	sta	phydata+1
	sta	temp
	lda	dictpiv
	sta	phydata
	asl
	rol	temp
	;clc
	adc	phydata
	sta	phydata
	lda	temp
	adc	phydata+1
	sta	phydata+1

	; phydata = &dict_tbl[dictpiv]

	lda	phydata
	clc
	adc	dicttbl
	sta	phydata
	lda	phydata+1
	adc	dicttbl+1
	sta	phydata+1

	ldy	#0
	lda	(phydata),y
	sta	dictlen
	iny
	lda	(phydata),y
	tax
	iny
	lda	(phydata),y
	clc
	adc	dictch
	sta	phydata
	txa
	adc	dictch+1
	sta	phydata+1

	; now phydata points to chars
	; and dictlen is length

	; meanwhile &inpbuf[count]
	; holds input chars and
	; wordend - count is length

	ldx	count
	ldy	#0
dictcmp
	cpx	wordend
	beq	inp_end

	cpy	dictlen
	beq	was_gt

	lda	inpbuf,x
	cmp	(phydata),y
	bcc	was_lt

	bne	was_gt

	inx
	iny
	bne	dictcmp ; always
inp_end
	cpy	dictlen
	beq	dictfound
was_lt
	lda	dictpiv
	sta	dictb
	lda	dictpiv+1
	sta	dictb+1
	jmp	dictloop
was_gt
	lda	dictpiv
	clc
	adc	#1
	sta	dicta
	lda	dictpiv+1
	adc	#0
	sta	dicta+1
	jmp	dictloop
dictfound
	; piv is index of match

	lda	count
	sta	wordend

	lda	opermsb+4
	bpl	noextra

	jsr	alloc_pair
	ldy	#0
	lda	dictpiv+1
	ora	#$20
	sta	(phydata),y
	iny
	lda	dictpiv
	sta	(phydata),y
	iny
	lda	opermsb+4
	sta	(phydata),y
	iny
	lda	operlsb+4
	sta	(phydata),y
	ldx	rpair+1
	lda	rpair+0
	bmi	tag ; always
noextra
	ldx	dictpiv
	lda	dictpiv+1
tag
	; either turn index into
	; dictword (noextra) or
	; turn cons cell into extdict

	ora	#$20
	sta	opermsb+4
	stx	operlsb+4
	rts
	.)

words_to_string
	; input/output wordend = buffer pos
	; inpbuf = buffer
	; input oper1 = deref'd head
	; input oper2 = deref'd tail

	.(
loop
	lda	opermsb+1
	bmi	neg

	cmp	#$3e
	bcc	less3e

	bne	nochar

	; single-character word

	lda	operlsb+1
	ldx	wordend
	cpx	#64
	bcs	fail

	sta	inpbuf,x
	inc	wordend

	cmp	#$21
	bcc	fail

	ldy	#0
stoploop
	lda	(stoptbl),y
	beq	next1

	cmp	operlsb+1
	beq	fail

	iny
	bpl	stoploop ; always
nochar
	cmp	#$40
	bcc	fail

	; number

	and	#$3f
	sta	ioparam+1
	lda	operlsb+1
	sta	ioparam
	jsr	convertnumber
	ldy	#0
	ldx	wordend
numloop
	lda	(ioparam),y
	beq	numdone

	cpx	#64
	bcs	fail
	sta	inpbuf,x
	inx
	iny
	bpl	numloop ; always
numdone
	stx	wordend
next1
	beq	next ; always
fail
	jmp	failure
less3e
	and	#$e0
	cmp	#$20
	bne	fail

	; dictionary word

	eor	opermsb+1
	tay
	lda	operlsb+1
	jsr	find_dict

	ldx	wordend
	txa
	clc
	adc	count
	cmp	#65
	bcs	fail

	ldy	#0
dictloop
	lda	(phytmp),y
	sta	inpbuf,x
	inx
	iny
	cpy	count
	bne	dictloop

	stx	wordend
	beq	next ; always
neg
	cmp	#$e0
	bcc	fail

	; extended word

	and	#$1f
	sta	temp
	lda	operlsb+1
	asl
	rol	temp
	;clc
	adc	hpbase
	sta	phydata
	lda	temp
	adc	hpbase+1
	sta	phydata+1

	lda	opermsb+2
	pha
	lda	operlsb+2
	pha

	ldy	#0
	lda	(phydata),y
	bpl	combined

	sta	opermsb+2
	iny
	lda	(phydata),y
dorecurse
	sta	operlsb+2
	ldx	#3
	jsr	dereflastoper
	jsr	recurse

	pla
	sta	operlsb+2
	pla
	sta	opermsb+2
	jmp	next
combined
	lda	opermsb+1
	sta	opermsb+2
	lda	operlsb+1
	jmp	dorecurse
next
	lda	opermsb+2
	cmp	#$3f
	beq	done

	and	#$e0
	cmp	#$c0
	bne	fail
recurse
	lda	opermsb+2
	and	#$1f
	sta	temp
	lda	operlsb+2
	asl
	rol	temp
	;clc
	adc	hpbase
	sta	phydata
	lda	temp
	adc	hpbase+1
	sta	phydata+1
	ldy	#0
	lda	(phydata),y
	sta	opermsb+1
	iny
	lda	(phydata),y
	sta	operlsb+1
	iny
	lda	(phydata),y
	sta	opermsb+2
	iny
	lda	(phydata),y
	sta	operlsb+2
	ldx	#2
	jsr	dereflastoper
	inx
	jsr	dereflastoper
	jmp	loop
done
	rts
	.)

op_if_bound
	.(
	jsr	fetchvalderef
	lda	opermsb+0
	and	#$e0
	cmp	#$80
	beq	no

	jmp	ifyes
no
	jmp	ifno
	.)

op_if_cwl
	.(
	lda	rcwl
	bne	yes

	jmp	ifno
yes
	jmp	ifyes
	.)

op_if_empty
	.(
	jsr	fetchvalderef
	lda	opermsb+0
	cmp	#$3f
	bne	no

	jmp	ifyes
no
	jmp	ifno
	.)

op_if_eq
	.(
	jsr	fetchwordorvbyte
	jsr	fetchvalderef

	lda	operlsb+0
	cmp	operlsb+1
	bne	no

	lda	opermsb+0
	cmp	opermsb+1
	bne	no

	jmp	ifyes
no
	jmp	ifno
	.)

op_if_flag
	.(
	jsr	fetchfield0
	sty	`pclsb

	lda	operlsb+1
	pha
	lsr	opermsb+1
	ror
	lsr	opermsb+1
	ror
	lsr	opermsb+1
	ror
	sta	operlsb+1
	jsr	findfield
	pla
	bcs	no

	and	#7
	tay
	lda	flagbit,y
	ldy	#0
	and	(phydata),y
	beq	no

	ldy	`pclsb
	jmp	ifyes
no
	ldy	`pclsb
	jmp	ifno
	.)

op_if_gt
	.(
	jsr	fetchvalderef
	jsr	fetchvalderef

	lda	opermsb+0
	bmi	no

	cmp	#$40
	bcc	no

	lda	opermsb+1
	bmi	no

	cmp	#$40
	bcc	no

	lda	operlsb+1
	cmp	operlsb+0
	lda	opermsb+1
	sbc	opermsb+0
	bcs	no

	jmp	ifyes
no
	jmp	ifno
	.)

op_if_mem_eq_1
	.(
	jsr	fetchfield0
	sty	`pclsb
	jsr	readfield
	ldy	`pclsb
	jsr	fetchvalue
common
	lda	operlsb+2
	cmp	result+1
	bne	no

	lda	opermsb+2
	cmp	result+0
	bne	no

	jmp	ifyes
no
	jmp	ifno

+op_if_mem_eq_2
	jsr	fetchfield0
	sty	`pclsb
	jsr	readfield
	ldy	`pclsb
	jsr	fetchvbyte
	jmp	common
	.)

op_if_num
	.(
	jsr	fetchvalderef
	lda	opermsb+0
	bmi	no

	cmp	#$40
	bcc	no

	jmp	ifyes
no
	jmp	ifno
	.)

op_if_obj
	.(
	jsr	fetchvalderef
	lda	opermsb+0
	beq	was0

	cmp	#$20
	bcs	fail
succeed
	jmp	ifyes
was0
	lda	operlsb+0
	bne	succeed
fail
	jmp	ifno
	.)

op_if_pair
	.(
	jsr	fetchvalderef
	lda	opermsb+0
	and	#$e0
	cmp	#$c0
	bne	no

	jmp	ifyes
no
	jmp	ifno
	.)

op_if_raw_eq
	.(
	bcc	word

	lda	#0
	sta	operlsb+0
	sta	opermsb+0
	inx
	bne	was0
word
	jsr	fetchword
was0
	jsr	fetchvalue
	lda	operlsb+0
	cmp	operlsb+1
	bne	nomatch

	lda	opermsb+0
	cmp	opermsb+1
	bne	nomatch

	jmp	ifyes
nomatch
	jmp	ifno
	.)

op_if_unify
	.(
	jsr	fetchvalue
	jsr	fetchvalue

	sty	`pclsb
	lda	opermsb+0
	sta	opermsb+4
	lda	operlsb+0
	sta	operlsb+4
	lda	opermsb+1
	sta	opermsb+5
	lda	operlsb+1
	sta	operlsb+5
	jsr	would_unify
	ldy	`pclsb
	bcc	no

	jmp	ifyes
no
	jmp	ifno
	.)

op_if_word
	.(
	bcs	unknown

	jsr	fetchvalderef

	lda	opermsb+0
	cmp	#$3f
	beq	no

	and	#$e0
	cmp	#$20
	beq	yes

	cmp	#$e0
	beq	yes
no
	jmp	ifno
unknown
	jsr	fetchvalderef

	lda	opermsb+0
	cmp	#$e0
	bcc	no

	and	#$1f
	sta	temp
	lda	operlsb+0
	asl
	rol	temp
	;clc
	adc	hpbase
	sta	phydata
	lda	temp
	adc	hpbase+1
	sta	phydata+1

	ldx	#0
	lda	(phydata,x)
	bpl	no
yes
	jmp	ifyes
	.)

op_jmp
	.(
	jsr	fetchcode
	jmp	jumpvirdata
	.)

op_jmp_multi
	.(
	lda	#$ff
	sta	rsim+0
	sta	rsim+1
	bcs	jmpl_common

jmp_common
	jsr	fetchcode
	jmp	jumpvirdata

+op_jmp_simple
	lda	rcho+0
	sta	rsim+0
	lda	rcho+1
	sta	rsim+1
	bcc	jmp_common

jmpl_common
	jsr	fetchcode
	tya
	sec
	sbc	codeseg+2
	sta	cont+3
	lda	pcmsb
	sbc	codeseg+1
	sta	cont+2
	lda	pcbank
	sbc	codeseg+0
	sta	cont+1
	jmp	jumpvirdata
	.)

op_jmp_tail
	.(
	bcs	tail

	jsr	fetchcode

	lda	rsim+0
	bpl	simple

	lda	rcho+0
	sta	rsim+0
	lda	rcho+1
	sta	rsim+1
simple
	jmp	jumpvirdata
tail
	lda	rsim+0
	bpl	simple1

	lda	rcho+0
	sta	rsim+0
	lda	rcho+1
	sta	rsim+1
simple1
	jmp	fetchnext
	.)

op_line_par
	.(
	lda	rcwl
	bne	skip

	sty	`pclsb
	bcs	par

	jsr	vio_line
skip
	jmp	ldyfetchnext
par
	lda	#1
	jsr	vio_vspace
	jmp	ldyfetchnext
	.)

op_link
	.(
	bcs	leave

	jsr	fetchvalue
	inc	nspan
	inc	nspan
leave
	dec	nspan
	jmp	fetchnext

+op_selflink
	bcs	leave

	sty	`pclsb
	jsr	syncspace
	inc	nspan
	jmp	ldyfetchnext
	.)

op_load_byte
	.(
	jsr	fetchfield0
	sty	`pclsb
	jsr	findfield

	lda	#0
	sta	result+0
	bcs	noobj

	tay
	lda	(phydata),y
noobj
	sta	result+1
	jmp	ldystorefetchnext
	.)

op_load_val
	.(
	jsr	fetchfield0
	sty	`pclsb
	jsr	readfield

	lda	result+0
	bpl	simple

	sta	temp
	lda	result+1
	asl
	rol	temp
	clc
	adc	rambase
	sta	phytmp
	lda	temp
	adc	rambase+1
	sta	phytmp+1

	ldy	#0
	lda	(phytmp),y
	sta	temp
	iny
	lda	(phytmp),y
	asl
	rol	temp
	;clc
	adc	phytmp
	sta	phytmp
	lda	phytmp+1
	adc	temp
	sta	phytmp+1

	jsr	poplongterm
	lda	result+0
simple
	ora	result+1
	beq	fail

	jmp	ldystorefetchnext
fail
	jmp	failure
	.)

op_load_word
	.(
	jsr	fetchfield0
	sty	`pclsb
	jsr	readfield
	jmp	ldystorefetchnext
	.)

op_make_pair1
	jsr	fetchbyte
	lda	#0
	sta	count
	beq	makepair_common

op_make_pair2
	.(
	lda	#$ff
	sta	count
	jsr	fetchwordorvbyte
	;jmp	makepair_common
	.)

makepair_common
	.(
	jsr	fetchbyte
	jsr	fetchbyte
	sty	`pclsb

	lda	operlsb+2
	bmi	unif

	jsr	alloc_pair

	lda	rpair+1
	sta	result+1
	lda	rpair+0
	sta	result+0
	and	#$9f
	sta	rpair+0

	ldy	count
	beq	make1a

	lda	opermsb+0
	iny
	sta	(phydata),y
	lda	operlsb+0
	iny
	sta	(phydata),y
	jmp	post1a
make1a
	lda	operlsb+0
	jsr	makepairsub
post1a
	inc	rpair+1
	bne	noc1

	inc	rpair+0
noc1
	ldy	#2
	lda	operlsb+1
	jsr	makepairsub

	ldy	`pclsb
	lda	operlsb+2
	jsr	storehere
	jmp	fetchnext
unif
	asl
	bpl	ureg

	; get from env slot

	and	#$7f
	tay
	lda	(envbase),y
	sta	opermsb+2
	iny
	lda	(envbase),y
	jmp	ucommon
ureg
	; get from register

	tax
	lda	regs+0,x
	sta	opermsb+2
	lda	regs+1,x
ucommon
	sta	operlsb+2
	jsr	derefoper2y

	lda	opermsb+2
	and	#$e0
	cmp	#$80
	bne	novar

	jsr	alloc_pair

	lda	rpair+1
	sta	operlsb+4
	lda	rpair+0
	sta	opermsb+4
	and	#$9f
	sta	rpair+0

	ldy	count
	beq	make1b

	lda	opermsb+0
	iny
	sta	(phydata),y
	lda	operlsb+0
	iny
	sta	(phydata),y
	jmp	post1b
make1b
	lda	operlsb+0
	jsr	makepairsub
post1b
	inc	rpair+1
	bne	noc2

	inc	rpair+0
noc2
	ldy	#2
	lda	operlsb+1
	jsr	makepairsub

	lda	opermsb+2
	sta	opermsb+5
	lda	operlsb+2
	sta	operlsb+5
	jsr	unify
	jmp	ldyfetchnext
novar
	cmp	#$c0
	bne	nopair

	lda	opermsb+2
	and	#$9f
	sta	result+0
	lda	operlsb+2
	sta	result+1

	ldy	count
	beq	make1c

	lda	result+0
	sta	opermsb+4
	lda	result+1
	sta	operlsb+4
	lda	opermsb+0
	sta	opermsb+5
	lda	operlsb+0
	sta	operlsb+5
	jsr	unify
	ldy	`pclsb
	jmp	post1c
make1c
	ldy	`pclsb
	lda	operlsb+0
	jsr	storehere
post1c
	inc	result+1
	bne	noc3

	inc	result+0
noc3
	lda	operlsb+1
	jsr	storehere
	jmp	fetchnext
nopair
	jmp	failure
	.)

makepairsub
	; input a, flags = arg byte
	; input y = byte offset in pair
	; input phydata = pair pointer
	; input rpair = slot value
	; clobbers x, y

	.(
	bpl	put

	asl
	bpl	getreg

	; env slot
	sty	temp
	and	#$7f
	tay
	lda	(envbase),y
	tax
	iny
	lda	(envbase),y
	ldy	temp
	iny
	sta	(phydata),y
	dey
	txa
	sta	(phydata),y
	rts
getreg
	tax
	lda	regs,x
	sta	(phydata),y
	iny
	lda	regs+1,x
	sta	(phydata),y
	rts
put
	pha
	lda	#0
	sta	(phydata),y
	iny
	sta	(phydata),y
	pla

	asl
	bpl	putreg

	; store to env slot

	and	#$7f
	tay
	lda	rpair+0
	sta	(envbase),y
	iny
	lda	rpair+1
	sta	(envbase),y
	rts
putreg
	; store to register

	tax
	lda	rpair+0
	sta	regs+0,x
	lda	rpair+1
	sta	regs+1,x
	rts
	.)

op_make_var
	.(
	sty	`pclsb
	jsr	alloc_var
	jmp	ldystorefetchnext
	.)

op_mod_num
	.(
	jsr	fetchvalnum
	jsr	fetchvalnum
	sty	`pclsb

	lda	opermsb+0
	and	#$3f
	sta	numer+1
	lda	operlsb+0
	sta	numer

	lda	opermsb+1
	and	#$3f
	sta	denom+1
	lda	operlsb+1
	sta	denom

	ora	denom+1
	beq	fail

	jsr	div16

	lda	remain+1
	ora	#$40
	sta	result+0
	lda	remain
	sta	result+1

	jmp	ldystorefetchnext
fail
	jmp	failure
	.)

op_mul_num
	.(
	jsr	fetchvalnum
	jsr	fetchvalnum
	sty	`pclsb

	lda	opermsb+0
	and	#$3f
	sta	quot+1
	lda	operlsb+0
	sta	quot

	lda	opermsb+1
	and	#$3f
	sta	denom+1
	lda	operlsb+1
	sta	denom

	jsr	mul16

	lda	numer+1
	and	#$3f
	ora	#$40
	sta	result+0
	lda	numer
	sta	result+1

	jmp	ldystorefetchnext
	.)

op_pop_choice
	.(
	jsr	fetchbyteor0
	sty	`pclsb

	lda	rcho+0
	sta	phydata+1
	lda	rcho+1
	asl
	rol	phydata+1
	;clc
	adc	hpbase
	sta	phydata
	lda	phydata+1
	adc	hpbase+1
	sta	phydata+1

	ldy	#12
	lda	(phydata),y
	sta	rcho+0
	iny
	lda	(phydata),y
	sta	rcho+1

	jmp	pop_common
	.)

op_pop_env
	.(
	sty	`pclsb
	php

	lda	renv+0
	sta	temp
	lda	renv+1
	asl
	rol	temp
	;clc
	adc	hpbase
	sta	phydata
	lda	temp
	adc	hpbase+1
	sta	phydata+1

	ldy	#0
	lda	(phydata),y
	sta	renv+0
	iny
	lda	(phydata),y
	sta	renv+1
	iny

	plp
	bcs	proceed

	lda	(phydata),y
	sta	rsim+0
	iny
	lda	(phydata),y
	sta	rsim+1

	ldy	#5
	lda	(phydata),y
	sta	cont+1
	iny
	lda	(phydata),y
	sta	cont+2
	iny
	lda	(phydata),y
	sta	cont+3

	jsr	update_envbase
	jmp	ldyfetchnext
proceed
	lda	(phydata),y
	bmi	multi

	sta	rcho+0
	iny
	lda	(phydata),y
	sta	rcho+1
multi
	ldy	#5
	lda	(phydata),y
	sta	inst+1
	iny
	lda	(phydata),y
	sta	inst+2
	iny
	lda	(phydata),y
	sta	inst+3

	jsr	update_envbase
	jmp	fetchinst
	.)

op_p_p_choice
	.(
	jsr	fetchbyteor0
	jsr	fetchcode
	sty	`pclsb

	lda	rcho+0
	sta	phydata+1
	lda	rcho+1
	asl
	rol	phydata+1
	;clc
	adc	hpbase
	sta	phydata
	lda	phydata+1
	adc	hpbase+1
	sta	phydata+1

	ldy	#9
	lda	virdata+0
	sta	(phydata),y
	iny
	lda	virdata+1
	sta	(phydata),y
	iny
	lda	virdata+2
	sta	(phydata),y

	;jmp	pop_common
	.)

pop_common
	.(
	ldy	#0
	lda	(phydata),y
	sta	renv+0
	iny
	lda	(phydata),y
	sta	renv+1
	iny
	lda	(phydata),y
	sta	rsim+0
	iny
	lda	(phydata),y
	sta	rsim+1

	ldy	#5
	lda	(phydata),y
	sta	cont+1
	iny
	lda	(phydata),y
	sta	cont+2
	iny
	lda	(phydata),y
	sta	cont+3

	ldy	#14
	lda	(phydata),y
	sta	rtop+0
	iny
	lda	(phydata),y
	sta	rtop+1
	iny
	lda	(phydata),y
	sta	virdata+0 ; trl end
	iny
	lda	(phydata),y
	sta	virdata+1 ; trl end

	lda	operlsb+0
	beq	argsdone

	iny
	ldx	#0
argsloop
	lda	(phydata),y
	iny
	sta	regs,x
	inx
	lda	(phydata),y
	iny
	sta	regs,x
	inx
	dec	operlsb+0
	bne	argsloop
argsdone
	jsr	update_envbase

	; rewind trail
trailloop
	lda	rtrl+1
	cmp	virdata+1
	lda	rtrl+0
	sbc	virdata+0
	bcs	traildone

	lda	rtrl+0
	sta	phydata+1
	lda	rtrl+1
	asl
	rol	phydata+1
	;clc
	adc	auxbase
	sta	phydata
	lda	phydata+1
	adc	auxbase+1
	sta	phydata+1

	ldy	#0
	lda	(phydata),y
	sta	temp
	iny
	lda	(phydata),y
	asl
	rol	temp
	;clc
	adc	hpbase
	sta	phydata
	lda	temp
	adc	hpbase+1
	sta	phydata+1

	lda	#0
	sta	(phydata),y
	dey
	sta	(phydata),y

	inc	rtrl+1
	bne	trailloop

	inc	rtrl+0
	jmp	trailloop
traildone
	jmp	ldyfetchnext
	.)

op_pop_stop
	.(
	lda	rsta+1
	sec
	sbc	#2
	sta	raux+1
	lda	rsta+0
	sbc	#0
	sta	raux+0

	sta	phydata+1
	lda	raux+1
	asl
	rol	phydata+1
	;clc
	adc	auxbase
	sta	phydata
	lda	phydata+1
	adc	auxbase+1
	sta	phydata+1

	sty	`pclsb
	ldy	#0
	lda	(phydata),y
	sta	rstc+0
	iny
	lda	(phydata),y
	sta	rstc+1
	iny
	lda	(phydata),y
	sta	rsta+0
	iny
	lda	(phydata),y
	sta	rsta+1
	jmp	ldyfetchnext
	.)

op_print_str_a
	.(
	sty	`pclsb
	lda	rspc
	bcs	n_str

	beq	sp
n_str
	cmp	#SPC_PENDING
	bne	nosp
sp
	lda	#$20
	jsr	vio_putc
nosp
	lda	#SPC_AUTO
	jmp	printstr_common
	.)

op_print_str_n
	.(
	sty	`pclsb
	lda	rspc
	bcs	n_str

	beq	sp
n_str
	cmp	#SPC_PENDING
	bne	nosp
sp
	lda	#$20
	jsr	vio_putc
nosp
	lda	#SPC_NO
	;jmp	printstr_common
	.)

printstr_common
	.(
	sta	rspc

	ldy	`pclsb
	jsr	fetchstring
	sty	`pclsb
	lda	#$ff
	sta	quot
	jsr	printstring
	jmp	ldyfetchnext
	.)

op_print_val
	.(
	jsr	fetchvalderef
	sty	`pclsb

	lda	rcwl
	bne	collect

	lda	opermsb+0
	cmp	#$3e
	bne	nochar

	ldy	nosbpos
loop1
	lda	(stoptbl),y
	beq	done1

	iny
	cmp	operlsb+0
	bne	loop1

	lda	#SPC_NO
	sta	rspc
done1
	jsr	syncspace
	lda	operlsb+0
	jsr	vio_putc

	ldy	nosapos
loop2
	lda	(stoptbl),y
	beq	done2

	iny
	cmp	operlsb+0
	bne	loop2

	lda	#SPC_NO
	bne	done ; always
nochar
	jsr	syncspace

	jsr	printvalue
done2
	lda	#SPC_AUTO
done
	sta	rspc
	jmp	ldyfetchnext
collect
	jmp	aux_push_val
	.)

op_proceed
	.(
	lda	rsim+0
	bmi	multi

	sta	rcho+0
	lda	rsim+1
	sta	rcho+1
multi
	lda	cont+1
	sta	inst+1
	lda	cont+2
	sta	inst+2
	lda	cont+3
	sta	inst+3
	jmp	fetchinst
	.)

op_progress
	.(
	jsr	fetchvalderef
	jsr	fetchvalderef
	sty	`pclsb

	lda	rcwl
	bne	skip

	jsr	vio_line

	lda	opermsb+0
	bmi	skip

	cmp	#$40
	bcc	skip

	and	#$3f
	sta	opermsb+0

	lda	opermsb+1
	bmi	skip

	cmp	#$40
	bcc	skip

	and	#$3f
	sta	opermsb+1

	jsr	progressbar
	jsr	vio_line
skip
	jmp	ldyfetchnext
	.)

progressbar
	.(
	lda	operlsb+0
	sec
	sbc	operlsb+1
	lda	opermsb+0
	sbc	opermsb+1
	bcc	nosat

	lda	operlsb+1
	sta	operlsb+0
	lda	opermsb+1
	sta	opermsb+0
nosat
	; oper2 =
	; (width << PRSHIFT) - PREXTRA
	; must be <= 255

	bit	stflag
	bpl	nostw

	bvc	skip

	lda	stfullw
	jmp	poststw
nostw
	lda	screenw
poststw
#if PRSHIFT > 2
	asl
#endif
#if PRSHIFT > 1
	asl
#endif
#if PRSHIFT > 0
	asl
#endif
	sec
	sbc	#PREXTRA
	bcc	skip

	sta	operlsb+2

	; x = oper0 * oper2 / oper1
shloop
	bit	opermsb+0
	bmi	shdone

	bit	opermsb+1
	bmi	shdone

	asl	operlsb+0
	rol	opermsb+0
	asl	operlsb+1
	rol	opermsb+1
	bpl	shloop ; always
shdone
	lda	opermsb+1
	bne	nozero

	lda	operlsb+2
	jmp	waszero
skip
	rts
nozero
	lda	opermsb+0
	sta	quot
	lda	operlsb+2
	sta	denom
	lda	#0
	sta	quot+1
	sta	denom+1
	jsr	mul16

	lda	opermsb+1
	sta	denom
	lda	#0
	sta	denom+1
	jsr	div16
	lda	quot
waszero
	tax
	ldy	operlsb+2

	lda	#SPC_AUTO
	sta	rspc

	lda	stflag
	beq	nost

	jmp	io_sprogress
nost
	jmp	io_mprogress
	.)

op_push_choice
	.(
	jsr	fetchbyteor0
	jsr	fetchcode
	sty	`pclsb
	lda	operlsb+0
	jsr	pushchoice
	jmp	ldyfetchnext
	.)

op_push_env
	.(
	jsr	fetchbyteor0
	clc
	adc	#4
	sta	temp

	lda	renv+0
	pha
	lda	renv+1
	pha

	cmp	rcho+1
	lda	renv+0
	sbc	rcho+0
	bcs	usecho

	lda	renv+1
	sec
	sbc	temp
	sta	renv+1
	bcs	noc1

	dec	renv+0
noc1
	jmp	gotit
overflow
	lda	#1
	jmp	error
usecho
	lda	rcho+1
	sec
	sbc	temp
	sta	renv+1
	lda	rcho+0
	sbc	#0
	sta	renv+0
gotit
	lda	renv+1
	cmp	rtop+1
	lda	renv+0
	sbc	rtop+0
	bcc	overflow

	lda	renv+0
	sta	phydata+1
	lda	renv+1
	asl
	rol	phydata+1
	;clc
	adc	hpbase
	sta	phydata
	lda	phydata+1
	adc	hpbase+1
	sta	phydata+1

	sty	`pclsb
	ldy	#1
	pla
	sta	(phydata),y
	dey
	pla
	sta	(phydata),y
	ldy	#2
	lda	rsim+0
	sta	(phydata),y
	iny
	lda	rsim+1
	sta	(phydata),y
	iny
	lda	#0
	sta	(phydata),y
	iny
	lda	cont+1
	sta	(phydata),y
	iny
	lda	cont+2
	sta	(phydata),y
	iny
	lda	cont+3
	sta	(phydata),y

	lda	phydata
	clc
	adc	#4*2
	sta	envbase
	lda	phydata+1
	adc	#0
	sta	envbase+1

	jmp	ldyfetchnext
	.)

op_push_stop
	.(
	jsr	fetchcode
	sty	`pclsb
	lda	rstc+0
	sta	opermsb+0
	lda	rstc+1
	sta	operlsb+0
	jsr	push_aux
	lda	rsta+0
	sta	opermsb+0
	lda	rsta+1
	sta	operlsb+0
	jsr	push_aux
	lda	raux+0
	sta	rsta+0
	lda	raux+1
	sta	rsta+1
	lda	#0
	jsr	pushchoice
	lda	rcho+0
	sta	rstc+0
	lda	rcho+1
	sta	rstc+1
	jmp	ldyfetchnext
	.)

op_rand_num
	.(
	jsr	fetchvalnum
	jsr	fetchvalnum
	sty	`pclsb

	lda	operlsb+1
	sec
	sbc	operlsb+0
	sta	denom

	lda	opermsb+1
	sbc	opermsb+0
	bcc	fail

	inc	denom
	bne	noc1

	;sec
	adc	#0
noc1
	sta	denom+1

	jsr	io_random
	stx	numer
	sty	numer+1

	jsr	div16

	lda	remain
	clc
	adc	operlsb+0
	sta	result+1
	lda	remain+1
	adc	opermsb+0
	ora	#$40
	sta	result+0

	jsr	ldystorefetchnext
fail
	jmp	failure
	.)

op_rand_raw
	.(
	jsr	fetchbyte
	sty	`pclsb

	lda	operlsb+0
	clc
	adc	#1
	sta	denom
	lda	#0
	adc	#0
	sta	denom+1

	jsr	io_random
	stx	numer
	sty	numer+1

	jsr	div16

	lda	remain
	sta	result+1
	lda	remain+1
	sta	result+0

	jmp	ldystorefetchnext
	.)

op_reset_flag
	.(
	jsr	fetchfield0
	sty	`pclsb

	lda	operlsb+1
	pha
	lsr	opermsb+1
	ror
	lsr	opermsb+1
	ror
	lsr	opermsb+1
	ror
	sta	operlsb+1
	jsr	findfield
	pla
	bcs	badtype

	and	#7
	tay
	lda	flagbit,y
	eor	#$ff
	ldy	#0
	and	(phydata),y
	sta	(phydata),y
badtype
	jmp	ldyfetchnext
	.)

op_save
	.(
	lda	stflag
	ora	nspan
	bne	err

	bcc	savegame

	jmp	saveundo
err
	lda	#7
	jmp	error
savegame
	.(
	sty	`pclsb

	; We will load the initial
	; state, and then we will
	; overwrite part of the page
	; buffers. Avoid putting the
	; initial state in the part
	; that we will overwrite.

	lda	firstpg
	pha
	lda	#>(SAVEADDR+4096)
	sta	firstpg

	jsr	cleanupmem
	jsr	xorinit

	ldx	#<SAVEADDR
	stx	phytmp
	ldx	#>SAVEADDR
	stx	phytmp+1
	jsr	evictx

	.(
	ldy	#0
loop
	lda	form0000aasv,y
	jsr	putsavebyte
	iny
	cpy	#12+7
	bne	loop
	.)

	.(
	ldy	#0
	lda	(hdbase),y
	sta	count
loop
	lda	(hdbase),y
	jsr	putsavebyte
	iny
	cpy	count
	bne	loop

	lda	(hdbase),y
	jsr	putsavebyte

	lsr	count
	bcc	noc1

	lda	#0
	jsr	putsavebyte
noc1
	.)

	.(
	ldy	#0
loop
	lda	data0000,y
	jsr	putsavebyte
	iny
	cpy	#8
	bne	loop

	lda	phytmp
	sta	workptr
	lda	phytmp+1
	sta	workptr+1
	.)

	.(
	lda	#0
	sta	phydata
	lda	inbase+1
	sta	phydata+1
	ldy	inbase
loop
	cpy	#<HEAPEND
	bne	noend

	lda	phydata+1
	cmp	#>HEAPEND
	beq	done
noend
	lda	(phydata),y
	beq	rle
norle
	jsr	putsavebyte
	iny
	bne	loop

	inc	phydata+1
	jmp	loop
rle
	lda	#0
	jsr	putsavebyte
	ldx	#0
rleloop
	iny
	bne	nowrap

	inc	phydata+1
nowrap
	inx
	beq	rledone

	cpy	#<HEAPEND
	bne	noend2

	lda	phydata+1
	cmp	#>HEAPEND
	beq	rledone
noend2
	lda	(phydata),y
	beq	rleloop
rledone
	dex
	txa
	jsr	putsavebyte
	jmp	loop
done
	lda	phytmp
	sec
	sbc	workptr
	pha
	lda	phytmp+1
	sbc	workptr+1
	pha

	lda	workptr
	sec
	sbc	#2
	sta	workptr
	bcs	noc1

	dec	workptr+1
noc1
	ldy	#0
	pla
	sta	(workptr),y
	iny
	pla
	sta	(workptr),y
	lsr
	bcc	noc2

	lda	#0
	jsr	putsavebyte
noc2
	.)

	.(
	ldy	#0
loop
	lda	regs000,y
	jsr	putsavebyte
	iny
	cpy	#7
	bne	loop

	lda	#2*64+26+2
	clc
	adc	divsp
	jsr	putsavebyte
	.)

	.(
	ldy	#0
loop
	lda	regs,y
	jsr	putsavebyte
	iny
	bpl	loop
	.)

	.(
	lda	#SPC_PAR
	cmp	rspc
	bcs	nosat

	sta	rspc
nosat
	.)

	.(
	ldy	`pclsb
	jsr	fetchcode
	sty	`pclsb

	ldy	#0
	tya
	jsr	putsavebyte
instloop
	lda	virdata,y
	jsr	putsavebyte
	iny
	cpy	#3
	bne	instloop

	iny
loop
	lda	specreg,y
	jsr	putsavebyte
	iny
	cpy	#26
	bne	loop
	.)

	.(
	lda	#0
	jsr	putsavebyte
	lda	divsp
	lsr
	jsr	putsavebyte

	ldy	#0
loop
	cpy	divsp
	beq	done

	lda	divstk,y
	jsr	putsavebyte
	iny
	jmp	loop
done
	.)

	.(
	lda	phytmp
	sec
	sbc	#<SAVEADDR
	tax
	lda	phytmp+1
	sbc	#>SAVEADDR
	tay

	txa
	;sec
	sbc	#8
	sta	SAVEADDR+7
	tya
	sbc	#0
	sta	SAVEADDR+6

	pla
	sta	firstpg

	jsr	io_save
	php
	jsr	xorinit
	plp
	bcs	ok

	jmp	failure
ok
	jmp	refetchnext
	.)
	.)
saveundo
	jsr	fetchcode
	sty	`pclsb

	; memory layout
	;	inbase..
	;	regs
	;	inpbuf = special regs
	;	divstk
	; total size in undosz

	ldx	#25+1	;+1 for divsp
copy
	lda	specreg,x
	sta	inpbuf,x
	dex
	bpl	copy

	lda	virdata+0
	sta	inst-specreg+inpbuf+1
	lda	virdata+1
	sta	inst-specreg+inpbuf+2
	lda	virdata+2
	sta	inst-specreg+inpbuf+3

	lda	inbase
	sta	ioparam
	lda	inbase+1
	sta	ioparam+1
	ldx	undosz
	ldy	undosz+1
	jsr	io_saveundo
	bcs	ok

	jmp	failure
ok
	jmp	ldyfetchnext
	.)

putsavebyte
	; input a = byte
	; input/output phytmp
	; (incremented)
	; preserves y

	.(
	ldx	#0
	sta	(phytmp,x)
	inc	phytmp
	beq	wrap

	rts
wrap
	inc	phytmp+1

	ldx	phytmp+1
	;jmp	evictx
	.)

evictx
	; input x = physical page
	; preserves x, y

	.(
	lda	phy2msb,x
	and	#$7f
	clc
	adc	vtmsb
	sta	vtptr+1
	sty	temp
	ldy	phy2lsb,x
	lda	#0 ; out-of-core
	sta	(vtptr),y
	ldy	temp

	lda	vtsize
	sta	phy2lsb,x
	lda	vtsize+1
	sta	phy2msb,x

	rts
	.)

cleanupmem
	.(
	lda	rtop+0
	sta	count
	sta	temp
	lda	rtop+1
	tax
	asl
	rol	temp
	;clc
	adc	hpbase
	sta	phydata
	lda	temp
	adc	hpbase+1
	sta	phydata+1
loop1
	cpx	renv+1
	bne	no1

	lda	count
	cmp	renv+0
	beq	done1
no1
	cpx	rcho+1
	bne	no2

	lda	count
	cmp	rcho+0
	beq	done1
no2
	inx
	bne	noc1

	inc	count
noc1
	ldy	#0
	lda	#$3f
	sta	(phydata),y
	iny
	sta	(phydata),y
	lda	phydata
	clc
	adc	#2
	sta	phydata
	bcc	loop1

	inc	phydata+1
	jmp	loop1
done1
	lda	raux+0
	sta	count
	sta	temp
	lda	raux+1
	tax
	asl
	rol	temp
	;clc
	adc	auxbase
	sta	phydata
	lda	temp
	adc	auxbase+1
	sta	phydata+1
loop2
	cpx	rtrl+1
	bne	no3

	lda	count
	cmp	rtrl+0
	beq	done2
no3
	inx
	bne	noc2

	inc	count
noc2
	ldy	#0
	lda	#$3f
	sta	(phydata),y
	iny
	sta	(phydata),y
	lda	phydata
	clc
	adc	#2
	sta	phydata
	bcc	loop2

	inc	phydata+1
	jmp	loop2
done2
	ldy	#4
	lda	(inbase),y
	sta	temp
	iny
	lda	(inbase),y
	asl
	rol	temp
	;clc
	adc	rambase
	sta	phydata
	lda	temp
	adc	rambase+1
	sta	phydata+1

	lda	phydata
loop3
	cmp	auxbase
	bne	no4

	lda	phydata+1
	cmp	auxbase+1
	beq	done3
no4
	ldy	#0
	lda	#$3f
	sta	(phydata),y
	iny
	sta	(phydata),y
	lda	phydata
	clc
	adc	#2
	sta	phydata
	bcc	loop3

	inc	phydata+1
	jmp	loop3
done3
	rts
	.)

xorinit
	.(
	lda	chnklsb+CH_INIT
	sec
	sbc	#2
	sta	virdata+2
	lda	chnkssb+CH_INIT
	sbc	#0
	sta	virdata+1
	lda	chnkmsb+CH_INIT
	sbc	#0
	sta	virdata+0
	lda	#2
	jsr	readdata

	lda	databuf
	sta	physize+1
	lda	databuf+1
	sta	physize

	lda	#0
	sta	phytmp
	lda	inbase+1
	sta	phytmp+1
	ldy	inbase

	lda	virdata+2
	sta	phydata
nextpage
	sty	opermsb+4
	ldx	virdata+0
	ldy	virdata+1
	jsr	swapin
	sta	phydata+1
	ldy	opermsb+4
	ldx	#0
xorloop
	lda	(phydata,x)
	eor	(phytmp),y
	sta	(phytmp),y
	iny
	bne	noc1

	inc	phytmp+1
noc1
	dec	physize
	bne	noc2

	dec	physize+1
	bmi	initdone
noc2
	inc	phydata
	bne	xorloop

	inc	virdata+1
	bne	nextpage

	inc	virdata+0
	jmp	nextpage
initdone
fill
	cpy	#<HEAPEND
	bne	noend

	lda	phytmp+1
	cmp	#>HEAPEND
	beq	filldone
noend
	lda	(phytmp),y
	eor	#$3f
	sta	(phytmp),y
	iny
	bne	fill

	inc	phytmp+1
	jmp	fill
filldone
	rts
	.)

op_set_cho
	.(
	jsr	fetchvalue
	lda	opermsb+0
	sta	rcho+0
	lda	operlsb+0
	sta	rcho+1
	jmp	fetchnext
	.)

op_set_cont
	.(
	jsr	fetchcode
	lda	virdata+0
	sta	cont+1
	lda	virdata+1
	sta	cont+2
	lda	virdata+2
	sta	cont+3
	jmp	fetchnext
	.)

op_set_flag
	.(
	jsr	fetchfield0
	sty	`pclsb

	lda	operlsb+1
	pha
	lsr	opermsb+1
	ror
	lsr	opermsb+1
	ror
	lsr	opermsb+1
	ror
	sta	operlsb+1
	jsr	findfield
	pla
	bcs	badtype

	and	#7
	tay
	lda	flagbit,y
	ldy	#0
	ora	(phydata),y
	sta	(phydata),y

	jmp	ldyfetchnext
badtype
	lda	#3
	jmp	error
	.)

op_set_idx
	.(
	jsr	fetchvalderef

	lda	opermsb+0
	cmp	#$e0
	bcs	ext

	sta	ridx+0
	lda	operlsb+0
	sta	ridx+1
	jmp	fetchnext
ext
	and	#$1f
	sta	temp
	lda	operlsb+0
	asl
	rol	temp
	;clc
	adc	hpbase
	sta	phydata+0
	lda	temp
	adc	hpbase+1
	sta	phydata+1

	sty	`pclsb
	ldy	#0
	lda	(phydata),y
	sta	ridx+0
	iny
	lda	(phydata),y
	sta	ridx+1
	jmp	ldyfetchnext
	.)

op_set_parent1
	.(
	bcs	wasbyte

	jsr	fetchvalderef
	jmp	wasval
wasbyte
	jsr	fetchvbyte
wasval
	jsr	fetchvalderef
	jmp	set_parent_common
	.)

op_set_parent2
	.(
	bcs	wasbyte

	jsr	fetchvalderef
	jmp	wasval
wasbyte
	jsr	fetchvbyte
wasval
	jsr	fetchvbyte
	; drop through
	.)

set_parent_common
	.(
	lda	opermsb+0
	bne	notz0

	lda	operlsb+0
	bne	ok0
nonobj
	lda	opermsb+1
	ora	operlsb+1
	bne	badtype

	jmp	fetchnext
badtype
	lda	#3
	jmp	error
notz0
	cmp	#$20
	bcs	nonobj
ok0
	lda	opermsb+1
	cmp	#$20
	bcs	badtype

	sty	`pclsb

	; phydata = &ram[obj]
	lda	opermsb+0
	sta	temp
	lda	operlsb+0
	asl
	rol	temp
	;clc
	adc	rambase
	sta	phydata
	lda	temp
	adc	rambase+1
	sta	phydata+1

	; workptr = &ram[*phydata]
	ldy	#0
	lda	(phydata),y
	sta	temp
	iny
	lda	(phydata),y
	asl
	rol	temp
	;clc
	adc	rambase
	sta	workptr
	lda	temp
	adc	rambase+1
	sta	workptr+1

	;ldy	#FIELD_PARENT*2+1
	lda	(workptr),y
	dey
	ora	(workptr),y
	beq	no_old_parent

	; make dictb point to
	; child field of parent object

	lda	(workptr),y
	sta	temp
	iny
	lda	(workptr),y
	asl
	rol	temp
	;clc
	adc	rambase
	sta	phydata
	lda	temp
	adc	rambase+1
	sta	phydata+1

	dey	; becomes 0
	lda	(phydata),y
	sta	temp
	iny
	lda	(phydata),y
	asl
	rol	temp
	;clc
	adc	rambase
	sta	dictb
	lda	temp
	adc	rambase+1
	sta	dictb+1

	lda	dictb
	clc
	adc	#FIELD_CHILD*2
	sta	dictb
	bcc	noc1

	inc	dictb+1
noc1
	lda	#0
	sta	opermsb+2
	lda	#FIELD_SIBLING*2
	sta	operlsb+2
	lda	opermsb+0
	sta	opermsb+3
	lda	operlsb+0
	sta	operlsb+3
	jsr	unlink

no_old_parent
	ldy	#FIELD_PARENT*2
	lda	opermsb+1
	sta	(workptr),y
	iny
	lda	operlsb+1
	sta	(workptr),y

	ora	opermsb+1
	beq	no_new_parent

	; phydata = &ram[parent]
	lda	opermsb+1
	sta	temp
	lda	operlsb+1
	asl
	rol	temp
	;clc
	adc	rambase
	sta	phydata
	lda	temp
	adc	rambase+1
	sta	phydata+1

	; phydata = &ram[*phydata]
	ldy	#0
	lda	(phydata),y
	sta	temp
	iny
	lda	(phydata),y
	asl
	rol	temp
	;clc
	adc	rambase
	sta	phydata
	lda	temp
	adc	rambase+1
	sta	phydata+1

	ldy	#FIELD_CHILD*2
	lda	(phydata),y
	ldy	#FIELD_SIBLING*2
	sta	(workptr),y
	ldy	#FIELD_CHILD*2+1
	lda	(phydata),y
	ldy	#FIELD_SIBLING*2+1
	sta	(workptr),y

	ldy	#FIELD_CHILD*2
	lda	opermsb+0
	sta	(phydata),y
	iny
	lda	operlsb+0
	sta	(phydata),y

no_new_parent
	jmp	ldyfetchnext
	.)

op_space
	.(
	lda	rcwl
	bne	skip

	lda	#SPC_NO
	adc	#0

	cmp	rspc
	bcc	skip

	sta	rspc
skip
	jmp	fetchnext
	.)

op_space_n
	.(
	jsr	fetchvalderef
	sty	`pclsb
	lda	rcwl
	bne	skip

	lda	opermsb+0
	cmp	#$40
	bne	skip

	lda	operlsb+0
	beq	skip
loop
	lda	#$20
	jsr	vio_putc

	dec	operlsb+0
	bne	loop

	lda	#SPC_SPACE
	sta	rspc
skip
	jmp	ldyfetchnext
	.)

op_split_list
	.(
	jsr	fetchvalderef
	jsr	fetchvalderef
	sty	`pclsb

	lda	#<result
	sta	phytmp
	lda	#>result
	sta	phytmp+1
loop
	lda	operlsb+0
	cmp	operlsb+1
	bne	noteq

	lda	opermsb+0
	cmp	opermsb+1
	beq	done
noteq
	lda	opermsb+0
	and	#$e0
	cmp	#$c0
	bne	done

	lda	opermsb+0
	and	#$1f
	sta	temp
	lda	operlsb+0
	asl
	rol	temp
	;clc
	adc	hpbase
	sta	phydata
	lda	temp
	adc	hpbase+1
	sta	phydata+1
	ldy	#0
	lda	(phydata),y
	pha
	iny
	lda	(phydata),y
	pha
	iny
	lda	(phydata),y
	sta	opermsb+0
	iny
	lda	(phydata),y
	sta	operlsb+0
	jsr	derefoper0y

	jsr	alloc_pair

	ldy	#1
	pla
	sta	(phydata),y
	dey
	pla
	sta	(phydata),y

	lda	rpair+0
	sta	(phytmp),y
	iny
	lda	rpair+1
	sta	(phytmp),y

	lda	phydata
	clc
	adc	#2
	sta	phytmp
	lda	phydata+1
	adc	#0
	sta	phytmp+1
	jmp	loop
done
	ldy	#0
	lda	#$3f
	sta	(phytmp),y
	iny
	lda	#$00
	sta	(phytmp),y

	jmp	ldystorefetchnext
	.)

op_split_word
	.(
	bcc	split

	; join_words

	jsr	fetchvalderef
	sty	`pclsb

	lda	opermsb+0
	and	#$e0
	cmp	#$c0
	bne	fail

	lda	opermsb+0
	and	#$1f
	sta	temp
	lda	operlsb+0
	asl
	rol	temp
	;clc
	adc	hpbase
	sta	phydata
	lda	temp
	adc	hpbase+1
	sta	phydata+1

	ldy	#0
	lda	(phydata),y
	sta	opermsb+1
	iny
	lda	(phydata),y
	sta	operlsb+1
	iny
	lda	(phydata),y
	sta	opermsb+2
	iny
	lda	(phydata),y
	sta	operlsb+2
	ldx	#2
	jsr	dereflastoper
	inx
	jsr	dereflastoper

	lda	opermsb+2
	cmp	#$3f
	bne	nosingle

	lda	opermsb+1
	cmp	#$3e
	bne	nosingle

	sta	result+0
	lda	operlsb+1
	sta	result+1
	jmp	ldystorefetchnext
nosingle
	ldx	#0
	stx	wordend
	jsr	words_to_string
	lda	#0
	sta	count
	lda	wordend
	jsr	parseword_sub
	lda	opermsb+4
	sta	result+0
	lda	operlsb+4
	sta	result+1
	jmp	ldystorefetchnext
fail
	jmp	failure
split
	jsr	fetchvalderef

	lda	#$3f
	sta	result+0
	lda	#0
	sta	result+1
	sty	`pclsb

	lda	opermsb+0
	bmi	neg

	cmp	#$40
	bcs	num

	cmp	#$3e
	beq	char

	bcs	fail

	cmp	#$20
	bcc	fail

	and	#$1f
	tay
	lda	operlsb+0
	jmp	prepend
neg
	cmp	#$e0
	bcc	fail

	and	#$1f
	sta	temp
	lda	operlsb+0
	asl
	rol	temp
	;clc
	adc	hpbase
	sta	phydata
	lda	temp
	adc	hpbase+1
	sta	phydata+1
	ldy	#0
	lda	(phydata),y
	bpl	combined

	sta	result+0
	iny
	lda	(phydata),y
	sta	result+1
	jmp	ldystorefetchnext
num
	and	#$3f
	sta	ioparam+1
	lda	operlsb+0
	sta	ioparam
	jsr	convertnumber
	ldy	#$ff
find0
	iny
	lda	(ioparam),y
	bne	find0

	sty	count
mknum
	jsr	push_pair
	ldy	count
	dey
	lda	(ioparam),y
	and	#$0f
	ldy	#1
	sta	(phydata),y
	dey
	lda	#$40
	sta	(phydata),y
	dec	count
	bne	mknum

	jmp	ldystorefetchnext
char
	jsr	push_pair
	lda	operlsb+0
	sta	(phydata),y
	dey
	lda	opermsb+0
	sta	(phydata),y
	jmp	ldystorefetchnext
combined
	ldy	#3
	lda	(phydata),y
	sta	result+1
	dey
	lda	(phydata),y
	sta	result+0
	dey
	lda	(phydata),y
	tax
	dey
	lda	(phydata),y
	and	#$1f
	tay
	txa
prepend
	jsr	find_dict
chloop
	jsr	push_pair
	ldy	count
	dey
	lda	(phytmp),y
	ldy	#1
	ldx	#$3e
	cmp	#$30
	bcc	nodigit

	cmp	#$3a
	bcs	nodigit

	and	#$0f
	ldx	#$40
nodigit
	sta	(phydata),y
	dey
	txa
	sta	(phydata),y
	dec	count
	bne	chloop

	jmp	ldystorefetchnext
	.)

op_stop
	.(
	lda	rstc
	sta	rcho
	lda	rstc+1
	sta	rcho+1
	jmp	failure
	.)

op_store_byte
	.(
	jsr	fetchfield0
	jsr	fetchvalderef
	sty	`pclsb
	jsr	findfield
	bcs	badtype

	lda	operlsb+2
	ldy	#0
	sta	(phydata),y

	jmp	ldyfetchnext
badtype
	lda	#3
	jmp	error
	.)

op_store_val
	.(
	jsr	fetchfield0
	jsr	fetchvalderef
	sty	`pclsb

	asl	operlsb+1
	rol	opermsb+1
	jsr	findfield
	bcs	nonobj

	ldy	#0
	lda	(phydata),y
	bmi	clear

	jmp	noclear
nonobj
	lda	operlsb+2
	ora	opermsb+2
	bne	badtype

	jmp	ldyfetchnext
badtype
	lda	#3
	jmp	error
clear
	; phytmp = &ram[old] and push

	sta	temp
	iny
	lda	(phydata),y
	asl
	rol	temp
	clc
	adc	rambase
	sta	phytmp
	pha
	lda	temp
	adc	rambase+1
	sta	phytmp+1
	pha

	; if store fails, don't leave
	; a dangling reference

	lda	#0
	sta	(phydata),y
	dey
	sta	(phydata),y

	; physize = ram[old]

	lda	(phytmp),y
	sta	physize+1
	sta	temp
	iny
	lda	(phytmp),y
	sta	physize

	; phydata = &ram[old + size]

	asl
	rol	temp
	;clc
	adc	phytmp
	sta	phydata
	lda	temp
	adc	phytmp+1
	sta	phydata+1

	; LTT -= physize

	ldy	#5
	lda	(inbase),y
	sec
	sbc	physize
	sta	(inbase),y
	pha
	dey
	lda	(inbase),y
	sbc	physize+1
	sta	(inbase),y

	; workptr = &ram[ltt]
	; i.e. end of dest

	sta	temp
	pla
	asl
	rol	temp
	;clc
	adc	rambase
	sta	workptr
	lda	temp
	adc	rambase+1
	sta	workptr+1
moveloop
	lda	phytmp
	cmp	workptr
	lda	phytmp+1
	sbc	workptr+1
	bcs	movedone

	ldy	#0
	lda	(phydata),y
	sta	(phytmp),y
	iny
	lda	(phydata),y
	sta	(phytmp),y
	lda	phydata
	clc
	adc	#2
	sta	phydata
	bcc	noc2

	inc	phydata+1
	clc
noc2
	lda	phytmp
	clc
	adc	#2
	sta	phytmp
	bcc	moveloop

	inc	phytmp+1
	jmp	moveloop
movedone
	; phytmp = &ram[old]

	pla
	sta	phytmp+1
	pla
	sta	phytmp
updloop
	lda	phytmp
	cmp	workptr
	lda	phytmp+1
	sbc	workptr+1
	bcs	upddone

	ldy	#2
	lda	(phytmp),y
	sta	temp
	iny
	lda	(phytmp),y
	asl
	rol	temp
	;clc
	adc	rambase
	sta	phydata
	lda	temp
	adc	rambase+1
	sta	phydata+1

	ldy	#1
	lda	(phydata),y
	sec
	sbc	physize
	sta	(phydata),y
	dey
	lda	(phydata),y
	sbc	physize+1
	sta	(phydata),y

	lda	(phytmp),y
	sta	temp
	iny
	lda	(phytmp),y
	asl
	rol	temp
	;clc
	adc	phytmp
	sta	phytmp
	lda	temp
	adc	phytmp+1
	sta	phytmp+1
	jmp	updloop
upddone
	jsr	findfield
noclear
	lda	opermsb+2
	bmi	complex

	ldy	#0
	sta	(phydata),y
	iny
	lda	operlsb+2
	sta	(phydata),y

	jmp	ldyfetchnext
complex
	; phytmp = &ram[LTT]

	ldy	#4
	lda	(inbase),y
	sta	temp
	iny
	lda	(inbase),y
	asl
	rol	temp
	;clc
	adc	rambase
	sta	phytmp
	lda	temp
	adc	rambase+1
	sta	phytmp+1

	; phytmp = &ram[LTT + 2]

	lda	phytmp
	;clc
	adc	#4
	sta	phytmp
	bcc	noc1

	inc	phytmp+1
noc1
	lda	opermsb+2
	sta	opermsb+4
	lda	operlsb+2
	sta	operlsb+4

	; aux marks end of ram
	lda	auxbase
	sta	physize
	lda	auxbase+1
	sta	physize+1
	jsr	pushlongterm

	jsr	findfield
	ldy	#5
	lda	(inbase),y
	ldy	#1
	sta	(phydata),y
	ldy	#4
	lda	(inbase),y
	ora	#$80
	ldy	#0
	sta	(phydata),y

	; back-link for clearing

	lda	phydata
	sec
	sbc	rambase
	sta	temp
	lda	phydata+1
	sbc	rambase+1
	lsr
	pha
	lda	temp
	ror
	pha

	; phydata = &ram[LTT]

	ldy	#4
	lda	(inbase),y
	sta	temp
	iny
	lda	(inbase),y
	asl
	rol	temp
	;clc
	adc	rambase
	sta	phydata
	lda	temp
	adc	rambase+1
	sta	phydata+1

	lda	phytmp
	sec
	sbc	phydata
	sta	physize
	lda	phytmp+1
	sbc	phydata+1
	lsr
	ror	physize
	sta	physize+1

	ldy	#3
	pla
	sta	(phydata),y
	dey
	pla
	sta	(phydata),y
	dey
	lda	physize
	sta	(phydata),y
	dey
	lda	physize+1
	sta	(phydata),y

	ldy	#5
	lda	(inbase),y
	;clc
	adc	physize
	sta	(inbase),y
	dey
	lda	(inbase),y
	adc	physize+1
	sta	(inbase),y

	jmp	ldyfetchnext
	.)

#if 0
dumplts
	.(
	lda	rambase
	sta	phydata
	lda	rambase+1
	sta	phydata+1
	ldy	#4
	lda	(inbase),y
	sta	physize+1
	iny
	lda	(inbase),y
	sta	physize
loop
	lda	physize
	ora	physize+1
	beq	done

	ldy	#0
	lda	(phydata),y
	sta	$220
	iny
	lda	(phydata),y
	sta	$220

	lda	phydata
	clc
	adc	#2
	sta	phydata
	bcc	noc1

	inc	phydata+1
noc1
	dec	physize
	ldx	physize
	cpx	#$ff
	bne	loop

	dec	physize+1
	jmp	loop
done
	sta	$221
	rts
	.)
#endif

op_store_word
	.(
	jsr	fetchfield0
	jsr	fetchvalue
	sty	`pclsb

	asl	operlsb+1
	rol	opermsb+1
	jsr	findfield
	bcs	badtype

	lda	opermsb+2
	ldy	#0
	sta	(phydata),y
	lda	operlsb+2
	iny
	sta	(phydata),y

	jmp	ldyfetchnext
badtype
	lda	#3
	jmp	error
	.)

op_style
	.(
	php
	jsr	fetchbyte
	sty	`pclsb
	plp
	lda	rcwl
	bne	skip

	lda	stflag
	bmi	skip

	bcs	off

	jsr	syncspace
	jsr	io_mflush
	lda	operlsb+0
	ora	rstyle
	sta	rstyle
	jsr	io_mstyle
	lda	#SPC_SPACE
	sta	rspc
skip
	jmp	ldyfetchnext
off
	jsr	io_mflush
	lda	operlsb+0
	eor	#$ff
	and	rstyle
	sta	rstyle
	jsr	io_mstyle
	jmp	ldyfetchnext
	.)

op_sub_num
	.(
	bcs	wasdec

	jsr	fetchvalnum
	jsr	fetchvalnum

	lda	operlsb+0
	sec
	sbc	operlsb+1
	sta	result+1
	lda	opermsb+0
	sbc	opermsb+1
	bcc	fail

	ora	#$40
ok
	sta	result+0
	jmp	storefetchnext
wasdec
	jsr	fetchvalnum

	lda	operlsb+0
	sec
	sbc	#1
	sta	result+1
	lda	opermsb+0
	sbc	#0
	cmp	#$40
	bcs	ok
fail
	jmp	failure
	.)

op_sub_raw
	.(
	bcs	wasdec

	jsr	fetchvalue
	jsr	fetchvalue
	lda	operlsb+0
	sec
	sbc	operlsb+1
	sta	result+1
	lda	opermsb+0
	sbc	opermsb+1
common
	sta	result+0
	jmp	storefetchnext
wasdec
	jsr	fetchvalue
	lda	operlsb+0
	sec
	sbc	#1
	sta	result+1
	lda	opermsb+0
	sbc	#0
	jmp	common
	.)

op_trace
	.(
	lda	rtrace
	bpl	skip

	lda	stflag
	bmi	skip

	jsr	fetchstring
	sty	`pclsb
	jsr	vio_line
	lda	#$ff
	sta	quot
	jsr	printstring
	lda	#'('
	jsr	vio_putc
	ldy	`pclsb
	jsr	fetchstring
	sty	`pclsb
	inc	quot
	jsr	printstring
	lda	#')'
	jsr	vio_putc
	lda	#$20
	jsr	vio_putc
	ldy	`pclsb
	dec	quot
	jsr	fetchstring
	sty	`pclsb
	jsr	printstring
	lda	#$3a
	jsr	vio_putc
	ldy	`pclsb
	ldx	#0
	jsr	fetchword
	sty	`pclsb
	lda	opermsb+0
	sta	ioparam+1
	lda	operlsb+0
	sta	ioparam
	jsr	printnumber
	lda	#SPC_AUTO
	sta	rspc
	jsr	vio_line
	jmp	ldyfetchnext
skip
	jsr	fetchstring
	jsr	fetchstring
	jsr	fetchstring
	jsr	fetchword
	jmp	fetchnext
	.)

op_unlink
	.(
	jsr	fetchfield0
	jsr	fetchindex
	jsr	fetchvalderef
	sty	`pclsb

	asl	operlsb+1
	rol	opermsb+1
	jsr	findfield
	bcs	skip

	asl	operlsb+2
	rol	opermsb+2
	lda	phydata
	sta	dictb
	lda	phydata+1
	sta	dictb+1
	jsr	unlink
skip
	jmp	ldyfetchnext
	.)

op_vm_info
	.(
	jsr	fetchbyte
	sty	`pclsb

	ldx	#0
	stx	result+0
	stx	result+1

	lda	operlsb+0
	bit	flagbit+1	; 40
	beq	defzero

	jmp	defnull
defzero
	ldx	#$40
	stx	result+0

	cmp	#$00
	bne	notheap

	lda	heapsz+1
	sta	physize
	lda	heapsz
	sta	physize+1

	ldx	hpbase
	ldy	hpbase+1
usedcount
	stx	phydata
	sty	phydata+1

	lda	physize
	asl
	rol	physize+1
	;clc
	adc	phydata
	sta	physize
	lda	physize+1
	adc	phydata+1
	sta	physize+1

	lda	phydata
cloop
	cmp	physize
	lda	phydata+1
	sbc	physize+1
	bcs	cdone

	lda	#$3f
	ldy	#0
	cmp	(phydata),y
	bne	doinc

	iny
	cmp	(phydata),y
	beq	noinc
doinc
	inc	result+1
	bne	noinc

	inc	result+0
noinc
	lda	phydata
	clc
	adc	#2
	sta	phydata
	bcc	cloop

	inc	phydata+1
	jmp	cloop
notheap
	cmp	#$01
	bne	notaux

	lda	auxsz+1
	sta	physize
	lda	auxsz
	sta	physize+1

	ldx	auxbase
	ldy	auxbase+1
	jmp	usedcount
notaux
	cmp	#$02
	bne	cdone

	lda	ramsz+1
	sec
	ldy	#3
	sbc	(inbase),y
	sta	physize
	lda	ramsz
	dey
	sbc	(inbase),y
	sta	physize+1

	lda	(inbase),y
	sta	temp
	iny
	lda	(inbase),y
	asl
	rol	temp
	;clc
	adc	rambase
	tax
	lda	temp
	adc	rambase+1
	tay
	jmp	usedcount
defnull
#if HAVE_QUIT
	cmp	#$43
	beq	yes
#endif
#if HAVE_STATUS
	cmp	#$60
	beq	yes
#endif
	cmp	#$40
	bne	cdone

	jsr	io_undosupp
	bcc	cdone
yes
	inc	result+1
cdone
	jmp	ldystorefetchnext
	.)

N_EXT0	= $12
ext0_lsb
	.byt	<ext0_quit	; 00
	.byt	<ext0_restart	; 01
	.byt	<ext0_restore	; 02
	.byt	<ext0_undo	; 03
	.byt	<ext0_unstyle	; 04
	.byt	<ext0_serial	; 05
	.byt	<ext0_clear	; 06
	.byt	<ext0_clear_all	; 07
	.byt	<ext0_scrpt_on	; 08
	.byt	<ext0_scrpt_off	; 09
	.byt	<ext0_trace_on	; 0a
	.byt	<ext0_trace_off	; 0b
	.byt	<ext0_inc_cwl	; 0c
	.byt	<ext0_dec_cwl	; 0d
	.byt	<ext0_upper	; 0e
	.byt	<ext0_clr_links	; 0f
	.byt	<ext0_clr_old	; 10
	.byt	<ext0_clr_div	; 11
ext0_msb
	.byt	>ext0_quit	; 00
	.byt	>ext0_restart	; 01
	.byt	>ext0_restore	; 02
	.byt	>ext0_undo	; 03
	.byt	>ext0_unstyle	; 04
	.byt	>ext0_serial	; 05
	.byt	>ext0_clear	; 06
	.byt	>ext0_clear_all	; 07
	.byt	>ext0_scrpt_on	; 08
	.byt	>ext0_scrpt_off	; 09
	.byt	>ext0_trace_on	; 0a
	.byt	>ext0_trace_off	; 0b
	.byt	>ext0_inc_cwl	; 0c
	.byt	>ext0_dec_cwl	; 0d
	.byt	>ext0_upper	; 0e
	.byt	>ext0_clr_links	; 0f
	.byt	>ext0_clr_old	; 10
	.byt	>ext0_clr_div	; 11

ext0_quit
	jsr	io_mflush
	jmp	io_quit

ext0_restart
	jsr	io_mflush
	jsr	io_restart
	jsr	restartgame
	jmp	fetchinst

ext0_restore
	.(
	jsr	io_load
	bcc	err

	lda	#<SAVEADDR+8
	clc
	adc	SAVEADDR+7
	sta	physize
	lda	#>SAVEADDR+8
	adc	SAVEADDR+6
	sta	physize+1

	tax
	lda	physize
	bne	unmap1
unmap
	dex
unmap1
	jsr	evictx
	cpx	#>SAVEADDR
	bne	unmap

	ldy	#6
hloop1
	lda	SAVEADDR+12,y
	cmp	head000,y
	bne	err

	dey
	bpl	hloop1

	ldy	#0
hloop2
	lda	SAVEADDR+12+7,y
	cmp	(hdbase),y
	bne	wronggame

	iny
	cpy	SAVEADDR+12+7
	bne	hloop2

	lda	#<SAVEADDR+12
	sta	phytmp
	lda	#>SAVEADDR+12
	sta	phytmp+1
chunkloop
	lda	phytmp
	cmp	physize
	lda	phytmp+1
	sbc	physize+1
	bcc	dochunk

	jsr	xorinit

	jsr	update_envbase
	jmp	fetchinst

wronggame
	lda	#<txt_wronggame
	sta	phydata
	lda	#>txt_wronggame
	sta	phydata+1
	jsr	puts
	lda	#SPC_AUTO
	sta	rspc
	jsr	vio_line
err
	jmp	refetchnext

nextchunk
	ldy	#6
	lda	(phytmp),y
	tax
	iny
	lda	(phytmp),y
	clc
	adc	#9
	and	#$fe
	bcc	noc1

	inx
	clc
noc1
	adc	phytmp
	sta	phytmp
	txa
	adc	phytmp+1
	sta	phytmp+1
	jmp	chunkloop

dochunk
	ldy	#3
tagcmp1
	lda	(phytmp),y
	cmp	data0000,y
	bne	notdata
	dey
	bpl	tagcmp1

	lda	phytmp
	clc
	adc	#8
	sta	phydata
	lda	phytmp+1
	adc	#0
	sta	phydata+1

	ldy	#7
	lda	(phytmp),y
	clc
	adc	phydata
	sta	dictb
	dey
	lda	(phytmp),y
	adc	phydata+1
	sta	dictb+1

	lda	inbase
	sta	workptr
	lda	inbase+1
	sta	workptr+1

dataloop
	lda	phydata
	cmp	dictb
	lda	phydata+1
	sbc	dictb+1
	bcs	nextchunk

	ldy	#0
	ldx	#1
	lda	(phydata),y
	bne	norle

	inc	phydata
	bne	noc5

	inc	phydata+1
noc5
	lda	(phydata),y
	tax
	inx
	tya
norle
rleloop
	sta	(workptr),y
	iny
	dex
	bne	rleloop

	inc	phydata
	bne	noc4

	inc	phydata+1
noc4
	dey
	tya
	sec
	adc	workptr
	sta	workptr
	bcc	dataloop

	inc	workptr+1
	jmp	dataloop
notdata
	ldy	#3
tagcmp2
	lda	(phytmp),y
	cmp	regs000,y
	bne	notregs
	dey
	bpl	tagcmp2

	ldy	#8
regloop
	lda	(phytmp),y
	sta	regs-8,y
	iny
	cpy	#128+8
	bne	regloop

	tya
	clc
	adc	phytmp
	sta	phydata
	lda	phytmp+1
	adc	#0
	sta	phydata+1
	ldy	#0
sploop
	lda	(phydata),y
	sta	specreg,y
	iny
	cpy	#26
	bne	sploop

	iny
	lda	(phydata),y
	asl
	sta	divsp
	beq	divdone

	ldx	#0
divlp
	iny
	lda	(phydata),y
	sta	divstk,x
	inx
	cpx	divsp
	bcc	divlp
divdone
notregs
	jmp	nextchunk

txt_wronggame
	.asc	"Savefile doesn't match story.",0
	.)

ext0_undo
	.(
	lda	inbase
	sta	ioparam
	lda	inbase+1
	sta	ioparam+1
	ldx	undosz
	ldy	undosz+1
	jsr	io_loadundo

	cmp	#1
	beq	fail

	bcs	err

	ldx	#25+1
copy
	lda	inpbuf,x
	sta	specreg,x
	dex
	bpl	copy

	jsr	update_envbase
	jmp	fetchinst
err
	jmp	ldyfetchnext
fail
	jmp	failure
	.)

ext0_unstyle
	.(
	lda	rcwl
	bne	skip

	jsr	unstyle
skip
	jmp	ldyfetchnext
	.)

ext0_serial
	.(
	lda	rcwl
	bne	skip

	jsr	syncspace
	ldy	#1+6
loop
	sty	count
	lda	(hdbase),y
	jsr	vio_putc
	ldy	count
	iny
	cpy	#1+6+6
	bne	loop

	lda	#SPC_AUTO
	sta	rspc
skip
	jmp	ldyfetchnext
	.)

ext0_clear
	.(
	lda	rcwl
	bne	skip

	lda	stflag
	ora	nspan
	beq	doclear
err
	lda	#7
	jmp	error

+ext0_clear_all
	lda	rcwl
	bne	skip

	lda	stflag
	ora	nspan
	bne	err

	jsr	io_mclear ; more-prompt
	lda	#0
	jsr	io_sprepare
doclear
	jsr	io_mclear
	lda	#SPC_PAR
	sta	rspc
skip
	jmp	ldyfetchnext
	.)

ext0_trace_on
	lda	#$ff
	sta	rtrace
ext0_scrpt_off
ext0_clr_links
ext0_clr_old
ext0_clr_div
	jmp	ldyfetchnext

ext0_trace_off
	lda	#0
	sta	rtrace
	jmp	ldyfetchnext

ext0_inc_cwl
	inc	rcwl
	jmp	ldyfetchnext

ext0_dec_cwl
	dec	rcwl
	jmp	ldyfetchnext

ext0_upper
	lda	#$ff
	sta	rupper
	jmp	ldyfetchnext

unify
	; input oper4, oper5
	; returns on success
	; longjumps on failure

	.(
again_a
	jsr	derefoper4y
again_b
	jsr	derefoper5y

	lda	opermsb+4
	and	#$e0
	cmp	#$80
	bne	not_a_ref

	jmp	a_ref
not_a_ref
	lda	opermsb+5
	and	#$e0
	cmp	#$80
	bne	not_b_ref

	jmp	b_ref
not_b_ref
	; we have two bound values

	cmp	#$e0
	bne	not_b_ext

	lda	opermsb+4
	cmp	#$e0
	bcs	both_ext

	; b is extdict, a is not
	lda	opermsb+5
	and	#$1f
	sta	phydata+1
	lda	operlsb+5
	asl
	rol	phydata+1
	;clc
	adc	hpbase
	sta	phydata
	lda	phydata+1
	adc	hpbase+1
	sta	phydata+1
	ldy	#0
	lda	(phydata),y
	sta	opermsb+5
	iny
	lda	(phydata),y
	sta	operlsb+5
	jmp	again_b

both_ext
	; a and b are extdict
	lda	opermsb+5
	and	#$1f
	sta	phydata+1
	lda	operlsb+5
	asl
	rol	phydata+1
	;clc
	adc	hpbase
	sta	phydata
	lda	phydata+1
	adc	hpbase+1
	sta	phydata+1
	ldy	#0
	lda	(phydata),y
	sta	opermsb+5
	iny
	lda	(phydata),y
	sta	operlsb+5
	; drop through

a_ext
	; a is extdict, b is not
	lda	opermsb+4
	and	#$1f
	sta	phydata+1
	lda	operlsb+4
	asl
	rol	phydata+1
	;clc
	adc	hpbase
	sta	phydata
	lda	phydata+1
	adc	hpbase+1
	sta	phydata+1
	ldy	#0
	lda	(phydata),y
	sta	opermsb+4
	iny
	lda	(phydata),y
	sta	operlsb+4
	jmp	again_a

not_b_ext
	lda	opermsb+4
	cmp	#$e0
	bcs	a_ext

	; neither a nor b is extdict

	lda	opermsb+4
	cmp	opermsb+5
	bne	noteq

	lda	operlsb+4
	cmp	operlsb+5
	bne	noteq

	rts
noteq
	lda	opermsb+4
	cmp	#$c0
	bcc	nolist

	lda	opermsb+5
	cmp	#$c0
	bcc	nolist

	; both are lists

	and	#$9f
	sta	opermsb+5
	pha
	lda	operlsb+5
	pha
	lda	opermsb+4
	and	#$9f
	sta	opermsb+4
	pha
	lda	operlsb+4
	pha

	jsr	unify

	pla
	clc
	adc	#1
	sta	operlsb+4
	pla
	adc	#0
	sta	opermsb+4
	pla
	clc
	adc	#1
	sta	operlsb+5
	pla
	adc	#0
	sta	opermsb+5
	jmp	again_a
nolist
	jmp	failure
a_ref
	lda	opermsb+5
	and	#$e0
	cmp	#$80
	beq	ab_ref
a_ref2
	; bind a to value b
	jsr	alloc_trail
	ldy	#1
	lda	operlsb+4
	sta	(phydata),y
	dey
	lda	opermsb+4
	and	#$1f
	sta	(phydata),y

	sta	phydata+1
	lda	operlsb+4
	asl
	rol	phydata+1
	;clc
	adc	hpbase
	sta	phydata
	lda	phydata+1
	adc	hpbase+1
	sta	phydata+1

	lda	opermsb+5
	sta	(phydata),y
	iny
	lda	operlsb+5
	sta	(phydata),y
ab_eq
	rts
ab_ref
	; bind a and b together
	lda	operlsb+4
	cmp	operlsb+5
	bne	ab_noteq

	lda	opermsb+4
	eor	opermsb+5
	beq	ab_eq

	;sec
ab_noteq
	lda	opermsb+4
	sbc	opermsb+5
	bcs	a_ref2
b_ref
	; bind b to value a
	jsr	alloc_trail
	ldy	#1
	lda	operlsb+5
	sta	(phydata),y
	dey
	lda	opermsb+5
	and	#$1f
	sta	(phydata),y

	sta	phydata+1
	lda	operlsb+5
	asl
	rol	phydata+1
	;clc
	adc	hpbase
	sta	phydata
	lda	phydata+1
	adc	hpbase+1
	sta	phydata+1

	lda	opermsb+4
	sta	(phydata),y
	iny
	lda	operlsb+4
	sta	(phydata),y
	rts
	.)

would_unify
	; input oper4, oper5
	; clobbers them
	; clobbers phydata
	; output c = would

	.(
again_a
	jsr	derefoper4y
again_b
	jsr	derefoper5y

	lda	opermsb+4
	and	#$e0
	cmp	#$80
	bne	not_a_ref
would
	sec
	rts
not_a_ref
	lda	opermsb+5
	and	#$e0
	cmp	#$80
	beq	would

	; we have two bound values

	cmp	#$e0
	bne	not_b_ext

	lda	opermsb+4
	cmp	#$e0
	bcs	both_ext

	; b is extdict, a is not
	lda	opermsb+5
	and	#$1f
	sta	phydata+1
	lda	operlsb+5
	asl
	rol	phydata+1
	;clc
	adc	hpbase
	sta	phydata
	lda	phydata+1
	adc	hpbase+1
	sta	phydata+1
	ldy	#0
	lda	(phydata),y
	sta	opermsb+5
	iny
	lda	(phydata),y
	sta	operlsb+5
	jmp	again_b

both_ext
	; a and b are extdict
	lda	opermsb+5
	and	#$1f
	sta	phydata+1
	lda	operlsb+5
	asl
	rol	phydata+1
	;clc
	adc	hpbase
	sta	phydata
	lda	phydata+1
	adc	hpbase+1
	sta	phydata+1
	ldy	#0
	lda	(phydata),y
	sta	opermsb+5
	iny
	lda	(phydata),y
	sta	operlsb+5
	; drop through

a_ext
	; a is extdict, b is not
	lda	opermsb+4
	and	#$1f
	sta	phydata+1
	lda	operlsb+4
	asl
	rol	phydata+1
	;clc
	adc	hpbase
	sta	phydata
	lda	phydata+1
	adc	hpbase+1
	sta	phydata+1
	ldy	#0
	lda	(phydata),y
	sta	opermsb+4
	iny
	lda	(phydata),y
	sta	operlsb+4
	jmp	again_a

not_b_ext
	lda	opermsb+4
	cmp	#$e0
	bcs	a_ext

	; neither a nor b is extdict

	lda	opermsb+4
	cmp	opermsb+5
	bne	noteq

	lda	operlsb+4
	cmp	operlsb+5
	bne	noteq

	sec
nolist
	rts
noteq
	lda	opermsb+4
	cmp	#$c0
	bcc	nolist

	lda	opermsb+5
	cmp	#$c0
	bcc	nolist

	; both are lists

	and	#$9f
	sta	opermsb+5
	pha
	lda	operlsb+5
	pha
	lda	opermsb+4
	and	#$9f
	sta	opermsb+4
	pha
	lda	operlsb+4
	pha
	jsr	would_unify
	bcc	wouldnt

	pla
	clc
	adc	#1
	sta	operlsb+4
	pla
	adc	#0
	sta	opermsb+4
	pla
	clc
	adc	#1
	sta	operlsb+5
	pla
	adc	#0
	sta	opermsb+5
	jmp	again_a
wouldnt
	pla
	pla
	pla
	pla
	rts
	.)

update_envbase
	; input renv, hpbase
	; output envbase
	; clobbers phydata

	.(
	lda	renv+0
	sta	phydata+1
	lda	renv+1
	asl
	rol	phydata+1
	;clc
	adc	hpbase
	sta	phydata
	lda	phydata+1
	adc	hpbase+1
	sta	phydata+1
	lda	phydata
	clc
	adc	#4*2
	sta	envbase
	lda	phydata+1
	adc	#0
	sta	envbase+1
	rts
	.)

alloc_trail
	.(
	lda	raux+1
	cmp	rtrl+1
	lda	raux+0
	sbc	rtrl+0
	bcs	auxfull

	lda	rtrl+1
	;clc
	sbc	#0
	sta	rtrl+1
	bcs	noc1

	dec	rtrl+0
noc1
	lda	rtrl+0
	sta	phydata+1
	lda	rtrl+1
	asl
	rol	phydata+1
	;clc
	adc	auxbase
	sta	phydata
	lda	phydata+1
	adc	auxbase+1
	sta	phydata+1
	rts
auxfull
	lda	#2
	jmp	error
	.)

readfield
	; input oper 0 = deref'd obj
	; input oper 1 = word index
	; output result = raw data
	; clobbers y, phydata, oper1

	.(
	asl	operlsb+1
	rol	opermsb+1
	jsr	findfield
	bcs	noobj

	ldy	#1
	lda	(phydata),y
	sta	result+1
	dey
	lda	(phydata),y
	sta	result+0
	rts
noobj
	lda	#0
	sta	result+0
	sta	result+1
	rts
	.)

findfield
	; input oper 0 = deref'd obj
	; input oper 1 = byte offset
	; output phydata = ram addr
	; output c = invalid obj
	; clobbers y

	.(
	lda	opermsb+0
	cmp	#$20
	bcs	done

	; phydata = &ram[obj]
	sta	temp
	lda	operlsb+0
	asl
	rol	temp
	;clc
	adc	rambase
	sta	phydata
	lda	temp
	adc	rambase+1
	sta	phydata+1

	; phydata = &ram[*phydata]
	ldy	#0
	lda	(phydata),y
	sta	temp
	iny
	lda	(phydata),y
	asl
	rol	temp
	;clc
	adc	rambase
	sta	phydata
	lda	temp
	adc	rambase+1
	sta	phydata+1

	lda	phydata
	;clc
	adc	operlsb+1
	sta	phydata
	lda	phydata+1
	adc	opermsb+1
	sta	phydata+1
	;clc
done
	rts
	.)

unlink
	; input dictb = root ptr addr
	; input oper 2 = sibling offset
	; input oper 3 = deref'd key
	; preserves oper 0, oper 1
	; preserves oper 4
	; clobbers dictb, phydata
	; clobbers temp

	.(
loop
	ldy	#0
	lda	(dictb),y
	iny
	ora	(dictb),y
	beq	done

	lda	(dictb),y
	cmp	operlsb+3
	bne	nomatch

	dey
	lda	opermsb+3
	cmp	(dictb),y
	bne	nomatch

	; write tail at dictb

	; phydata = &ram[key]
	sta	temp
	lda	operlsb+3
	asl
	rol	temp
	;clc
	adc	rambase
	sta	phydata
	lda	temp
	adc	rambase+1
	sta	phydata+1

	; phydata = &ram[*phydata]
	lda	(phydata),y
	sta	temp
	iny
	lda	(phydata),y
	asl
	rol	temp
	;clc
	adc	rambase
	sta	phydata
	lda	temp
	adc	rambase+1
	sta	phydata+1

	lda	phydata
	clc
	adc	operlsb+2
	sta	phydata
	lda	phydata+1
	adc	opermsb+2
	sta	phydata+1

	lda	(phydata),y
	sta	(dictb),y
	dey
	lda	(phydata),y
	sta	(dictb),y
done
	rts
nomatch
	; phydata = &ram[*dictb]
	ldy	#0
	lda	(dictb),y
	sta	temp
	iny
	lda	(dictb),y
	asl
	rol	temp
	;clc
	adc	rambase
	sta	phydata
	lda	temp
	adc	rambase+1
	sta	phydata+1

	; phydata = &ram[*phydata]
	dey
	lda	(phydata),y
	sta	temp
	iny
	lda	(phydata),y
	asl
	rol	temp
	;clc
	adc	rambase
	sta	phydata
	lda	temp
	adc	rambase+1
	sta	phydata+1

	lda	phydata
	clc
	adc	operlsb+2
	sta	dictb
	lda	phydata+1
	adc	opermsb+2
	sta	dictb+1
	jmp	loop
	.)

mul16
	; input quot, denom
	; output numer
	; clobbers quot, denom, y

	.(
	lda	#0
	sta	numer
	sta	numer+1

	ldy	#16
loop
	lsr	denom+1
	ror	denom
	bcc	nobit

	lda	numer
	clc
	adc	quot
	sta	numer
	lda	numer+1
	adc	quot+1
	sta	numer+1
nobit
	asl	quot
	rol	quot+1
	dey
	bne	loop

	rts
	.)

div16
	; input numer, denom
	; output quot, remain
	; clobbers count
	; gets stuck if denom is zero

	.(
	lda	#0
	sta	count
	sta	quot
	sta	quot+1
	lda	numer
	sta	remain
	lda	numer+1
	sta	remain+1
preloop
	bit	denom+1
	bmi	predone

	asl	denom
	rol	denom+1
	inc	count
	jmp	preloop
loop
	lsr	denom+1
	ror	denom
predone
	lda	remain
	cmp	denom
	lda	remain+1
	sbc	denom+1
	bcc	nofit

	lda	remain
	;sec
	sbc	denom
	sta	remain
	lda	remain+1
	sbc	denom+1
	sta	remain+1
	;sec
nofit
	rol	quot
	rol	quot+1
	dec	count
	bpl	loop

	rts
	.)

flagbit
	.byt	$80
	.byt	$40
	.byt	$20
	.byt	$10
	.byt	$08
	.byt	$04
	.byt	$02
	.byt	$01

form0000aasv
	.byt	"FORM",0,0,0,0,"AASV"
head000
	.byt	"HEAD",0,0,0
data0000
	.byt	"DATA",0,0,0,0
regs000
	.byt	"REGS",0,0,0

unpadded_footprint = *

	PAGE
optable
	.word	fetchnext	; 00
	.word	op_fail		; 01
	.word	op_set_cont	; 02
	.word	op_proceed	; 03
	.word	op_jmp		; 04
	.word	op_jmp_multi	; 05
	.word	op_jmp_simple	; 06
	.word	op_jmp_tail	; 07
	.word	op_push_env	; 08
	.word	op_pop_env	; 09
	.word	op_push_choice	; 0a
	.word	op_pop_choice	; 0b
	.word	op_p_p_choice	; 0c
	.word	op_cut_choice	; 0d
	.word	op_get_cho	; 0e
	.word	op_set_cho	; 0f
	.word	op_assign	; 10
	.word	op_make_var	; 11
	.word	op_make_pair1	; 12
	.word	op_make_pair2	; 13
	.word	op_aux_push_val	; 14
	.word	op_aux_push_raw	; 15
	.word	op_bad		; 16
	.word	op_aux_pop_list	; 17
	.word	op_aux_pop_chk	; 18
	.word	op_aux_pop_mtch	; 19
	.word	op_bad		; 1a
	.word	op_split_list	; 1b
	.word	op_stop		; 1c
	.word	op_push_stop	; 1d
	.word	op_pop_stop	; 1e
	.word	op_split_word	; 1f
	.word	op_load_word	; 20
	.word	op_load_byte	; 21
	.word	op_load_val	; 22
	.word	op_bad		; 23
	.word	op_store_word	; 24
	.word	op_store_byte	; 25
	.word	op_store_val	; 26
	.word	op_bad		; 27
	.word	op_set_flag	; 28
	.word	op_reset_flag	; 29
	.word	op_bad		; 2a
	.word	op_bad		; 2b
	.word	op_bad		; 2c
	.word	op_unlink	; 2d
	.word	op_set_parent1	; 2e
	.word	op_set_parent2	; 2f
	.word	op_if_raw_eq	; 30
	.word	op_if_bound	; 31
	.word	op_if_empty	; 32
	.word	op_if_num	; 33
	.word	op_if_pair	; 34
	.word	op_if_obj	; 35
	.word	op_if_word	; 36
	.word	op_if_unify	; 37
	.word	op_if_gt	; 38
	.word	op_if_eq	; 39
	.word	op_if_mem_eq_1	; 3a
	.word	op_if_flag	; 3b
	.word	op_if_cwl	; 3c
	.word	op_if_mem_eq_2	; 3d
	.word	op_bad		; 3e
	.word	op_bad		; 3f
	.word	op_if_raw_eq	; 40
	.word	op_if_bound	; 41
	.word	op_if_empty	; 42
	.word	op_if_num	; 43
	.word	op_if_pair	; 44
	.word	op_if_obj	; 45
	.word	op_if_word	; 46
	.word	op_if_unify	; 47
	.word	op_if_gt	; 48
	.word	op_if_eq	; 49
	.word	op_if_mem_eq_1	; 4a
	.word	op_if_flag	; 4b
	.word	op_if_cwl	; 4c
	.word	op_if_mem_eq_2	; 4d
	.word	op_bad		; 4e
	.word	op_bad		; 4f
	.word	op_add_raw	; 50
	.word	op_sub_raw	; 51
	.word	op_rand_raw	; 52
	.word	op_bad		; 53
	.word	op_bad		; 54
	.word	op_bad		; 55
	.word	op_bad		; 56
	.word	op_bad		; 57
	.word	op_add_num	; 58
	.word	op_sub_num	; 59
	.word	op_rand_num	; 5a
	.word	op_mul_num	; 5b
	.word	op_div_num	; 5c
	.word	op_mod_num	; 5d
	.word	op_bad		; 5e
	.word	op_bad		; 5f
	.word	op_print_str_a	; 60
	.word	op_print_str_n	; 61
	.word	op_space	; 62
	.word	op_line_par	; 63
	.word	op_space_n	; 64
	.word	op_print_val	; 65
	.word	op_en_lv_div	; 66
	.word	op_en_lv_st	; 67
	.word	op_link		; 68
	.word	op_link		; 69
	.word	op_selflink	; 6a
	.word	op_style	; 6b
	.word	op_embed	; 6c
	.word	op_progress	; 6d
	.word	op_en_lv_span	; 6e
	.word	op_en_st_1	; 6f
	.word	op_ext0		; 70
	.word	op_bad		; 71
	.word	op_save		; 72
	.word	op_get_input	; 73
	.word	op_vm_info	; 74
	.word	op_bad		; 75
	.word	op_bad		; 76
	.word	op_bad		; 77
	.word	op_set_idx	; 78
	.word	op_chk_eq	; 79
	.word	op_chk_gt_eq	; 7a
	.word	op_chk_gt	; 7b
	.word	op_chk_wordmap	; 7c
	.word	op_chk_eq_2	; 7d
	.word	op_bad		; 7e
	.word	op_trace	; 7f

engine_footprint = *-engine_firstaddr

;======================================
initsegment
;======================================

	; Anything past this point gets
	; overwritten by initengine5

initengine0
	.(
	lda	#DEFWIDTH
	sta	screenw
	lda	#0
	sta	stflag
	rts
	.)

initprogressbar
	.(
	stx	operlsb+0
	sty	opermsb+0
	lda	ioparam
	sta	operlsb+1
	lda	ioparam+1
	sta	opermsb+1
	jmp	progressbar
	.)

initengine1
	; Set up internal variables.
	; Load first page of storyfile.
	; Compute RAM requirements.

	.(
	lda	#<HEAPEND
	sta	freeptr
	lda	#>HEAPEND
	sta	freeptr+1

	.(
	ldy	#zpcodelen-1
loop
	lda	zpcode,y
	sta	zporg,y
	dey
	bpl	loop
	.)

	lda	#0
	sta	ioparam
	sta	ioparam+1
	ldx	#SAFEPG
	stx	firstpg
	lda	#SAFEPG+48
	sta	endpg

	jsr	io_readpage

	lda	initdata+7
	clc
	adc	#8
	sta	filesz+2
	lda	initdata+6
	adc	#0
	sta	filesz+1
	lda	initdata+5
	adc	#0
	sta	filesz+0

	.(
	ldx	#5
szloop
	lda	initdata+12+8+16,x
	sta	heapsz,x
	dex
	bpl	szloop
	.)

	.(
	ldx	heapsz+1
	ldy	heapsz
	jsr	allocwords
	stx	hpbase
	sty	hpbase+1

	ldx	auxsz+1
	ldy	auxsz
	jsr	allocwords
	stx	auxbase
	sty	auxbase+1

	ldx	ramsz+1
	ldy	ramsz
	jsr	allocwords
	stx	rambase
	sty	rambase+1

	ldx	#3
	ldy	#0
	jsr	allocwords
	stx	inbase
	sty	inbase+1

	lda	#<UNDOEND
	sec
	sbc	freeptr
	sta	undosz
	lda	#>UNDOEND
	sbc	freeptr+1
	sta	undosz+1
	.)

	.(
	; for each virtual page, msb of
	; where it is mapped (0 if not)

	lda	filesz+2
	cmp	#1
	lda	filesz+1
	adc	#0
	sta	vtsize
	lda	filesz+0
	adc	#0
	sta	vtsize+1

	lda	freeptr
	clc		; one extra
	sbc	vtsize
	sta	freeptr
	sta	vtptr
	lda	freeptr+1
	sbc	vtsize+1
	sta	freeptr+1
	sta	vtmsb

	.(
	sta	vtptr+1
	ldy	#0
	tya

	ldx	vtsize+1
	beq	donemsb
loopmsb
	sta	(vtptr),y
	iny
	bne	loopmsb

	inc	vtptr+1
	dex
	bne	loopmsb
donemsb
	cpy	vtsize
	beq	donelsb
looplsb
	sta	(vtptr),y
	iny
	cpy	vtsize
	bne	looplsb
donelsb
	.)

	.(
	tay
loop
	lda	vtsize
	sta	phy2lsb,y
	lda	vtsize+1
	sta	phy2msb,y
	iny
	cpy	#$fa
	bne	loop
	.)

	lda	vtmsb
	sta	vtptr+1
	ldy	#0
	lda	#SAFEPG
	sta	(vtptr),y
	sta	evict
	inc	evict

	lda	#0
	sta	phy2msb+SAFEPG
	sta	phy2lsb+SAFEPG
	.)

	.(
	lda	initdata+12+7
	clc
	adc	#2
	lsr
	tax
	ldy	#0
	jsr	allocwords
	stx	hdbase
	sty	hdbase+1

	ldy	initdata+12+7
copy
	lda	initdata+12+7,y
	sta	(hdbase),y
	dey
	bpl	copy
	.)

	rts
	.)

initengine2
	; Skim file to locate chunks.

	.(
	ldx	#CH_N-1
	lda	#0
loop
	sta	chnklsb,x
	sta	chnkssb,x
	sta	chnkmsb,x
	dex
	bpl	loop
	.)

	.(
	lda	#0
	sta	virdata+0
	sta	virdata+1
	lda	#12
	sta	virdata+2
fileloop
	lda	virdata+2
	cmp	filesz+2
	lda	virdata+1
	sbc	filesz+1
	lda	virdata+0
	sbc	filesz+0
	bcs	filedone

	lda	#8
	jsr	readdata

	ldx	#CH_N-1
chkloop
	lda	chunknames+0*CH_N,x
	cmp	databuf+0
	bne	chknext

	lda	chunknames+1*CH_N,x
	cmp	databuf+1
	bne	chknext

	lda	chunknames+2*CH_N,x
	cmp	databuf+2
	bne	chknext

	lda	chunknames+3*CH_N,x
	cmp	databuf+3
	bne	chknext

	lda	virdata+2
	sta	chnklsb,x
	lda	virdata+1
	sta	chnkssb,x
	lda	virdata+0
	sta	chnkmsb,x
	jmp	filenext
chknext
	dex
	bpl	chkloop
filenext
	lda	databuf+7
	clc
	adc	#1
	and	#$fe
	sta	databuf+7
	bcc	noc1

	inc	databuf+6
	bne	noc1

	inc	databuf+5
noc1
	lda	virdata+2
	clc
	adc	databuf+7
	sta	virdata+2
	lda	virdata+1
	adc	databuf+6
	sta	virdata+1
	lda	virdata+0
	adc	databuf+5
	sta	virdata+0
	jmp	fileloop
filedone
	.)

	.(
	lda	chnkmsb+CH_WRIT
	sta	inittmp
	lda	chnkssb+CH_WRIT
	sta	inittmp+1
	.)

	rts

initengine3
	; LANG and DICT.

	.(
	ldx	#CH_LANG
	jsr	loadchunk
	stx	lngbase
	sty	lngbase+1

	ldy	#1
	lda	(lngbase),y
	clc
	adc	lngbase
	sta	decoder
	dey
	lda	(lngbase),y
	adc	lngbase+1
	sta	decoder+1

	ldy	#7
	lda	(lngbase),y
	clc
	adc	lngbase
	sta	stoptbl
	dey
	lda	(lngbase),y
	adc	lngbase+1
	sta	stoptbl+1

	dey
	lda	(lngbase),y
	clc
	adc	lngbase
	sta	endbase
	dey
	lda	(lngbase),y
	adc	lngbase+1
	sta	endbase+1

	ldy	#$ff
loop1
	iny
	lda	(stoptbl),y
	bne	loop1

	sty	nosbpos
	sty	nosapos
	.)

	.(
	ldx	#CH_DICT
	jsr	loadchunk
	stx	dictch
	txa
	clc
	adc	#2
	sta	dicttbl
	sty	dictch+1
	tya
	adc	#0
	sta	dicttbl+1

	ldx	#CH_MAPS
	jsr	loadchunk
	stx	mapbase
	sty	mapbase+1
	.)

	.(
	lda	#7
	sta	escbits
	lda	#$ff
	sta	escbnd

	; check minor version
	ldy	#1+1
	lda	(hdbase),y
	cmp	#4
	bcc	done

	ldy	nosbpos
	inc	nosbpos
nosaloop
	iny
	lda	(stoptbl),y
	bne	nosaloop

	iny
	sty	nosapos

	inc	escbnd
	ldy	#3
	lda	(lngbase),y
	clc
	adc	lngbase
	sta	phytmp
	dey
	lda	(lngbase),y
	adc	lngbase+1
	sta	phytmp+1
	ldy	#0
	lda	(phytmp),y
	sec
	sbc	#32
	bmi	satbnd

	sta	escbnd
satbnd
	sty	escbits
	lda	(dictch),y
	sta	phytmp+1
	iny
	lda	(dictch),y
	clc
	adc	escbnd
	bcc	noc1

	inc	phytmp+1
	clc
noc1
	sbc	#0
	bcs	noc2

	dec	phytmp+1
noc2
	sta	phytmp
loop
	lda	phytmp+1
	bmi	done

	ora	phytmp
	beq	done

	lsr	phytmp+1
	ror	phytmp
	inc	escbits
	bne	loop	; always
done
	.)

	rts

initengine4
	; LOOK.

	.(
	lda	freeptr
	sec
	sbc	#8
	sta	phytmp
	lda	freeptr+1
	sbc	#0
	sta	phytmp+1

	lda	chnklsb+CH_LOOK
	sta	virdata+2
	lda	chnkssb+CH_LOOK
	sta	virdata+1
	lda	chnkmsb+CH_LOOK
	sta	virdata+0
	lda	#2
	jsr	readdata
	lda	#0
	sta	temp
	lda	databuf+1
	sta	count
	asl
	rol	temp
	asl
	rol	temp
	tax
	ldy	temp
	jsr	allocwords
	stx	stybase
	sty	stybase+1
classloop
	lda	#0
	sta	temp

	lda	count
	bne	notdone

	jmp	classdone
notdone
	asl
	rol	temp
	;clc
	adc	chnklsb+CH_LOOK
	sta	virdata+2
	lda	temp
	adc	chnkssb+CH_LOOK
	sta	virdata+1
	lda	chnkmsb+CH_LOOK
	adc	#0
	sta	virdata+0
	lda	#2
	jsr	readdata

	lda	databuf+1
	clc
	adc	chnklsb+CH_LOOK
	sta	virdata+2
	lda	databuf
	adc	chnkssb+CH_LOOK
	sta	virdata+1
	lda	chnkmsb+CH_LOOK
	adc	#0
	sta	virdata+0

	ldy	#7
	lda	#0
clrloop
	sta	(phytmp),y
	dey
	bpl	clrloop
attrsloop
	lda	#1
	jsr	readdata
	lda	databuf
	bne	attrsnotdone

	jmp	attrsdone
attrsnotdone
	ldx	#0
attrloop
	cmp	#$41
	bcc	nocase

	cmp	#$5b
	bcs	nocase

	eor	#$20
nocase
	sta	inpbuf,x
	inx
	txa
	pha
	lda	#1
	jsr	readdata
	pla
	tax
	lda	databuf
	bne	attrloop

	sta	inpbuf,x
#if 0
	ldx	#0
ploop
	lda	inpbuf,x
	beq	pdone

	txa
	pha
	lda	inpbuf,x
	jsr	vio_putc
	pla
	tax
	inx
	jmp	ploop
pdone
	lda	#SPC_AUTO
	sta	rspc
	jsr	vio_line
#endif
	ldy	#0
	sty	operlsb+0
matchloop
	ldx	#0
cmploop
	lda	csskeywords,y
	beq	cmpend

	cmp	inpbuf,x
	bne	matchnext

	inx
	iny
	jmp	cmploop
cmpskip1
	inx
cmpend
	lda	inpbuf,x
	cmp	#$20
	beq	cmpskip1

	cmp	#$3a
	beq	matchfound

	dey
matchnext
	iny
	lda	csskeywords,y
	bne	matchnext

	iny
	inc	operlsb+0
	lda	operlsb
	cmp	#CSS_N
	bcc	matchloop

	jmp	attrsloop
matchfound
cmpskip2
	inx
	lda	inpbuf,x
	cmp	#$20
	beq	cmpskip2

	ldy	operlsb
	bne	nowidth

	jsr	css_abs_rel
	ldy	#STY_WIDTH
	sta	(phytmp),y
	bcc	norelw

	ldy	#STY_FLAGS
	lda	(phytmp),y
	ora	#STYF_RELW
	sta	(phytmp),y
norelw
	jmp	attrsloop
nowidth
	dey
	bne	noheight

	jsr	css_abs_rel
	ldy	#STY_HEIGHT
	sta	(phytmp),y
	bcc	norelh

	ldy	#STY_FLAGS
	lda	(phytmp),y
	ora	#STYF_RELH
	sta	(phytmp),y
norelh
	jmp	attrsloop
noheight
	dey
	bne	nofloat

	ldy	#cssparam_left
	jsr	css_check_param
	bcc	noleft

	ldy	#STY_FLAGS
	lda	(phytmp),y
	ora	#STYF_FLOATL
	sta	(phytmp),y
	jmp	attrsloop
noleft
	ldy	#cssparam_right
	jsr	css_check_param
	bcc	noright

	ldy	#STY_FLAGS
	lda	(phytmp),y
	ora	#STYF_FLOATR
	sta	(phytmp),y
noright
	jmp	attrsloop
nofloat
	dey
	bne	nofstyle

	ldy	#cssparam_italic
	jsr	css_check_param
	bcs	italic

	ldy	#cssparam_oblique
	jsr	css_check_param
	bcc	noitalic
italic
	ldy	#STY_STYON
	lda	(phytmp),y
	ora	#4
	sta	(phytmp),y
	jmp	attrsloop
noitalic
	ldy	#cssparam_normal
	jsr	css_check_param
	bcc	nounitalic

	ldy	#STY_STYOFF
	lda	(phytmp),y
	ora	#4
	sta	(phytmp),y
nounitalic
	jmp	attrsloop
nofstyle
	dey
	bne	nofweight

	ldy	#cssparam_bold
	jsr	css_check_param
	bcc	nobold

	ldy	#STY_STYON
	lda	(phytmp),y
	ora	#2
	sta	(phytmp),y
	jmp	attrsloop
nobold
	ldy	#cssparam_normal
	jsr	css_check_param
	bcc	nounbold

	ldy	#STY_STYOFF
	lda	(phytmp),y
	ora	#2
	sta	(phytmp),y
nounbold
	jmp	attrsloop
nofweight
	dey
	bne	noffamily
fixedloop1
	ldy	#0
fixedloop2
	lda	inpbuf,x
	beq	nofixed

	cmp	css_monospace,y
	beq	fixednext

	cmp	#'m'
	beq	fixedloop1

	inx
	jmp	fixedloop1
fixednext
	inx
	iny
	cpy	#9
	bne	fixedloop2

	ldy	#STY_STYON
	lda	(phytmp),y
	ora	#8
	sta	(phytmp),y
nofixed
	jmp	attrsloop
noffamily
	dey
	bne	nomtop

	jsr	css_abs_rel
	bcs	badmtop

	ldy	#STY_MTOP
	sta	(phytmp),y
badmtop
	jmp	attrsloop
nomtop
	dey
	bne	nombottom

	jsr	css_abs_rel
	bcs	badmbtm

	ldy	#STY_MBOTTOM
	sta	(phytmp),y
badmbtm
nombottom
	jmp	attrsloop
attrsdone
#if 0
	ldy	#0
dumploop
	lda	(phytmp),y
	jsr	puthex
	iny
	cpy	#8
	bne	dumploop

	lda	#SPC_AUTO
	sta	rspc
	jsr	vio_line
#endif
	dec	count
	lda	phytmp
	sec
	sbc	#8
	sta	phytmp
	bcs	noc1

	dec	phytmp+1
noc1
	jmp	classloop
classdone
	.)

	.(
	lda	chnklsb+CH_CODE
	sec
	sbc	#1
	sta	codeseg+2
	lda	chnkssb+CH_CODE
	sbc	#0
	sta	codeseg+1
	lda	chnkmsb+CH_CODE
	sbc	#0
	sta	codeseg+0
	.)

	rts

css_abs_rel
	; input inpbuf = data
	; input x = data offset
	; output a = value
	; output c = relative
	; returns absolute 0 on error

	.(
	lda	#0
	sta	quot
	sta	quot+1
digloop
	lda	inpbuf,x
	cmp	#$30
	bcc	nodig

	cmp	#$3a
	bcs	nodig

	and	#$0f
	pha
	lda	#0
	sta	denom+1
	lda	#10
	sta	denom
	jsr	mul16
	pla
	clc
	adc	numer
	sta	quot
	lda	numer+1
	adc	#0
	sta	quot+1
	inx
	jmp	digloop
skip1
	inx
	lda	inpbuf,x
	cmp	#$30
	bcc	nodig2

	cmp	#$3a
	bcc	skip1
nodig
	cmp	#$2e
	beq	skip1
nodig2
	cmp	#'e'
	beq	got_e

	cmp	#'c'
	beq	got_c

	cmp	#$25
	bne	noparse

	lda	quot
	;sec
	rts
got_e
	lda	inpbuf+1,x
	cmp	#'m'
	beq	gotabs

	cmp	#'n'
	beq	gotabs

	jmp	noparse
got_c
	lda	inpbuf+1,x
	cmp	#'h'
	bne	noparse
gotabs
	lda	quot
	clc
	rts
noparse
	lda	#0
	clc
	rts
	.)

css_check_param
	; input inpbuf = input
	; input x = input offset
	; input y = keyword offset
	; output c = match
	; preserves x

	.(
	txa
	pha
loop
	lda	cssparams,y
	beq	end

	cmp	inpbuf,x
	bne	fail

	inx
	iny
	jmp	loop
skip
	inx
end
	lda	inpbuf,x
	cmp	#$20
	beq	skip

	cmp	#0
	beq	succeed
fail
	clc
succeed
	pla
	tax
	rts
	.)

CH_CODE	= 0
CH_LANG	= 1
CH_META	= 2
CH_INIT	= 3
CH_WRIT = 4
CH_TAGS = 5
CH_DICT = 6
CH_MAPS = 7
CH_LOOK = 8
CH_URLS = 9
CH_N	= 10
chunknames
	.byt	"CLMIWTDMLU"
	.byt	"OAENRAIAOR"
	.byt	"DNTIIGCPOL"
	.byt	"EGATTSTSKS"

CSS_WIDTH	= 0
CSS_HEIGHT	= 1
CSS_FLOAT	= 2
CSS_FONTSTYLE	= 3
CSS_FONTWEIGHT	= 4
CSS_FONTFAMILY	= 5
CSS_MARGINTOP	= 6
CSS_MARGINBTM	= 7
CSS_N		= 8
csskeywords
	.byt	"width",0
	.byt	"height",0
	.byt	"float",0
	.byt	"font-style",0
	.byt	"font-weight",0
	.byt	"font-family",0
	.byt	"margin-top",0
	.byt	"margin-bottom",0

cssparams
cssparam_left	= * - cssparams
	.byt	"left",0
cssparam_right	= * - cssparams
	.byt	"right",0
cssparam_italic	= * - cssparams
	.byt	"italic",0
cssparam_oblique = * - cssparams
	.byt	"oblique",0
cssparam_normal	= * - cssparams
	.byt	"normal",0
cssparam_bold	= * - cssparams
	.byt	"bold",0

css_monospace
	.byt	"monospace"

allocwords
	; input x = size lsb
	; input y = size msb
	; output x = addr lsb
	; output y = addr msb
	; clobbers phydata

	.(
	stx	phydata
	sty	phydata+1
	asl	phydata
	rol	phydata+1

	lda	freeptr
	sec
	sbc	phydata
	sta	freeptr
	tax
	lda	freeptr+1
	sbc	phydata+1
	sta	freeptr+1
	tay
	rts
	.)

loadchunk
	.(
	lda	chnklsb,x
	sec
	sbc	#2
	sta	virdata+2
	lda	chnkssb,x
	sbc	#0
	sta	virdata+1
	lda	chnkmsb,x
	sbc	#0
	sta	virdata+0
	lda	#2
	jsr	readdata
	lda	databuf+1
	sta	physize
	lda	databuf
	sta	physize+1

	lda	freeptr
	sec
	sbc	physize
	sta	freeptr
	sta	phydata
	lda	freeptr+1
	sbc	physize+1
	sta	freeptr+1
	sta	phydata+1

	jsr	readdatato

	ldx	freeptr
	ldy	freeptr+1
	rts
	.)

initaddpage
	; input a = physical page

	.(
	sta	phytmp+1
	lda	#0
	sta	phytmp
	sta	phydata
	ldx	inittmp
	ldy	inittmp+1
	cpx	filesz+0
	bcc	noover

	cpy	filesz+1
	bcs	over
noover
	jsr	swapin
	tax
	sta	phydata+1
	ldy	#0
copy
	lda	(phydata),y
	sta	(phytmp),y
	iny
	bne	copy

	jsr	evictx

	lda	inittmp
	clc
	adc	vtmsb
	sta	vtptr+1
	ldy	inittmp+1
	lda	phytmp+1
	sta	(vtptr),y

	inc	inittmp+1
	bne	noc1

	inc	inittmp
noc1
over
	rts
	.)

zpcode
	* = zporg

ldyfetchnext
pclsb	= * + 1
	ldy	#0
fetchnext
	.(
	iny
	beq	wrap
postwrap
#if TRACE_INST
	jsr	traceinst
#endif
+phypc	= *+1
	lda	!0,y
#if TRACE_INST
	sta	$0220
	sta	$0221
#endif
	asl
	sta	`opcode
	ldx	#0
+opcode	= *+1
	jmp	(optable)
wrap
	jsr	pcwrap
	beq	postwrap
	.)

zpcodelen = *-zporg
	* = zpcode+zpcodelen
