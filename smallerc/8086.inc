;
; NASM macros that let Smaller C's 16-bit output assemble for the 8086.
;
; smlrc's small-model code uses a few 80186 and 80386 instructions
; (movzx, movsx, setcc, push imm, shifts by an immediate count).  Each
; is replaced here by an 8086 sequence that leaves the other registers
; and, where the original did, the flags alone.  nasm8086 pre-includes
; this file, so it applies to the program and to the rebuilt library.
;
; movzx, movsx and setcc are from Smaller C's include/sys/80186.h:
;
;   Copyright (c) 2012-2021, Alexey Frunze
;   All rights reserved.
;
;   Redistribution and use in source and binary forms, with or without
;   modification, are permitted provided that the following conditions are met:
;
;   1. Redistributions of source code must retain the above copyright notice, this
;      list of conditions and the following disclaimer.
;   2. Redistributions in binary form must reproduce the above copyright notice,
;      this list of conditions and the following disclaimer in the documentation
;      and/or other materials provided with the distribution.
;
;   THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
;   ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
;   WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
;   DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR
;   ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
;   (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
;   LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
;   ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
;   (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
;   SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
;

cpu 8086

%define ___ReGs___Lo8___ "alblcldl"
%define ___ReGs___Hi8___ "ahbhchdh"
%define ___ReGs___16___ "axbxcxdxsidibpsp"

%macro movzx 2.nolist
  %push __CTX_MOVZX__

  %assign %$r_n 8 ; not 8-bit register
  %ifidni %2,al
    %assign %$r_n 0
  %endif
  %ifidni %2,bl
    %assign %$r_n 1
  %endif
  %ifidni %2,cl
    %assign %$r_n 2
  %endif
  %ifidni %2,dl
    %assign %$r_n 3
  %endif
  %ifidni %2,ah
    %assign %$r_n 4
  %endif
  %ifidni %2,bh
    %assign %$r_n 5
  %endif
  %ifidni %2,ch
    %assign %$r_n 6
  %endif
  %ifidni %2,dh
    %assign %$r_n 7
  %endif

  %assign %$l_n 8 ; not 16-bit register
  %ifidni %1,ax
    %assign %$l_n 0
  %endif
  %ifidni %1,bx
    %assign %$l_n 1
  %endif
  %ifidni %1,cx
    %assign %$l_n 2
  %endif
  %ifidni %1,dx
    %assign %$l_n 3
  %endif
  %ifidni %1,si
    %assign %$l_n 4
  %endif
  %ifidni %1,di
    %assign %$l_n 5
  %endif
  %ifidni %1,bp
    %assign %$l_n 6
  %endif
  ;%ifidni %1,sp
  ;  %assign %$l_n 7
  ;%endif

  %if %$l_n == 8
    %fatal expected word register (other than sp) in left operand
  %endif

  %if %$r_n != 8
    ; right operand is register
    %if %$l_n < 4
      ; movzx hi_lo, reg
      %if %$l_n != %$r_n
        %substr %$reg_lo_str ___ReGs___Lo8___ (%$l_n*2+1), 2
                           ; 2-char string with reg name, e.g. "al"
        %deftok %$reg_lo %$reg_lo_str ; tokenized to e.g. al
        mov %$reg_lo, %2
      %endif
      %substr %$reg_hi_str ___ReGs___Hi8___ (%$l_n*2+1), 2
      %deftok %$reg_hi %$reg_hi_str
      mov %$reg_hi, 0
    %else
      ; movzx non-hi_lo, reg
      mov %1, ax
      %if %$r_n != 0
        mov al, %2
      %endif
      mov ah, 0
      xchg ax, %1
    %endif
  %else
    ; right operand is memory
    %if %$l_n < 4
      ; movzx hi_lo, mem
      %substr %$reg_lo_str ___ReGs___Lo8___ (%$l_n*2+1), 2
      %deftok %$reg_lo %$reg_lo_str
      %substr %$reg_hi_str ___ReGs___Hi8___ (%$l_n*2+1), 2
      %deftok %$reg_hi %$reg_hi_str
      mov %$reg_lo, %2
      mov %$reg_hi, 0
    %else
      ; movzx non-hi_lo, mem
      ; Strip leading "byte" from %2 for lea.
      %define %$mem %2
      %defstr %$mem_str %2
      %substr %$pfx %$mem_str 1,4
      %ifidni %$pfx, "byte"
        %substr %$pfx %$mem_str 5
        %ifidn %$pfx, " "
          %substr %$mem_str %$mem_str 5,-1
          %deftok %$mem %$mem_str
        %endif
        %ifidn %$pfx, `\t`
          %substr %$mem_str %$mem_str 5,-1
          %deftok %$mem %$mem_str
        %endif
        %ifidn %$pfx, "["
          %substr %$mem_str %$mem_str 5,-1
          %deftok %$mem %$mem_str
        %endif
      %endif
      ; TBD: move segment prefix (if any) from "lea ..., [seg:...]"
      ; to "mov ..., [seg:...]"
      lea  %1, %$mem
      xchg bx, %1
      mov  bl, [bx]
      mov  bh, 0
      xchg bx, %1
    %endif
  %endif

  %pop ; __CTX_MOVZX__
%endm

%macro movsx 2.nolist
  %push __CTX_MOVSX__

  %assign %$r_n 8 ; not 8-bit register
  %ifidni %2,al
    %assign %$r_n 0
  %endif
  %ifidni %2,bl
    %assign %$r_n 1
  %endif
  %ifidni %2,cl
    %assign %$r_n 2
  %endif
  %ifidni %2,dl
    %assign %$r_n 3
  %endif
  %ifidni %2,ah
    %assign %$r_n 4
  %endif
  %ifidni %2,bh
    %assign %$r_n 5
  %endif
  %ifidni %2,ch
    %assign %$r_n 6
  %endif
  %ifidni %2,dh
    %assign %$r_n 7
  %endif

  %assign %$l_n 8 ; not 16-bit register
  %ifidni %1,ax
    %assign %$l_n 0
  %endif
  %ifidni %1,bx
    %assign %$l_n 1
  %endif
  %ifidni %1,cx
    %assign %$l_n 2
  %endif
  %ifidni %1,dx
    %assign %$l_n 3
  %endif
  %ifidni %1,si
    %assign %$l_n 4
  %endif
  %ifidni %1,di
    %assign %$l_n 5
  %endif
  %ifidni %1,bp
    %assign %$l_n 6
  %endif
  ;%ifidni %1,sp
  ;  %assign %$l_n 7
  ;%endif

  %if %$l_n == 8
    %fatal expected word register (other than sp) in left operand
  %endif

  %if %$r_n != 8
    ; right operand is register
    %if %$l_n == 0
      ; movsx ax, r
      %if %$r_n != 0
        mov al, %2
      %endif
      cbw
    %else
      %if %$r_n < 4
        %assign %$reg %$r_n
      %else
        %assign %$reg %$r_n - 4
      %endif
      %if %$l_n == %$reg
        ; movsx non-ax, lo/hi of the same non-ax reg
        xchg ax, %1
        %if %$r_n >= 4
          mov al, ah
        %endif
      %else
        ; movsx non-ax, lo/hi of other reg
        mov %1, ax
        %if %$r_n != 0
          mov al, %2
        %endif
      %endif
      cbw
      xchg ax, %1
    %endif
  %else
    ; right operand is memory
    %if %$l_n == 0
      ; movsx ax, mem
      mov al, %2
      cbw
    %else
      ; movsx non-ax, mem
      ; Strip leading "byte" from %2 for lea.
      %define %$mem %2
      %defstr %$mem_str %2
      %substr %$pfx %$mem_str 1,4
      %ifidni %$pfx, "byte"
        %substr %$pfx %$mem_str 5
        %ifidn %$pfx, " "
          %substr %$mem_str %$mem_str 5,-1
          %deftok %$mem %$mem_str
        %endif
        %ifidn %$pfx, `\t`
          %substr %$mem_str %$mem_str 5,-1
          %deftok %$mem %$mem_str
        %endif
        %ifidn %$pfx, "["
          %substr %$mem_str %$mem_str 5,-1
          %deftok %$mem %$mem_str
        %endif
      %endif
      ; TBD: move segment prefix (if any) from "lea ..., [seg:...]"
      ; to "mov ..., [seg:...]"
      lea  %1, %$mem
      %if %$l_n != 1
        xchg bx, %1
      %endif
      mov  bl, [bx]
      xchg ax, bx
      cbw
      xchg ax, bx
      %if %$l_n != 1
        xchg bx, %1
      %endif
    %endif
  %endif

  %pop ; __CTX_MOVSX__
%endm

%macro ___set_cc___ 2.nolist
  mov %2, byte 0
  j%-1 %%skip
  mov %2, byte 1
%%skip:
%endm

%macro seta 1.nolist
  ___set_cc___ a, %1
%endm
%macro setae 1.nolist
  ___set_cc___ ae, %1
%endm
%macro setb 1.nolist
  ___set_cc___ b, %1
%endm
%macro setbe 1.nolist
  ___set_cc___ be, %1
%endm
%macro setc 1.nolist
  ___set_cc___ c, %1
%endm
%macro sete 1.nolist
  ___set_cc___ e, %1
%endm
%macro setg 1.nolist
  ___set_cc___ g, %1
%endm
%macro setge 1.nolist
  ___set_cc___ ge, %1
%endm
%macro setl 1.nolist
  ___set_cc___ l, %1
%endm
%macro setle 1.nolist
  ___set_cc___ le, %1
%endm
%macro setna 1.nolist
  ___set_cc___ na, %1
%endm
%macro setnae 1.nolist
  ___set_cc___ nae, %1
%endm
%macro setnb 1.nolist
  ___set_cc___ nb, %1
%endm
%macro setnbe 1.nolist
  ___set_cc___ nbe, %1
%endm
%macro setnc 1.nolist
  ___set_cc___ nc, %1
%endm
%macro setne 1.nolist
  ___set_cc___ ne, %1
%endm
%macro setng 1.nolist
  ___set_cc___ ng, %1
%endm
%macro setnge 1.nolist
  ___set_cc___ nge, %1
%endm
%macro setnl 1.nolist
  ___set_cc___ nl, %1
%endm
%macro setnle 1.nolist
  ___set_cc___ nle, %1
%endm
%macro setno 1.nolist
  ___set_cc___ no, %1
%endm
%macro setnp 1.nolist
  ___set_cc___ np, %1
%endm
%macro setns 1.nolist
  ___set_cc___ ns, %1
%endm
%macro setnz 1.nolist
  ___set_cc___ nz, %1
%endm
%macro seto 1.nolist
  ___set_cc___ o, %1
%endm
%macro setp 1.nolist
  ___set_cc___ p, %1
%endm
%macro setpe 1.nolist
  ___set_cc___ pe, %1
%endm
%macro setpo 1.nolist
  ___set_cc___ po, %1
%endm
%macro sets 1.nolist
  ___set_cc___ s, %1
%endm
%macro setz 1.nolist
  ___set_cc___ z, %1
%endm

; push imm: write the value into a slot reserved with a dummy push.
; Registers and flags are unchanged.  Register and memory operands are
; passed through.
%macro push 1.nolist
  %push __CTX_PUSH__
  %assign %$imm 1
  %ifidni %1,ax
    %assign %$imm 0
  %elifidni %1,bx
    %assign %$imm 0
  %elifidni %1,cx
    %assign %$imm 0
  %elifidni %1,dx
    %assign %$imm 0
  %elifidni %1,si
    %assign %$imm 0
  %elifidni %1,di
    %assign %$imm 0
  %elifidni %1,bp
    %assign %$imm 0
  %elifidni %1,sp
    %assign %$imm 0
  %elifidni %1,cs
    %assign %$imm 0
  %elifidni %1,ds
    %assign %$imm 0
  %elifidni %1,es
    %assign %$imm 0
  %elifidni %1,ss
    %assign %$imm 0
  %else
    ; memory if there is a '[' anywhere in the operand
    %defstr %$s %1
    %strlen %$n %$s
    %assign %$i 1
    %rep %$n
      %substr %$c %$s %$i
      %ifidn %$c,"["
        %assign %$imm 0
      %endif
      %assign %$i %$i+1
    %endrep
  %endif
  %if %$imm
    push ax
    push bp
    mov  bp, sp
    mov  word [bp + 2], %1
    pop  bp
  %else
    push %1
  %endif
  %pop ; __CTX_PUSH__
%endm

; Shifts and rotates by an immediate count other than 1: repeat the
; shift by 1.  A count in cl is passed through.
%macro ___shift___ 3.nolist
  %ifidni %3,cl
    %1 %2, cl
  %else
    %rep (%3)
      %1 %2, 1
    %endrep
  %endif
%endm

%macro shl 2.nolist
  ___shift___ shl, %1, %2
%endm
%macro shr 2.nolist
  ___shift___ shr, %1, %2
%endm
%macro sal 2.nolist
  ___shift___ sal, %1, %2
%endm
%macro sar 2.nolist
  ___shift___ sar, %1, %2
%endm
%macro rol 2.nolist
  ___shift___ rol, %1, %2
%endm
%macro ror 2.nolist
  ___shift___ ror, %1, %2
%endm
%macro rcl 2.nolist
  ___shift___ rcl, %1, %2
%endm
%macro rcr 2.nolist
  ___shift___ rcr, %1, %2
%endm

; leave: the same as mov sp, bp / pop bp.
%macro leave 0.nolist
  mov sp, bp
  pop bp
%endm

; imul reg, r/m, imm: the low word of a product is the same signed or
; unsigned, so use mul.  Other registers are kept; the flags are not.
%macro imul 3.nolist
  %ifidni %1,ax
    push dx
    push cx
    mov  ax, %2
    mov  cx, %3
    mul  cx
    pop  cx
    pop  dx
  %elifidni %1,cx
    push ax
    push dx
    mov  ax, %2
    mov  cx, %3
    mul  cx
    mov  cx, ax
    pop  dx
    pop  ax
  %elifidni %1,dx
    push ax
    push cx
    mov  ax, %2
    mov  cx, %3
    mul  cx
    mov  dx, ax
    pop  cx
    pop  ax
  %else
    push ax
    push cx
    push dx
    mov  ax, %2
    mov  cx, %3
    mul  cx
    mov  %1, ax
    pop  dx
    pop  cx
    pop  ax
  %endif
%endm
