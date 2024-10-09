    include devices/timer.i
    include exec/memory.i
    include exec/tasks.i
    include hardware/cia.i
    include hardware/custom.i
    include hardware/dmabits.i
    include hardware/intbits.i
    include lvo/dos_lib.i
    include lvo/exec_lib.i
    include lvo/timer_lib.i
    
* Macro to print to debug console
DPRINT  macro
        jsr      desmsgDebugAndPrint
        dc.b     \1,10,0
        even
        endm


* Constants
PAL_CLOCK=3546895
SAMPLING_FREQ=27500
PAULA_PERIOD=(PAL_CLOCK+SAMPLING_FREQ/2)/SAMPLING_FREQ
SAMPLES_PER_FRAME set (SAMPLING_FREQ+25)/50
BUFFER_SIZE = 1000

    xref    _c64init
    xref    _c64get
    xref    _c64uninit
    xdef    _main

_main:
    DPRINT  "Start"
    bset    #1,$bfe001

    bsr     openTimer
    move.l  4.w,a6
    lea     DOSName,a1
    jsr     _LVOOldOpenLibrary(a6)
    move.l  d0,DOSBase

    move.l  #8*BUFFER_SIZE,d0
    move.l	#MEMF_CHIP!MEMF_CLEAR,d1
    jsr     _LVOAllocMem(a6)
    move.l  d0,.chipmem
    lea     outBuffer1lh,a0
 rept 8
    move.l  d0,(a0)+
    add.l   #BUFFER_SIZE,d0
 endr

    DPRINT  "_c64init"
    move.l  #sid,d0
    move.l  #sidLen,d1
    jsr     _c64init
    DPRINT  "_c64init=%lx"

    bsr     createReSIDWorkerTask

.loop
    bsr     delay
    btst    #6,$bfe001
    bne     .loop
.skip
    bsr     stopReSIDWorkerTask    

    * Stop audio
    move    #$f,dmacon+$dff000
    move    #0,$dff0a8
    move    #0,$dff0b8
    move    #0,$dff0c8
    move    #0,$dff0d8

    bsr     closeTimer
    jsr    _c64uninit

    move.l  .chipmem,d0
    beq     .x1
    move.l  d0,a1
    move.l  #8*BUFFER_SIZE,d0
    move.l  4.w,a6
    jsr     _LVOFreeMem(a6)
.x1 
    move.l  frameCount,d0
    move.l  frameTimes,d1
    divu.l  d0,d1
    move.l  maxTime,d2
    DPRINT  "frames=%ld avg=%ldms max=%ldms"

    DPRINT  "exit"
    rts

.chipmem    dc.l    0

delay
    movem.l d0-a6,-(sp)
    move.l  DOSBase,a6
    moveq   #1,d1
    jsr     _LVODelay(a6)
    movem.l (sp)+,d0-a6
    rts

* in:
*   d7 = 1/50 secs to wait
wait
.l
    bsr     delay
    subq    #1,d7
    bne     .l
    rts


createReSIDWorkerTask:
  
    movem.l d0-a6,-(sp)
    tst.b   workerStatus
    bne     .x

    lea     workerTaskStruct,a0
    move.b  #NT_TASK,LN_TYPE(a0)
    move.b  #-1,LN_PRI(a0)
    move.l  #.workerTaskName,LN_NAME(a0)
    lea     workerTaskStack,a1
    move.l  a1,TC_SPLOWER(a0)
    lea     4096(a1),a1
    move.l  a1,TC_SPUPPER(a0)
    move.l  a1,TC_SPREG(a0)

    move.l  a0,a1
    lea     workerEntry(pc),a2
    sub.l   a3,a3
    move.l  4.w,a6
    jsr     _LVOAddTask(a6)
    addq.b  #1,workerStatus
.x
    movem.l (sp)+,d0-a6
    rts

.workerTaskName
    dc.b    "reSID",0
    even

stopReSIDWorkerTask:
    
    movem.l d0-a6,-(sp)
    tst.b   workerStatus
    beq     .x
    move.b  #-1,workerStatus

    move.l  4.w,a6
    move.l  reSIDTask(pc),a1
    moveq   #0,d0
    move.b  reSIDExitSignal(pc),d1
    bset    d1,d0
    jsr     _LVOSignal(a6)

    lea     _DOSName(pc),a1
    jsr     _LVOOldOpenLibrary(a6)
    move.l  d0,a6
.loop
    tst.b   workerStatus
    beq     .y
    moveq   #1,d1
    jsr     _LVODelay(a6)
    bra     .loop
.y
    move.l  a6,a1
    move.l  4.w,a6
    jsr     _LVOCloseLibrary(a6)
.x 
    movem.l (sp)+,d0-a6
    rts

_DOSName
    dc.b    "dos.library",0
    even

* Playback task
workerEntry
    addq.b  #1,workerStatus

    move.l  4.w,a6
    sub.l   a1,a1
    jsr     _LVOFindTask(a6)
    move.l  d0,reSIDTask
    
    moveq   #-1,d0
    jsr     _LVOAllocSignal(a6)
    move.b  d0,reSIDAudioSignal
    moveq   #-1,d0
    jsr     _LVOAllocSignal(a6)
    move.b  d0,reSIDExitSignal

    lea     reSIDLevel4Intr1,a1
    moveq   #INTB_AUD0,d0		; Allocate Level 4
    jsr     _LVOSetIntVector(a6)
    move.l  d0,.oldVecAud0

    move.w  #INTF_AUD0,intena+$dff000
    move.w  #INTF_AUD0,intreq+$dff000
    move.w  #DMAF_AUD0!DMAF_AUD1!DMAF_AUD2!DMAF_AUD3,dmacon+$dff000

    * CH0 = high 8 bits - full volume
    * CH3 = low 6 bits  - volume 1
    * CH1 = high 8 bits - full volume
    * CH2 = low 6 bits  - volume 1
    move    #PAULA_PERIOD,$a6+$dff000
    move    #PAULA_PERIOD,$b6+$dff000
    move    #PAULA_PERIOD,$c6+$dff000
    move    #PAULA_PERIOD,$d6+$dff000
    ; TODO: hook up vol control
    move    #64,$a8+$dff000
    move    #1,$d8+$dff000
    move    #64,$b8+$dff000
    move    #1,$c8+$dff000


    movem.l outBuffer1lh(pc),d0/d1/d2/d3
    move.l  d0,$a0+$dff000  * left high
    move.l  d1,$d0+$dff000  * left low
    move.l  d2,$b0+$dff000  * right high
    move.l  d3,$c0+$dff000  * right low

    bsr     fillBufferA2
    move    d0,$a4+$dff000   * words
    move    d0,$d4+$dff000   * words
    move    d0,$b4+$dff000   * words
    move    d0,$c4+$dff000   * words

    bsr     dmawait

;    move    #DMAF_SETCLR!DMAF_AUD0!DMAF_AUD1!DMAF_AUD2!DMAF_AUD3,dmacon+$dff000
    move    #DMAF_SETCLR!DMAF_AUD0,dmacon+$dff000
    move.w  #INTF_SETCLR!INTF_AUD0,intena+$dff000

    ; buffer A now plays
    ; interrupt will be triggered soon to queue the next sample
    ; wait for the interrupt and queue buffer B
    ; fill buffer B
    ; after A has played, B will start
    ; interrupt will be triggered
    ; queue buffer A
    ; fill A
    ; ... etc

.loop
    move.l  4.w,a6
    moveq   #0,d0
    move.b  reSIDAudioSignal(pc),d1
    bset    d1,d0
    move.b  reSIDExitSignal(pc),d1
    bset    d1,d0
    jsr     _LVOWait(a6)

    tst.b   workerStatus
    bmi.b   .x

    bsr     reSIDLevel1Handler

    bra     .loop
.x

    move.w  #DMAF_AUD0!DMAF_AUD1!DMAF_AUD2!DMAF_AUD3,dmacon+$dff000
    move.w  #INTF_AUD0,intena+$dff000
    move.w  #INTF_AUD0,intreq+$dff000

    moveq   #INTB_AUD0,d0
    move.l  .oldVecAud0(pc),a1
    move.l  4.w,a6
    jsr     _LVOSetIntVector(a6)
    move.l  d0,.oldVecAud0
    
    move.b   reSIDAudioSignal(pc),d0
    jsr     _LVOFreeSignal(a6)
    move.b   reSIDExitSignal(pc),d0
    jsr     _LVOFreeSignal(a6)

    jsr     _LVOForbid(a6)
    clr.b   workerStatus
    rts

.oldVecAud0     dc.l    0

    ;0  = not running
    ;1  = running
    ;-1 = exiting
workerStatus        dc.b    0
    even

outBuffer1lh  dc.l    0
outBuffer1ll  dc.l    0
outBuffer1rh  dc.l    0
outBuffer1rl  dc.l    0
outBuffer2lh  dc.l    0
outBuffer2ll  dc.l    0
outBuffer2rh  dc.l    0
outBuffer2rl  dc.l    0

switchBuffers:
    movem.l outBuffer1lh(pc),d0/d1/d2/d3
    movem.l outBuffer2lh(pc),d4/d5/d6/d7
    movem.l d0/d1/d2/d3,outBuffer2lh
    movem.l d4/d5/d6/d7,outBuffer1lh
    rts

fillBufferA2:
    bsr     startMeasure

    move    #$f00,$dff180
    jsr     _c64get
    clr     $dff180
    move.l  d0,a0   
    * 550 samples of llLLrrRR, or 20 ms

    move.w  #SAMPLES_PER_FRAME-1,d7
    movem.l outBuffer1lh(pc),a1/a2/a3/a4
.conv
    * left
    move.b  (a0)+,d0
    lsr.b   #2,d0
    move.b  d0,(a2)+    * left low
    move.b  (a0)+,(a1)+ * left high

    * right
    move.b  (a0)+,d0
    lsr.b   #2,d0
    move.b  d0,(a4)+    * right low
    move.b  (a0)+,(a3)+ * right high
    
    dbf     d7,.conv

    bsr     stopMeasure
    add.l   d0,frameTimes
    addq.l  #1,frameCount
    cmp.l   maxTime(pc),d0
    blo.b   .1
    move.l  d0,maxTime
.1

    move.l  #SAMPLES_PER_FRAME/2,d0
    rts

dmawait
	movem.l d0/d1,-(sp)
	moveq	#12-1,d1
.d	move.b	$dff006,d0
.k	cmp.b	$dff006,d0
	beq.b	.k
	dbf	d1,.d
	movem.l (sp)+,d0/d1
	rts

reSIDLevel4Intr1	
        dc.l	0		; Audio Interrupt
		dc.l	0
		dc.b	2
		dc.b	0
		dc.l	reSIDLevel4Name1
reSIDLevel4Intr1Data:
reSIDTask:	
    dc.l	0		            ;is_Data
	dc.l	reSIDLevel4Handler1	;is_Code

reSIDLevel4Name1
    dc.b    "reSID Audio",0
    even

reSIDLevel1Intr
      	dc.l	0		; Player (Software)
		dc.l	0
		dc.b	2
		dc.b	0
		dc.l    reSIDLevel4Name1
PlayIntrPSB	dc.l	0
		dc.l	reSIDLevel1Handler



* a0 = custom base
* a1 = is_data = task
* a6 = execbase
reSIDLevel4Handler1
    move.w  #INTF_AUD0,intreq(a0)
    move.b  reSIDAudioSignal(pc),d1
    moveq   #0,d0
    bset    d1,d0
    jmp     _LVOSignal(a6)
    ;lea     reSIDLevel1Intr(pc),a1
    ;jmp     _LVOCause(a6)

reSIDLevel1Handler
    movem.l d2-d7/a2-a4,-(sp)
 
    * Switch buffers and fill
    bsr     switchBuffers
    movem.l outBuffer1lh(pc),d0/d1/d2/D3
    move.l  d0,$a0+$dff000 * left high
    move.l  d1,$d0+$dff000 * left low
    move.l  d2,$b0+$dff000 * right high
    move.l  d3,$c0+$dff000 * right low

    bsr     fillBufferA2
    move    d0,$a4+$dff000   * words
    move    d0,$d4+$dff000   * words
    move    d0,$b4+$dff000   * words
    move    d0,$c4+$dff000   * words

    movem.l (sp)+,d2-d7/a2-a4
    moveq   #0,d0
    rts


    
reSIDAudioSignal    dc.b    0
reSIDExitSignal     dc.b    0
maxTime             dc.l    0
frameCount          dc.l    0
frameTimes          dc.l    0
    even


***************************************************************************
*
* Performance measurement with timer.device
*
***************************************************************************

openTimer
	move.l	4.w,a0
	move	LIB_VERSION(a0),d0
	cmp	#36,d0
	blo.b	.x
	move.l	a0,a6

	lea	.timerDeviceName(pc),a0
	moveq	#UNIT_ECLOCK,d0
	moveq	#0,d1
	lea	timerRequest,a1
	jsr	_LVOOpenDevice(a6)		; d0=0 if success
	tst.l	d0
	seq	timerOpen
.x	rts

.timerDeviceName dc.b	"timer.device",0
	even

closeTimer
	tst.b	timerOpen
	beq.b	.x
	clr.b	timerOpen
	move.l	4.w,a6
	lea	timerRequest,a1
	jsr	_LVOCloseDevice(a6)
.x	rts

startMeasure
	tst.b	timerOpen(pc)
	beq.b	.x
	move.l	IO_DEVICE+timerRequest(pc),a6
	lea	clockStart(pc),a0
	jsr     _LVOReadEClock(a6)
.x	rts

; out: d0: difference in millisecs
stopMeasure
	tst.b	timerOpen(pc)
	bne.b	.x
	moveq	#-1,d0
	rts
.x
	move.l	IO_DEVICE+timerRequest(pc),a6
	lea	clockEnd,a0
	jsr     _LVOReadEClock(a6)
    * D0 will be 709379 for PAL.
	move.l	d0,d2
	; d2 = ticks/s
	divu	#1000,d2
	; d2 = ticks/ms
	ext.l	d2
	
	; Calculate diff between start and stop times
	; in 64-bits
	move.l	EV_HI+clockEnd(pc),d0
	move.l	EV_LO+clockEnd(pc),d1
	move.l	EV_HI+clockStart(pc),d3
	sub.l	EV_LO+clockStart(pc),d1
	subx.l	d3,d0

	; Turn the diff into millisecs
    divu.l  d2,d1
	move.l	d1,d0
	rts

timerOpen               dc.w    1
timerRequest	        ds.b    IOTV_SIZE
clockStart              ds.b    EV_SIZE
clockEnd                ds.b    EV_SIZE




DOSName     dc.b    "dos.library",0
    even




desmsgDebugAndPrint
	* sp contains the return address, which is
	* the string to print
	movem.l	d0-d7/a0-a3/a6,-(sp)
	* get string
	move.l	4*(8+4+1)(sp),a0
	* find end of string
	move.l	a0,a1
.e	tst.b	(a1)+
	bne.b	.e
	move.l	a1,d7
	btst	#0,d7
	beq.b	.even
	addq.l	#1,d7
.even
	* overwrite return address 
	* for RTS to be just after the string
	move.l	d7,4*(8+4+1)(sp)

	move.l	sp,a1	
    lea     .putCharSerial(pc),a2
	move.l	4.w,a6
	jsr	    _LVORawDoFmt(a6)
	movem.l	(sp)+,d0-d7/a0-a3/a6
	rts	* teleport!

.putCharSerial
    ;_LVORawPutChar
    ; output char in d0 to serial
    move.l  4.w,a6
    jsr     -516(a6)
    rts

sid 
    incbin  Skate_or_Die_intro.sid 
    ;incbin  Yet_Bigger_Beat_2SID.sid
    ;incbin  Terra_Cresta.sid
    ;incbin  Netherworld.sid 
sidLen = *-sid

    section bss1,bss

DOSBase             ds.l    1
workerTaskStack     ds.b    4096
workerTaskStruct    ds.b    TC_SIZE

