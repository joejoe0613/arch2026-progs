# gcd_u32_asm: binary GCD, hand-written RV32I.
#
# uint32_t gcd_u32_asm(uint32_t a, uint32_t b)   a in a0, b in a1, result in a0
#
# RV32I and Zicsr only: no mul, div, rem, no floating point, no compressed
# instructions. Tests: tests/tgcd.c.

.text

    .globl gcd_u32_asm
    .type  gcd_u32_asm, @function
    .align 2

gcd_u32_asm:
    # Input:
    #   a0 = unsigned integer a
    #   a1 = unsigned integer b
    #
    # Output:
    #   a0 = gcd(a, b)

    # ----------------------------------------
    # Step 1: Handle zero operands
    # ----------------------------------------

    beq a0, zero, .Lgcd_return_b
    beq a1, zero, .Lgcd_return

    # ----------------------------------------
    # Step 2: Remove common factors of two
    # ----------------------------------------

    # t0 = number of common factors of two
    addi t0, zero, 0

.Lgcd_both_even:
    or   t1, a0, a1
    andi t1, t1, 1

    # Stop when at least one operand is odd
    bne t1, zero, .Lgcd_make_a_odd

    srli a0, a0, 1
    srli a1, a1, 1

    addi t0, t0, 1
    jal zero, .Lgcd_both_even

    # ----------------------------------------
    # Step 3: Make operand a odd
    # ----------------------------------------

.Lgcd_make_a_odd:
    andi t1, a0, 1
    bnez t1, .Lgcd_make_b_odd

.Lgcd_a_shift:
    srli a0, a0, 1
    andi t1, a0, 1
    beqz t1, .Lgcd_a_shift

    # ----------------------------------------
    # Step 4: Make operand b odd
    # ----------------------------------------

.Lgcd_make_b_odd:
    andi t1, a1, 1
    bnez t1, .Lgcd_compare

.Lgcd_b_shift:
    srli a1, a1, 1
    andi t1, a1, 1
    beqz t1, .Lgcd_b_shift

    # ----------------------------------------
    # Step 5: Compare and swap
    # ----------------------------------------

.Lgcd_compare:
    # If b < a, handle the smaller operand
    bltu a1, a0, .Lgcd_less

    # b >= a: subtract directly
    sub a1, a1, a0
    bnez a1, .Lgcd_make_b_odd

    # Restore common factors of two
    sll a0, a0, t0

.Lgcd_return:
    ret

.Lgcd_less:
    # a > b: compute the difference first
    sub t2, a0, a1

    # Update operands without a full swap
    mv a0, a1
    mv a1, t2

    # The difference is guaranteed nonzero
    j .Lgcd_make_b_odd

.Lgcd_return_b:
    mv a0, a1
    ret

    .size gcd_u32_asm, .-gcd_u32_asm
