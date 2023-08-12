%define T_void 				0
%define T_nil 				1
%define T_char 				2
%define T_string 			3
%define T_symbol 			4
%define T_closure 			5
%define T_boolean 			8
%define T_boolean_false 		(T_boolean | 1)
%define T_boolean_true 			(T_boolean | 2)
%define T_number 			16
%define T_rational 			(T_number | 1)
%define T_real 				(T_number | 2)
%define T_collection 			32
%define T_pair 				(T_collection | 1)
%define T_vector 			(T_collection | 2)

%define SOB_CHAR_VALUE(reg) 		byte [reg + 1]
%define SOB_PAIR_CAR(reg)		qword [reg + 1]
%define SOB_PAIR_CDR(reg)		qword [reg + 1 + 8]
%define SOB_STRING_LENGTH(reg)		qword [reg + 1]
%define SOB_VECTOR_LENGTH(reg)		qword [reg + 1]
%define SOB_CLOSURE_ENV(reg)		qword [reg + 1]
%define SOB_CLOSURE_CODE(reg)		qword [reg + 1 + 8]

%define OLD_RDP 			qword [rbp]
%define RET_ADDR 			qword [rbp + 8 * 1]
%define ENV 			qword [rbp + 8 * 2]
%define COUNT 				qword [rbp + 8 * 3]
%define PARAM(n) 			qword [rbp + 8 * (4 + n)]
%define AND_KILL_FRAME(n)		(8 * (2 + n))

%macro ENTER 0
	enter 0, 0
	and rsp, ~15
%endmacro

%macro LEAVE 0
	leave
%endmacro

%macro assert_type 2
        cmp byte [%1], %2
        jne L_error_incorrect_type
%endmacro

%macro assert_type_integer 1
        assert_rational(%1)
        cmp qword [%1 + 1 + 8], 1
        jne L_error_incorrect_type
%endmacro

%macro FIX_STACK 0

    mov rcx, rax ; save rax in rcx

    ;rsp points to end of blue (rbp in f)
    ;rbp points to end of green 

    mov rdx, [rsp + 8 * 3]  ; rdx = num of args h = m
    mov rsi, rdx  
    add rsi, 3          ; rsi =  how much we need to add to rsp to get to top of blue
    mov rdi, rsi
    add rdi, 4          ; rdi = size of blue +4 (how much we need to go up from rsp to n)

    ; the next calculetion :rsp + (rdi*8) = num of args g = n

    mov rax, 8          ; rax = qword_size
    mul rdi
    mov rdi, rax 
    add rdi, rsp        ; rdi = address num of args g  
    mov rdx, [rdi]      ; rdx = num of args g = n
    mov rax, 8          
    mul rdx             
    mov rdx, rax
    add rdi, rdx        ; rdi = address of top stack of g (green)

    
    %%args_copy_loop:
        cmp rsi, (-1)   ; rsi + 1 = size of blue
        je %%finish_args_copy_loop
        mov rbx, rsi 
        mov rax, 8 
        mul rbx
        mov rbx, rax     
        add rbx, rsp    ; rbx = address of the next one to copy
        mov rbx, [rbx]  ; rbx = the next one to copy

        mov [rdi], rbx  ; overwrite    (copy)

        sub rdi, 8      ; rdi = address of the next one to overwrite
        dec rsi         ; rsi = the number we still need to copy
        jmp %%args_copy_loop

    %%finish_args_copy_loop:
    add rdi, 8          ; rdi = buttom of green (new blue)  
    mov rsp, rdi

    mov rax, rcx        ; return rax its original value
%endmacro


%macro MAKE_PAIR 3 
        push rdi 
        mov rdi, (17)   ; TYPE_SIZE + WORD_SIZE*2        
        call malloc  
        pop rdi                
        mov byte [%1], T_pair
        mov SOB_PAIR_CAR (%1), %2
        mov SOB_PAIR_CDR (%1), %3
        
%endmacro

%macro MORE_PARAM 1    ; maybe needs to be uniqe
    mov r8, qword [rsp + 8 * 2]         ; r8 = real numbere of arguments = n (params + opt) 
    mov r11, r8
    mov rdx, %1                         ; rdx = List.length params'
    sub r8, rdx 
    mov r10, r8                         ; r10= save the number of opt 
    add r11, 2                          ; r11 = placement of top of the frame
    xor r9, r9
    mov r9, r11                         ; r9 = placement of next param to add to the list  

    mov rbx, qword[rsp + 8*r9]          ; rbx= next param to add to the list 
    mov rcx, sob_nil
    MAKE_PAIR rax,rbx,rcx 
    dec r9
    dec r8
    cmp r8,0
    je %%end_more


    %%pair_loop:
        mov rcx, rax                    ; rcx = curr pair 
        mov rbx, qword[rsp + 8*r9]
        MAKE_PAIR rax,rbx,rcx
        dec r9
        dec r8
        cmp r8,0
        jg %%pair_loop  

    %%end_more:                         ; add list to stack 
    inc r9                              ; buttom opt
    mov qword [rsp+8*r9], rax
    mov qword [rsp + 8 * 2], %1         
    inc qword [rsp+ 8 * 2]              ; changed n to be num of param + 1 (list)
    mov rsi, r9                         ;counter how much we need to copy
    dec r10                             
    add r9, r10                         ; param + opt num + ret, lex , n
    mov rdi, r9
    mov rax, 8                          ; rax = qword_size
    mul rdi
    mov rdi, rax 
    add rdi, rsp                        ; rdi = address top of stack (the address we want to copy into)

    %%args_copy_loop_1:
    cmp rsi, (-1)   
    je %%finish_args_copy_loop_1
    mov rbx, rsi 
    mov rax, 8 
    mul rbx
    mov rbx, rax     
    add rbx, rsp    ; rbx = address of the next one to copy
    mov rbx, [rbx]  ; rbx = the next one to copy

    mov [rdi], rbx  ; overwrite    (copy)

    sub rdi, 8      ; rdi = address of the next one to overwrite
    dec rsi         ; rsi = the number we still need to copy
    jmp %%args_copy_loop_1

    %%finish_args_copy_loop_1:
        mov rax, 8
        mul r10
        mov r10, rax
        add rsp, r10
%endmacro

%macro EXACT_PARAM 1
    mov r8, %1                     ; r8 = num param 
    add r8, 3                      ; r8 = num we want to move down
    mov rdx, rsp
    sub rdx, 8                     ; rdx = next address we want to copy into
    mov r10, 0                     ; r10 = next placement to copy 

    %%copy_down_loop:
        mov r15, qword[rsp + 8 * r10]  ; r15 = next to copy
        mov qword[rdx], r15
        inc r10       
        add rdx, 8                 ; next place we want to copy into
        cmp r10, r8
        je %%finish_down_loop
        jmp %%copy_down_loop

    %%finish_down_loop: 
       mov qword[rdx], sob_nil
       mov r11, %1
       inc r11
       mov qword[rsp + 8 * 1], r11  ; update to num of n (param + 1)
       sub rsp, 8           
%endmacro


%define assert_void(reg)		assert_type reg, T_void
%define assert_nil(reg)			assert_type reg, T_nil
%define assert_char(reg)		assert_type reg, T_char
%define assert_string(reg)		assert_type reg, T_string
%define assert_symbol(reg)		assert_type reg, T_symbol
%define assert_closure(reg)		assert_type reg, T_closure
%define assert_boolean(reg)		assert_type reg, T_boolean
%define assert_rational(reg)	assert_type reg, T_rational
%define assert_integer(reg)		assert_type_integer reg
%define assert_real(reg)		assert_type reg, T_real
%define assert_pair(reg)		assert_type reg, T_pair
%define assert_vector(reg)		assert_type reg, T_vector

%define sob_void			(L_constants + 0)
%define sob_nil				(L_constants + 1)
%define sob_boolean_false		(L_constants + 2)
%define sob_boolean_true		(L_constants + 3)
%define sob_char_nul			(L_constants + 4)

%define bytes(n)			(n)
%define kbytes(n) 			(bytes(n) << 10)
%define mbytes(n) 			(kbytes(n) << 10)
%define gbytes(n) 			(mbytes(n) << 10)

section .data
section .data
message: db "error", 10, 0
fmt: db "%s", 10, 0
