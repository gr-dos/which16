;
; which - locate a program the way COMMAND.COM would
;
; An 8086 assembly version of which.c, as a .COM program, using only
; DOS 2.0 calls.  which.c is the specification: the lookup, options,
; messages and exit status are the same; see the comments there.
;
; Build: nasm -f bin -DVERSION='"0.01"' -o which.com which.asm
;
; SPDX-License-Identifier: MIT
;

cpu 8086
bits 16
org 0x100

%ifndef VERSION
%define VERSION "unknown"
%endif

MAX_PATH    equ 80          ; as libc16's _MAX_PATH
FULL_WORK   equ 256         ; libc16's _fullpath work buffer
MAXDIRS     equ 64
ATTRS       equ 0x03        ; read-only and hidden
STACK       equ 512

; PSP
ENVSEG      equ 0x2c
TAILLEN     equ 0x80
TAIL        equ 0x81

; DTA, from find first
DTA_ATTR    equ 0x15
DTA_NAME    equ 0x1e

section .text

start:
        cld
        mov     ax, sp
        sub     ax, STACK
        jc      nomem
        cmp     ax, heap
        jb      nomem
        push    ax
        mov     di, bss                 ; DOS does not clear it
        mov     cx, heap - bss
        xor     al, al
        rep     stosb
        pop     word [heap_limit]
        mov     word [heap_ptr], heap

        mov     dx, dta
        mov     ah, 0x1a
        int     0x21

        call    parse_tail

; First pass: options.  Each option is replaced by 0 in argv.
        mov     bx, argv
.opt:
        cmp     bx, [argv_end]
        jae     .optdone
        mov     si, [bx]
        cmp     byte [endopts], 0
        jne     .name
        cmp     byte [si], '-'
        jne     .name
        cmp     byte [si + 1], 0
        je      .name
        cmp     byte [si + 1], '-'
        jne     .short
        cmp     byte [si + 2], 0
        jne     .long
        mov     byte [endopts], 1
        jmp     .used
.long:
        mov     di, s_all
        call    strcmp
        je      .all
        mov     di, s_silent
        call    strcmp
        je      .silent
        mov     di, s_help
        call    strcmp
        je      help
        mov     di, s_version
        call    strcmp
        je      version
        push    si
        call    lb_start
        mov     si, m_unrec
        call    lb_add
        pop     si
        call    lb_add
        mov     si, m_quote_nl
        jmp     .usage
.short:
        inc     si
.letter:
        lodsb
        test    al, al
        jz      .used
        cmp     al, 'a'
        je      .short_all
        cmp     al, 's'
        je      .short_silent
        cmp     al, 'h'
        je      help
        cmp     al, '?'
        je      help
        push    ax
        call    lb_start
        mov     si, m_invalid
        call    lb_add
        pop     ax
        call    lb_addc
        mov     si, m_quote_nl
        jmp     .usage
.short_all:
        mov     byte [opt_all], 1
        jmp     .letter
.short_silent:
        mov     byte [opt_silent], 1
        jmp     .letter
.all:
        mov     byte [opt_all], 1
        jmp     .used
.silent:
        mov     byte [opt_silent], 1
.used:
        mov     word [bx], 0
        jmp     .optnext
.name:
        inc     word [nnames]
.optnext:
        inc     bx
        inc     bx
        jmp     .opt
.optdone:
        cmp     word [nnames], 0
        jne     .search
        call    lb_start
        mov     si, m_missing
.usage:                         ; print the line buffer, then SI, then "Try"
        call    lb_add
        mov     bx, 2
        call    lb_flush
        mov     si, m_try
        call    write_str
        mov     al, 1
        jmp     exit

; Second pass: look for each name.
.search:
        call    build_dirs
        mov     word [argi], argv
.each:
        mov     bx, [argi]
        cmp     bx, [argv_end]
        jae     .done
        mov     si, [bx]
        test    si, si
        jz      .next
        call    which
        test    ax, ax
        jnz     .next
        mov     byte [status], 1
        cmp     byte [opt_silent], 0
        jne     .next
        call    lb_start
        mov     si, m_which
        call    lb_add
        mov     bx, [argi]
        mov     si, [bx]
        call    lb_add
        mov     si, m_notfound
        call    lb_add
        mov     bx, 2
        call    lb_flush
.next:
        add     word [argi], 2
        jmp     .each
.done:
        mov     al, [status]
exit:
        mov     ah, 0x4c
        int     0x21

help:
        mov     si, m_usage
        jmp     print_exit0
version:
        mov     si, m_version
print_exit0:
        mov     bx, 1
        call    write_str
        mov     al, 0
        jmp     exit

nomem:
        mov     dx, m_nomem
        mov     ah, 0x09
        int     0x21
        mov     al, 1
        jmp     exit

;
; Split the command tail into argv as libc16 does, which is Microsoft
; C's rule: arguments are separated by spaces and tabs, double quotes
; group (and are removed), a run of 2n backslashes before a quote gives
; n backslashes and a toggle, 2n + 1 give n backslashes and a literal
; quote, and any other backslash is literal.
;
parse_tail:
        mov     si, TAIL
        mov     bl, [TAILLEN]
        cmp     bl, 126
        jbe     .len
        mov     bl, 126
.len:
        mov     bh, 0
        mov     byte [si + bx], 0x0d
        mov     di, argbuf
        mov     bx, argv
.skip:
        lodsb
        cmp     al, ' '
        je      .skip
        cmp     al, 9
        je      .skip
        cmp     al, 0x0d
        je      .done
        dec     si
        mov     [bx], di
        inc     bx
        inc     bx
        mov     dl, 0                   ; inside quotes
.char:
        lodsb
        cmp     al, 0x0d
        je      .last
        cmp     al, '\'
        je      .run
        cmp     al, '"'
        jne     .notquote
        xor     dl, 1
        jmp     .char
.notquote:
        test    dl, dl
        jnz     .store
        cmp     al, ' '
        je      .end
        cmp     al, 9
        je      .end
.store:
        stosb
        jmp     .char
.run:
        mov     ah, 0                   ; AH = backslashes in the run
.count:
        inc     ah
        lodsb
        cmp     al, '\'
        je      .count
        dec     si                      ; the byte after the run is next
        cmp     al, '"'
        mov     al, '\'
        jne     .lits
        shr     ah, 1                   ; n
        sbb     dh, dh                  ; DH = -1 for 2n + 1
.half:
        test    ah, ah
        jz      .dquote
        stosb
        dec     ah
        jmp     .half
.dquote:
        test    dh, dh
        jz      .char                   ; 2n: the '"' toggles when read
        movsb                           ; 2n + 1: a literal '"'
        jmp     .char
.lits:
        stosb                           ; no '"' follows: all literal
        dec     ah
        jnz     .lits
        jmp     .char
.end:
        mov     al, 0
        stosb
        jmp     .skip
.last:
        mov     al, 0
        stosb
.done:
        mov     [argv_end], bx
        ret

;
; Collect the directories in PATH, made absolute and deduplicated.
;
build_dirs:
        mov     ax, [ENVSEG]
        test    ax, ax
        jz      .ret
        mov     es, ax
        xor     bx, bx
.var:
        cmp     byte [es:bx], 0
        je      .noenv
        mov     si, s_path
        mov     di, bx
        mov     cx, 5
        repe    cmpsb
        je      .found
.skipvar:
        inc     bx
        cmp     byte [es:bx - 1], 0
        jne     .skipvar
        jmp     .var
.found:                                 ; copy the value to the heap
        mov     si, di
        mov     di, [heap_ptr]
        mov     [bd_next], di
        mov     cx, 256                 ; libc16's getenv takes at most
.copy:                                  ; 255 bytes, or there is no PATH
        cmp     di, [heap_limit]
        jae     .full
        mov     al, [es:si]
        inc     si
        mov     [di], al
        inc     di
        test    al, al
        loopnz  .copy
        jz      .copied
        jmp     .noenv
.full:
        mov     byte [di], 0
        inc     di
.copied:
        mov     [heap_ptr], di
        push    ds
        pop     es

        mov     si, [bd_next]
.entry:                                 ; si: start of an entry
        cmp     byte [si], 0
        je      .ret
        mov     bx, si
.find:
        lodsb
        test    al, al
        jz      .eos
        cmp     al, ';'
        jne     .find
        mov     [bd_next], si
        jmp     .trim
.eos:
        mov     word [bd_next], 0
.trim:
        dec     si                      ; si: end of the entry
.trimr:
        cmp     si, bx
        jbe     .triml
        cmp     byte [si - 1], ' '
        jne     .triml
        dec     si
        jmp     .trimr
.triml:
        cmp     bx, si
        jae     .nextentry
        cmp     byte [bx], ' '
        jne     .trimmed
        inc     bx
        jmp     .triml
.trimmed:
        mov     cx, si
        sub     cx, bx
        cmp     cx, MAX_PATH
        jae     .nextentry
        mov     si, bx
        mov     di, entry
        rep     movsb
        mov     byte [di], 0
        call    add_dir
.nextentry:
        mov     si, [bd_next]
        test    si, si
        jnz     .entry
.ret:
        ret
.noenv:
        push    ds
        pop     es
        ret

; Add the directory in entry unless it is already there.
add_dir:
        cmp     word [dirs_end], dirs + 2 * MAXDIRS
        jae     .ret
        mov     si, entry
        mov     di, dirtmp
        call    normalize
        jc      .ret
        mov     bx, dirs
.cmp:
        cmp     bx, [dirs_end]
        jae     .add
        mov     si, [bx]
        mov     di, dirtmp
        call    strcmp
        je      .ret
        inc     bx
        inc     bx
        jmp     .cmp
.add:
        mov     si, dirtmp
        call    strlen
        inc     cx
        mov     di, [heap_ptr]
        mov     ax, di
        add     ax, cx
        jc      .ret
        cmp     ax, [heap_limit]
        ja      .ret
        mov     [bx], di
        rep     movsb
        mov     [heap_ptr], di
        add     word [dirs_end], 2
.ret:
        ret

;
; Look for the name at SI.  Prints what is found; AX = 1 if anything
; was, 0 if not.
;
which:
        mov     [w_name], si
.wild:
        lodsb
        cmp     al, '*'
        je      .no
        cmp     al, '?'
        je      .no
        test    al, al
        jnz     .wild

        ; split off any drive or directory
        mov     si, [w_name]
        mov     [w_base], si
        mov     byte [w_hasdir], 0
.split:
        lodsb
        test    al, al
        jz      .splitdone
        cmp     al, ':'
        je      .drive
        call    is_sep
        jne     .split
        mov     byte [w_hasdir], 1
.drive:
        mov     [w_base], si
        jmp     .split
.splitdone:
        mov     si, [w_base]
        cmp     byte [si], 0
        je      .no
        mov     cx, si
        sub     cx, [w_name]
        cmp     cx, MAX_PATH
        jae     .no

        ; first where NAME says: "C:" alone is C's current directory
        mov     si, [w_name]
        mov     di, dirbuf
        rep     movsb
        mov     byte [di], 0
        mov     ax, di
        sub     ax, dirbuf
        cmp     ax, 2
        jne     .norm
        cmp     byte [dirbuf + 1], ':'
        jne     .norm
        mov     word [di], '.'
.norm:
        mov     si, dirbuf
        mov     di, first
        call    normalize
        jc      .no
        mov     si, first
        call    search_dir
        mov     [w_count], ax

        ; then PATH, unless NAME has a directory
        cmp     byte [w_hasdir], 0
        jne     .ret
        mov     word [w_dir], dirs
.path:
        mov     bx, [w_dir]
        cmp     bx, [dirs_end]
        jae     .ret
        cmp     word [w_count], 0
        je      .try
        cmp     byte [opt_all], 0
        je      .ret
.try:
        mov     si, [bx]
        mov     di, first
        call    strcmp
        je      .pathnext
        mov     bx, [w_dir]
        mov     si, [bx]
        call    search_dir
        add     [w_count], ax
.pathnext:
        add     word [w_dir], 2
        jmp     .path
.ret:
        cmp     word [w_count], 0
        je      .no
        mov     ax, 1
        ret
.no:
        xor     ax, ax
        ret

;
; Look in the directory at SI for the name at w_base: as given if it has
; an extension, otherwise with each program extension in turn.  Prints
; what is found, stopping at the first unless -a.  AX = matches.
;
search_dir:
        mov     [s_dir], si
        call    strlen
        mov     dx, cx
        mov     si, [w_base]
        call    strlen
        add     cx, dx
        add     cx, 6
        cmp     cx, MAX_PATH + 16
        ja      .none
        mov     word [s_count], 0
        mov     si, [w_base]
.dot:
        lodsb
        test    al, al
        jz      .exts
        cmp     al, '.'
        jne     .dot
        call    pat_dir
        mov     si, [w_base]
        call    stpcpy
        jmp     find

.exts:
        mov     word [s_ext], exts
.ext:
        call    pat_dir
        mov     si, [w_base]
        call    stpcpy
        mov     al, '.'
        stosb
        mov     si, [s_ext]
        call    stpcpy
        call    find
        test    ax, ax
        jz      .extnext
        inc     word [s_count]
        cmp     byte [opt_all], 0
        je      .extdone
.extnext:
        add     word [s_ext], 4
        cmp     word [s_ext], exts_end
        jb      .ext
.extdone:
        mov     ax, [s_count]
        ret
.none:
        xor     ax, ax
        ret

; DI = pat with "dir\" in it, at the end.
pat_dir:
        mov     di, pat
        mov     si, [s_dir]
        call    stpcpy
        mov     al, '\'
        stosb
        ret

;
; Find the first match for pat.  If it is a program (not a directory or
; system file, with extension .COM, .EXE or .BAT), print s_dir\NAME
; unless -s.  AX = 1 if it was.
;
find:
        mov     dx, pat
        mov     cx, ATTRS
        mov     ah, 0x4e
        int     0x21
        jc      .no
        test    byte [dta + DTA_ATTR], 0x14
        jnz     .no
        mov     si, dta + DTA_NAME
        xor     bx, bx
.lastdot:
        lodsb
        test    al, al
        jz      .gotdot
        cmp     al, '.'
        jne     .lastdot
        mov     bx, si
        jmp     .lastdot
.gotdot:
        test    bx, bx
        jz      .no
        mov     di, exts
.ext:
        mov     si, bx
        push    di
        call    stricmp
        pop     di
        je      .prog
        add     di, 4
        cmp     di, exts_end
        jb      .ext
.no:
        xor     ax, ax
        ret
.prog:
        cmp     byte [opt_silent], 0
        jne     .yes
        mov     si, dta + DTA_NAME
        call    strlwr
        call    lb_start
        mov     si, [s_dir]
        call    lb_add
        mov     bx, [lbp]
        cmp     byte [bx - 1], '\'
        je      .sep
        mov     al, '\'
        call    lb_addc
.sep:
        mov     si, dta + DTA_NAME
        call    lb_add
        mov     al, 10
        call    lb_addc
        mov     bx, 1
        call    lb_flush
.yes:
        mov     ax, 1
        ret

;
; Make the directory at SI absolute in DI: lower case, and with no
; trailing backslash except at a root.  CF if it cannot be.
;
normalize:
        mov     [n_out], di
        cmp     byte [si], 0
        jne     .full
        mov     si, s_dot
.full:
        call    fullpath
        jc      .ret
        mov     si, fullbuf
        call    strlen
        cmp     cx, 3
        jbe     .lower
        mov     bx, si
        add     bx, cx
        cmp     byte [bx - 1], '\'
        jne     .lower
        mov     byte [bx - 1], 0
.lower:
        call    strlwr
        mov     si, fullbuf
        mov     di, [n_out]
        call    stpcpy
        clc
.ret:
        ret

;
; Make the path at SI absolute in fullbuf, as libc16's _fullpath does
; (its docs/spec/dos.md): the drive (as typed, or the current one) in
; upper case, ":\", then, unless the path starts with a separator,
; that drive's current directory, then the path.  Components are
; joined by single backslashes, "/" counts as "\", "." is dropped and
; ".." removes the last component (stopping at the root).  CF for an
; empty path, a drive that is not a letter or not valid, or a result
; that needs more than MAX_PATH bytes with its terminator.
;
fullpath:
        cmp     byte [si], 0
        je      .fail
        cmp     byte [si + 1], ':'
        jne     .curdrive
        mov     al, [si]
        or      al, 0x20
        sub     al, 'a'
        cmp     al, 'z' - 'a'
        ja      .fail
        inc     si
        inc     si
        jmp     .drive
.curdrive:
        mov     ah, 0x19
        int     0x21
.drive:
        mov     di, fullbuf
        mov     dl, al
        add     al, 'A'
        stosb
        mov     ax, ':' | ('\' << 8)
        stosw
        push    si
        inc     dl                      ; the current directory, which
        mov     si, cwdbuf              ; also checks the drive
        mov     ah, 0x47
        int     0x21
        pop     si
        jc      .fail
        mov     al, [si]
        call    is_sep
        je      .path
        push    si
        mov     si, cwdbuf
        call    add_parts
        pop     si
        jc      .fail
.path:
        call    add_parts
        jc      .fail
        mov     ax, di
        sub     ax, fullbuf
        cmp     ax, MAX_PATH
        jae     .fail
        mov     byte [di], 0
        clc
        ret
.fail:
        stc
        ret

; Add the components of the path at SI to the one in fullbuf, which
; ends at DI.  CF if the result would not fit in FULL_WORK bytes.
add_parts:
.skip:
        lodsb
        call    is_sep
        je      .skip
        test    al, al
        jz      .done
        lea     bx, [si - 1]            ; BX = the component
.scan:
        lodsb
        test    al, al
        jz      .scanned
        call    is_sep
        jne     .scan
.scanned:
        dec     si
        mov     cx, si
        sub     cx, bx                  ; CX = its length
        cmp     byte [bx], '.'
        jne     .copy
        cmp     cx, 1
        je      .skip                   ; "."
        cmp     cx, 2
        jne     .copy
        cmp     byte [bx + 1], '.'
        jne     .copy
.up:                                    ; "..": drop the last component
        cmp     di, fullbuf + 3
        jbe     .skip
        dec     di
        cmp     byte [di], '\'
        jne     .up
        jmp     .skip
.copy:
        mov     ax, di
        sub     ax, fullbuf
        cmp     di, fullbuf + 3
        jbe     .room
        inc     ax                      ; for the backslash
.room:
        add     ax, cx
        cmp     ax, FULL_WORK
        jae     .full
        cmp     di, fullbuf + 3
        jbe     .append
        mov     byte [di], '\'
        inc     di
.append:
        push    si
        mov     si, bx
        rep     movsb
        pop     si
        jmp     .skip
.done:
        clc
        ret
.full:
        stc
        ret

; ZF if AL is a path separator.
is_sep:
        cmp     al, '\'
        je      .ret
        cmp     al, '/'
.ret:
        ret

;
; Strings.  All take zero-terminated strings.
;

; CX = length of SI.
strlen:
        push    si
        xor     cx, cx
.loop:
        lodsb
        test    al, al
        jz      .ret
        inc     cx
        jmp     .loop
.ret:
        pop     si
        ret

; Copy SI to DI; DI is left at the terminating 0.
stpcpy:
        lodsb
        stosb
        test    al, al
        jnz     stpcpy
        dec     di
        ret

; ZF if SI and DI are equal.  SI is kept.
strcmp:
        push    si
.loop:
        lodsb
        cmp     al, [di]
        jne     .ret
        inc     di
        test    al, al
        jnz     .loop
.ret:
        pop     si
        ret

; ZF if SI and DI are equal, ignoring ASCII case.
stricmp:
        lodsb
        call    tolower
        mov     ah, al
        mov     al, [di]
        inc     di
        call    tolower
        cmp     ah, al
        jne     .ret
        test    al, al
        jnz     stricmp
.ret:
        ret

; Lower-case SI in place.
strlwr:
        mov     al, [si]
        test    al, al
        jz      .ret
        call    tolower
        mov     [si], al
        inc     si
        jmp     strlwr
.ret:
        ret

tolower:
        cmp     al, 'A'
        jb      .ret
        cmp     al, 'Z'
        ja      .ret
        or      al, 0x20
.ret:
        ret

;
; Output.  Lines are built in linebuf and written to a handle, with
; "\n" written as CR LF as the C runtime does.
;

lb_start:
        mov     word [lbp], linebuf
        ret

; Append SI.
lb_add:
        lodsb
        test    al, al
        jz      .ret
        call    lb_addc
        jmp     lb_add
.ret:
        ret

; Append AL.
lb_addc:
        push    di
        mov     di, [lbp]
        stosb
        mov     [lbp], di
        pop     di
        ret

; Write the line buffer to handle BX.
lb_flush:
        mov     si, [lbp]
        mov     byte [si], 0
        mov     si, linebuf
        ; fall through

; Write SI to handle BX.
write_str:
        mov     dx, si
.scan:
        lodsb
        test    al, al
        jz      .last
        cmp     al, 10
        jne     .scan
        push    si
        mov     cx, si
        dec     cx
        sub     cx, dx
        call    write
        mov     dx, crlf
        mov     cx, 2
        call    write
        pop     si
        jmp     write_str
.last:
        mov     cx, si
        dec     cx
        sub     cx, dx
write:                                  ; CX bytes at DX to handle BX
        jcxz    .ret
        mov     ah, 0x40
        int     0x21
.ret:
        ret

section .data

m_usage:
        db      "Usage: which [OPTION]... NAME...", 10
        db      "Show the full path of the program COMMAND.COM runs for each NAME.", 10
        db      10
        db      "The current directory is searched, then each directory in PATH,", 10
        db      "for NAME.COM, NAME.EXE and NAME.BAT.  A NAME with an extension is", 10
        db      "looked for only as given, and one with a directory only there.", 10
        db      10
        db      "  -a, --all      print every match, not just the first", 10
        db      "  -s, --silent   print nothing; the exit status shows the result", 10
        db      "  -h, --help     display this help and exit", 10
        db      "      --version  output version information and exit", 10
        db      10
        db      "Exit status is 0 if every NAME was found, 1 otherwise.", 10, 0
m_version:  db  "which (dos-which16) ", VERSION, 10, 0
m_unrec:    db  "which: unrecognized option '", 0
m_invalid:  db  "which: invalid option -- '", 0
m_quote_nl: db  "'", 10, 0
m_missing:  db  "which: missing operand", 10, 0
m_try:      db  "Try 'which --help' for more information.", 10, 0
m_which:    db  "which: ", 0
m_notfound: db  ": not found", 10, 0
m_nomem:    db  "which: not enough memory", 13, 10, "$"
s_all:      db  "--all", 0
s_silent:   db  "--silent", 0
s_help:     db  "--help", 0
s_version:  db  "--version", 0
s_path:     db  "PATH="
s_dot:      db  ".", 0
crlf:       db  13, 10
exts:       db  "com", 0, "exe", 0, "bat", 0
exts_end:
dirs_end:   dw  dirs

section .bss

bss:
opt_all:    resb 1
opt_silent: resb 1
endopts:    resb 1
status:     resb 1
w_hasdir:   resb 1
nnames:     resw 1
argv_end:   resw 1
argi:       resw 1
heap_limit: resw 1
heap_ptr:   resw 1
bd_next:    resw 1
w_name:     resw 1
w_base:     resw 1
w_count:    resw 1
w_dir:      resw 1
s_dir:      resw 1
s_count:    resw 1
s_ext:      resw 1
n_out:      resw 1
lbp:        resw 1
argv:       resw 64
dirs:       resw MAXDIRS
argbuf:     resb 192
linebuf:    resb 320
dta:        resb 44
entry:      resb MAX_PATH
dirbuf:     resb MAX_PATH + 2
first:      resb MAX_PATH
dirtmp:     resb MAX_PATH
pat:        resb MAX_PATH + 16
fullbuf:    resb FULL_WORK
cwdbuf:     resb 64
heap:
