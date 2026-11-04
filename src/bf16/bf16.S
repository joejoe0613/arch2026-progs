# BFloat16 routines: hand-written RV32I.
#
# uint16_t bf16_from_f32_asm(uint32_t f32bits)   a0 -> a0
# uint16_t bf16_mul_asm(uint16_t a, uint16_t b)  a0, a1 -> a0
# uint16_t bf16_sqrt_asm(uint16_t a)             a0 -> a0
#
# RV32I and Zicsr only: no mul, div, rem, no floating point, no compressed
# instructions. Tests: tests/tbf16.c.

    .text

    .globl bf16_from_f32_asm
    .type  bf16_from_f32_asm, @function
    .align 2

bf16_from_f32_asm:
    # Input: a0 = Float32 raw bits
    # Output: a0 = BF16 raw bits

    # Step 1: Extract exponent
    srli t0, a0, 23
    andi t0, t0, 0xff

    # Check exponent == 255
    li   t1, 255
    beq  t0, t1, .Lf32_special

    # Step 2: Round to nearest, ties to even
    srli t0, a0, 16
    andi t0, t0, 1

    li   t1, 0x7fff
    add  t0, t0, t1
    add  a0, a0, t0

    # Step 3: Keep upper 16 bits
    srli a0, a0, 16
    ret

.Lf32_special:
    # Inf / NaN: preserve upper 16 bits
    srli a0, a0, 16
    ret

    .size bf16_from_f32_asm, .-bf16_from_f32_asm


    .globl bf16_mul_asm
    .type  bf16_mul_asm, @function
    .align 2

bf16_mul_asm:
    # Input:
    #   a0 = BF16 operand a
    #   a1 = BF16 operand b
    # Output:
    #   a0 = BF16 product

    # ----------------------------------------
    # Step 1: Extract sign, exponent, fraction
    # ----------------------------------------

    xor  a2, a0, a1
    li   t0, 0x8000
    and  a2, a2, t0

    srli a3, a0, 7
    andi a3, a3, 255

    srli a4, a1, 7
    andi a4, a4, 255

    andi a5, a0, 127
    andi a6, a1, 127

    # ----------------------------------------
    # Step 2: Check special operand a
    # ----------------------------------------

    li   t0, 255
    bne  a3, t0, .Lmul_check_b

    # NaN a: return original a
    bnez a5, .Lmul_return_a

    # Infinity a times zero b -> quiet NaN
    li   t1, 0x7fff
    and  t2, a1, t1
    beqz t2, .Lmul_nan

    # Otherwise return signed infinity
    j .Lmul_inf

.Lmul_check_b:
    # ----------------------------------------
    # Step 3: Check special operand b
    # ----------------------------------------

    bne  a4, t0, .Lmul_check_zero

    # NaN b: return original b
    bnez a6, .Lmul_return_b

    # Infinity b times zero a -> quiet NaN
    li   t1, 0x7fff
    and  t2, a0, t1
    beqz t2, .Lmul_nan

    j .Lmul_inf

.Lmul_check_zero:
    # ----------------------------------------
    # Step 4: Handle finite zero operands
    # ----------------------------------------

    li   t0, 0x7fff

    and  t1, a0, t0
    beqz t1, .Lmul_zero

    and  t1, a1, t0
    beqz t1, .Lmul_zero

    # ----------------------------------------
    # Step 5: Normalize operand a
    # ----------------------------------------

    bnez a3, .Lmul_a_normal

    # Denormal: shift leading one to bit 7
    li a3, 1

.Lmul_norm_a_loop:
    andi t0, a5, 128
    bnez t0, .Lmul_norm_b

    slli a5, a5, 1
    addi a3, a3, -1
    j .Lmul_norm_a_loop

.Lmul_a_normal:
    ori a5, a5, 128

    # ----------------------------------------
    # Step 6: Normalize operand b
    # ----------------------------------------

.Lmul_norm_b:
    bnez a4, .Lmul_b_normal

    li a4, 1

.Lmul_norm_b_loop:
    andi t0, a6, 128
    bnez t0, .Lmul_multiply

    slli a6, a6, 1
    addi a4, a4, -1
    j .Lmul_norm_b_loop

.Lmul_b_normal:
    ori a6, a6, 128

    # ----------------------------------------
    # Step 7: Software multiplication
    # product = mant_a * mant_b
    # ----------------------------------------

.Lmul_multiply:
    li t0, 0
    mv t1, a5
    mv t2, a6

.Lmul_loop:
    andi t4, t2, 1
    beqz t4, .Lmul_skip_add

    add t0, t0, t1

.Lmul_skip_add:
    slli t1, t1, 1
    srli t2, t2, 1
    bnez t2, .Lmul_loop

    # ----------------------------------------
    # Step 8: Calculate result exponent
    # exp = exp_a + exp_b - 127
    # ----------------------------------------

    addi t3, a3, -127
    add  t3, t3, a4

    # ----------------------------------------
    # Step 9: Normalize product
    # ----------------------------------------

    li  t4, 0x8000
    and t5, t0, t4
    beqz t5, .Lmul_no_extra_shift

    # Product reaches bit 15
    srli t0, t0, 8
    addi t3, t3, 1
    j .Lmul_check_exp

.Lmul_no_extra_shift:
    srli t0, t0, 7

    # ----------------------------------------
    # Step 10: Check overflow and underflow
    # ----------------------------------------

.Lmul_check_exp:
    li  t4, 255
    bge t3, t4, .Lmul_inf

    # exp <= 0
    bge zero, t3, .Lmul_underflow

    # ----------------------------------------
    # Step 11: Pack normal BF16 result
    # ----------------------------------------

    slli t3, t3, 7
    andi t0, t0, 127

    or t3, t3, t0
    or a0, a2, t3
    ret

    # ----------------------------------------
    # Step 12: Underflow handling
    # ----------------------------------------

.Lmul_underflow:
    li  t4, -6
    blt t3, t4, .Lmul_zero

    # Important: remove hidden bit first
    andi t0, t0, 127

    # fraction >>= (1 - result_exp)
    li  t4, 1
    sub t4, t4, t3
    srl t0, t0, t4

    or a0, a2, t0
    ret

    # ----------------------------------------
    # Step 13: Return paths
    # ----------------------------------------

.Lmul_inf:
    li a0, 0x7f80
    or a0, a0, a2
    ret

.Lmul_nan:
    li a0, 0x7fc0
    ret

.Lmul_zero:
    mv a0, a2
    ret

.Lmul_return_a:
    ret

.Lmul_return_b:
    mv a0, a1
    ret

    .size bf16_mul_asm, .-bf16_mul_asm

    .globl bf16_sqrt_asm
    .type  bf16_sqrt_asm, @function
    .align 2

bf16_sqrt_asm:
    # Input:  a0 = BF16 value
    # Output: a0 = BF16 square root

    # ----------------------------------------
    # Step 1: Extract exponent and fraction
    # ----------------------------------------

    srli t1, a0, 7
    andi t1, t1, 255

    andi t2, a0, 127

    # ----------------------------------------
    # Step 2: Handle NaN and Infinity
    # ----------------------------------------

    li  t3, 255
    bne t1, t3, .Lsqrt_finite

    # NaN: preserve original bit pattern
    bnez t2, .Lsqrt_return

    # Infinity: negative gives quiet NaN
    li  t3, 0x8000
    and t0, a0, t3
    bnez t0, .Lsqrt_nan

    # Positive infinity
    ret

.Lsqrt_finite:
    # ----------------------------------------
    # Step 3: Handle zero and negative values
    # ----------------------------------------

    # +0 and -0 both return +0
    li  t3, 0x7fff
    and t0, a0, t3
    beqz t0, .Lsqrt_zero

    # Negative nonzero -> quiet NaN
    li  t3, 0x8000
    and t0, a0, t3
    bnez t0, .Lsqrt_nan

    # Denormal -> +0
    beqz t1, .Lsqrt_zero

    # ----------------------------------------
    # Step 4: Restore hidden bit
    # ----------------------------------------

    ori t2, t2, 128

    # e = exponent - 127
    addi t1, t1, -127

    # ----------------------------------------
    # Step 5: Make exponent even
    # ----------------------------------------

    andi t3, t1, 1
    beqz t3, .Lsqrt_even_exp

    # Odd exponent: double mantissa
    slli t2, t2, 1
    addi t1, t1, -1

.Lsqrt_even_exp:
    # new_exp = e / 2 + 127
    # e is even, so arithmetic shift is exact
    srai t1, t1, 1
    addi t1, t1, 127

    # ----------------------------------------
    # Step 6: Initialize binary search
    # ----------------------------------------

    li a2, 90       # low
    li a3, 256      # high
    li a4, 128      # result

.Lsqrt_search_loop:
    # while (low <= high)
    bltu a3, a2, .Lsqrt_search_done

    # mid = (low + high) >> 1
    add  a5, a2, a3
    srli a5, a5, 1

    # ----------------------------------------
    # Step 7: Compute mid * mid using RV32I
    # ----------------------------------------

    mv t3, a5       # multiplier
    mv a7, a5       # shifted multiplicand
    li a6, 0        # product

.Lsqrt_mul_loop:
    andi t4, t3, 1
    beqz t4, .Lsqrt_skip_add

    add a6, a6, a7

.Lsqrt_skip_add:
    slli a7, a7, 1
    srli t3, t3, 1
    bnez t3, .Lsqrt_mul_loop

    # sq = (mid * mid) >> 7
    srli a6, a6, 7

    # ----------------------------------------
    # Step 8: Compare square with mantissa
    # ----------------------------------------

    # If sq > m, search lower half
    bltu t2, a6, .Lsqrt_search_left

    # sq <= m: update best result
    mv   a4, a5
    addi a2, a5, 1
    j    .Lsqrt_search_loop

.Lsqrt_search_left:
    addi a3, a5, -1
    j    .Lsqrt_search_loop

.Lsqrt_search_done:
    # ----------------------------------------
    # Step 9: Normalize resulting significand
    # ----------------------------------------

    li t3, 256
    bltu a4, t3, .Lsqrt_check_exp

    srli a4, a4, 1
    addi t1, t1, 1

    # ----------------------------------------
    # Step 10: Check exponent range
    # ----------------------------------------

.Lsqrt_check_exp:
    li  t3, 255
    bge t1, t3, .Lsqrt_inf

    # Exponent <= 0 -> +0
    bge zero, t1, .Lsqrt_zero

    # ----------------------------------------
    # Step 11: Pack the final BF16 result
    # ----------------------------------------

    slli t1, t1, 7
    andi a4, a4, 127

    or a0, t1, a4
    ret

    # ----------------------------------------
    # Step 12: Special return paths
    # ----------------------------------------

.Lsqrt_zero:
    li a0, 0
    ret

.Lsqrt_nan:
    li a0, 0x7fc0
    ret

.Lsqrt_inf:
    li a0, 0x7f80
    ret

.Lsqrt_return:
    ret

    .size bf16_sqrt_asm, .-bf16_sqrt_asm