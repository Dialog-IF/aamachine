; A2 SmartPort boot loader ("sboot").
; Designed for the xa65 assembler.
;
; Replaces ProDOS on an 800k (or bigger) SmartPort volume.  Block 0 is
; the classic boot0 signature -- format byte, then SEC/BCS+3/JMP so a
; format-sniffing tool sees the same four bytes ProDOS's own boot0 uses
; -- followed by code that finds the slot from the boot ROM handoff,
; verifies the card answers the SmartPort ROM signature, and reads
; AAM.SYSTEM's data blocks straight to $2000.
;
; Unlike a general ProDOS reader, this does not walk the volume
; directory at runtime -- the bundler builds the disk, so it already
; knows exactly where AAM.SYSTEM's data blocks are.  AAMSTART is the
; first block past the volume bitmap (block 7, given this volume's
; fixed layout -- see AAMSTART below), and AAM_BLOCKS is however many
; 512-byte blocks the interpreter takes, passed in with -DAAM_BLOCKS
; at assemble time (see the 6502/Makefile rule).  The bundler allocates
; AAM.SYSTEM as the very first file on a freshly formatted volume, and
; a sapling/tree's data blocks are always written contiguously before
; their index block(s) (see vol_write_sapling in bundle_apple2.c), so
; that range is guaranteed contiguous -- the same trick 0boot uses to
; read whole tracks on a 5.25" disk.  A sanity check on the loaded
; data's first byte (always the $4c of a JMP, see a2_frontend.s's boot
; header) catches a mismatched build before jumping into it.
;
; Once loaded, jump to $2003 (raw_entry in a2_frontend.s), the same
; entry 0boot uses, so the interpreter knows there is no ProDOS
; underneath.
;
; SmartPort calling convention (see e.g. 1000bit.it's Apple technote
; archive, smpt/tn.smpt.2 -- "SmartPort Technical Note #2")
;
;   Boot ROM hands off to $0801 with X = slot * 16.
;   $Cn00 is the slot's own I/O ROM.  A block device answers
;     $Cn01=$20, $Cn03=$00, $Cn05=$03, $Cn07=$00 (SmartPort; nonzero
;     at $Cn07 means "generic ProDOS block device", no raw SmartPort
;     calls).
;   $Cn00 + [$CnFF] is the ProDOS-style entry point; 3 bytes further in
;     is the raw SmartPort entry, called as
;       jsr entry
;       .byte cmd
;       .word paramlist
;     which returns with carry set and an error code in A on failure.
;   READ BLOCK (cmd=1) parameter list -- count=3, unit, buffer ptr (2
;     bytes), block # (3 bytes, little-endian).

#ifndef AAM_BLOCKS
#define AAM_BLOCKS 40		; default for standalone assembly/testing
#endif

	COUT		= $fded

	; A sliver of the ProDOS global page that ProRWTS2's init (see
	; a2_prorwts2.acme) reads before it ever calls the (faked) MLI --
	; DEVNUM tells it which slot/drive it booted from, and DEVADR01HI is
	; where it looks that slot up.  0boot fakes DEVNUM for the same
	; reason (see 0boot.acme); we additionally fake DEVADR01HI (below,
	; in cont) because a smartport boot -- unlike 0boot's floppy boot --
	; falls through ProRWTS2's initial device-list checks and lands in
	; its SmartPort multi-unit scan, which calls the real MLI's
	; READ_BLOCK to seed a reference buffer.  mlistub (a2_frontend.s)
	; only emulates GET_PREFIX, so that read silently no-ops and the
	; scan compares real data against a zeroed buffer forever.  Faking
	; DEVADR01HI to match makes ProRWTS2 take its early "already know
	; the slot" exit instead, the same shortcut 0boot gets for free from
	; the Disk ][ ROM signature match.
	DEVNUM		= $bf30
	DEVADR01HI	= $bf11

	; AAMSTART -- see the header comment above.  Tied to this volume's
	; fixed layout -- BITMAP_BLOCK=6 plus one bitmap block, which covers
	; up to 4096 total blocks -- comfortably more than BLOCKS_800K
	; (1600) in bundle_apple2.c.  A bigger volume needing a second
	; bitmap block would have to bump this.
	AAMSTART	= 7

	; zero page scratch -- nothing else is running yet, so any of it
	; is free to use.
	ptr		= $f0	; 2 bytes, generic indirect pointer
	cn_hi		= $f2	; 1 byte, $c0 + slot
	blknum		= $f3	; 3 bytes, block # for do_read
	blkleft		= $f6	; 1 byte, blocks still to load
	msgptr		= $f0	; 2 bytes, reuses ptr -- boot is over by
				; the time a failure message needs it

; =====================================
; Block 0
; =====================================

	* = $0800

	.byt	1		; format marker, not executed (entry is $0801)
	sec			; $0801 -- entry point, X = slot*16
	bcs	cont		; always taken -- skips the jmp below
	jmp	cont		; dead code, present for format-sniffing tools

cont
	.(
	stx	DEVNUM		; DEVNUM = slot*16, drive 1 (see above)
	txa
	lsr
	lsr
	lsr
	lsr			; a = slot number, 0-7
	tax			; x = slot number, stashed for below
	ora	#$c0
	sta	cn_hi		; cn_hi = $c0 + slot
	sta	ptr+1
	txa
	asl
	tay			; y = slot*2 -- DEVADR01HI's index
	lda	cn_hi
	sta	DEVADR01HI,y	; see above
	lda	#0
	sta	ptr

	; verify the SmartPort ROM signature at $Cn01/03/05/07
	ldy	#1
	lda	(ptr),y
	cmp	#$20
	bne	notsp
	ldy	#3
	lda	(ptr),y
	bne	notsp
	ldy	#5
	lda	(ptr),y
	cmp	#$03
	bne	notsp
	ldy	#7
	lda	(ptr),y
;	bne	notsp		; TODO doesnt work on izapple?

	; entry = $Cn00 + [$CnFF]; raw SmartPort entry is 3 bytes further in
	ldy	#$ff
	lda	(ptr),y
	clc
	adc	#3
	sta	docall+1
	lda	cn_hi
	sta	docall+2

	; read AAM_BLOCKS blocks starting at AAMSTART into $2000
	lda	#AAMSTART
	sta	blknum
	lda	#0
	sta	blknum+1
	sta	blknum+2
	lda	#0
	sta	parambuf	; dest lo = 0
	lda	#$20
	sta	parambuf+1	; dest hi = $20 -- $2000
	lda	#AAM_BLOCKS
	sta	blkleft
loadloop
	jsr	do_read
	bcs	diskerr
rdok
	inc	blknum
	bne	nocarry
	inc	blknum+1
nocarry
	lda	parambuf+1
	clc
	adc	#2
	sta	parambuf+1
	dec	blkleft
	bne	loadloop

	; sanity check -- AAM.SYSTEM's boot header always starts with a
	; JMP ($4c); catches a mismatched build before jumping into it
	lda	$2000
	cmp	#$4c
	beq	loaded
	ldx	#<msg_badsys
	ldy	#>msg_badsys
	jmp	fail

loaded
	jmp	$2003		; raw_entry -- no ProDOS underneath us

notsp
	ldx	#<msg_notsp
	ldy	#>msg_notsp
	jmp	fail

diskerr
	ldx	#<msg_diskerr
	ldy	#>msg_diskerr
	jmp	fail
	.)

; input blknum (3 bytes) + parambuf (2 bytes), pre-set by the caller;
; output c = error
do_read
	lda	blknum
	sta	paramblk
	lda	blknum+1
	sta	paramblk+1
	lda	blknum+2
	sta	paramblk+2
docall
	jsr	$0000		; operand patched at boot to the raw
				; SmartPort entry
	.byt	$01		; READ BLOCK
	.word	paramlist
	rts

paramlist
	.byt	3
paramunit
	.byt	1
parambuf
	.word	0
paramblk
	.byt	0,0,0

; input x/y = message, low/high; never returns
fail
	.(
	stx	msgptr
	sty	msgptr+1
	ldy	#0
loop
	lda	(msgptr),y
	beq	halt
	jsr	COUT
	iny
	bne	loop
halt
	jmp	halt
	.)

msg_notsp
	.asc	"NOT A SMARTPORT DEVICE",0
msg_diskerr
	.asc	"DISK ERROR",0
msg_badsys
	.asc	"BAD AAM.SYSTEM",0

	.dsb	$0a00-*,0	; error out if this grew past one block
