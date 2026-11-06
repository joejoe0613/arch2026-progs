# op1, op2, op3 and q_mul: hand-written RV32I.
#
# uint32_t op1_asm(uint32_t a, uint32_t b, int *n)   a0, a1, a2 -> a0
# uint32_t op2_asm(uint32_t a, uint32_t b)           a0, a1 -> a0
# uint32_t op3_asm(uint32_t a, uint32_t b)           a0, a1 -> a0
# int32_t  q_mul_asm(int32_t a, int32_t b)           a0, a1 -> a0
#
# RV32I and Zicsr only: no mul, div, rem, no floating point, no compressed
# instructions. q_mul forms a 64-bit product in a register pair. Tests:
# tests/tfixed.c.

    .text

    .globl op1_asm
    .type  op1_asm, @function
    .align 2

op1_asm:
    # Input:
    #   a0 = unsigned integer a
    #   a1 = unsigned integer b
    #   a2 = pointer to pass count (*n)
    #
    # Output:
    #   a0 = (a + b) modulo 2^32
    #   *n = number of carry propagation passes

    # Initialize pass counter
    li t0, 0

    # If b is zero, skip the loop
    beqz a1, .Lop1_done

.Lop1_loop:
    # Calculate carry before modifying a0
    and t1, a0, a1

    # Calculate sum without carry
    xor a0, a0, a1

    # Shift carry directly into a1
    slli a1, t1, 1

    # Increment pass counter
    addi t0, t0, 1

    # Repeat while carry is nonzero
    bnez a1, .Lop1_loop

.Lop1_done:
    # Store pass count
    sw t0, 0(a2)

    ret

    .size op1_asm, .-op1_asm

    .globl  op2_asm
    .type   op2_asm, @function
    .align  2
op2_asm:
    # Input:
    #   a0 = unsigned integer a
    #   a1 = unsigned integer b
    #
    # Output:
    #   a0 = (a - b) modulo 2^32

    sub a0, a0, a1

    ret

    .globl  op3_asm
    .type   op3_asm, @function
    .align  2
op3_asm:
    # Input:
    #   a0 = unsigned integer a
    #   a1 = unsigned integer b
    #
    # Output:
    #   a0 = floor((a + b) / 2)
    #   without intermediate overflow

    # Step 1: Compute common bits
    and t0, a0, a1

    # Step 2: Compute differing bits
    xor t1, a0, a1

    # Step 3: Divide differing bits by two
    srli t1, t1, 1

    # Step 4: Combine the two parts
    add a0, t0, t1

    ret

    .globl  q_mul_asm
    .type   q_mul_asm, @function
    .align  2
q_mul_asm:
    # Input:
    #   a0 = signed Q11.20 operand a
    #   a1 = signed Q11.20 operand b
    #
    # Output:
    #   a0 = rounded Q11.20 product
    #
    # Product = signed 64-bit a * b
    # Result  = (Product + 2^19) >> 20
    # Keep only the low 32 bits.

    # ----------------------------------------
    # Step 1: Determine product sign
    # ----------------------------------------

    xor  t0, a0, a1
    srai t0, t0, 31

    # t0 = 0  : positive product
    # t0 = -1 : negative product

    # ----------------------------------------
    # Step 2: Convert to unsigned magnitudes
    # ----------------------------------------

    bge a0, zero, .Lqmul_abs_b
    sub a0, zero, a0

.Lqmul_abs_b:
    bge a1, zero, .Lqmul_init
    sub a1, zero, a1

    # ----------------------------------------
    # Step 3: Initialize 64-bit multiplication
    # ----------------------------------------

.Lqmul_init:
    # Multiplicand = t2:t1
    mv t1, a0
    li t2, 0

    # Product = t4:t3
    li t3, 0
    li t4, 0

    # Multiplier
    mv t5, a1

    # Handle zero multiplier before entering loop
    beqz t5, .Lqmul_restore_sign

.Lqmul_loop:
    # Check current multiplier bit
    andi t6, t5, 1
    beqz t6, .Lqmul_shift

    # Update low product word directly
    add t3, t3, t1

    # Carry occurs if sum < multiplicand
    sltu t6, t3, t1

    # Update high product word
    add t4, t4, t2
    add t4, t4, t6

.Lqmul_shift:
    # Shift multiplier right
    srli t5, t5, 1

    # Shift 64-bit multiplicand left
    srli t6, t1, 31
    slli t1, t1, 1
    slli t2, t2, 1
    or t2, t2, t6

    # Loop only while multiplier is nonzero
    bnez t5, .Lqmul_loop

    # Fall through to .Lqmul_restore_sign

    # ----------------------------------------
    # Step 5: Restore signed 64-bit product
    # ----------------------------------------

.Lqmul_restore_sign:
    beqz t0, .Lqmul_round

    # Negate 64-bit product in two's complement
    xori t3, t3, -1
    xori t4, t4, -1

    addi t3, t3, 1

    # Propagate carry if low word becomes zero
    sltiu t6, t3, 1
    add t4, t4, t6

    # ----------------------------------------
    # Step 6: Add rounding bias (2^19)
    # ----------------------------------------

.Lqmul_round:
    li t6, 0x80000

    add t3, t3, t6
    sltu t6, t3, t6
    add t4, t4, t6

    srli t3, t3, 20
    slli t4, t4, 12
    or a0, t4, t3

    ret

    # ----------------------------------------
    # Step 7: Arithmetic shift right by 20
    # Keep the low 32 bits
    # ----------------------------------------

    # Bits 20..31 from the low word
    srli t3, t3, 20

    # Bits 32..51 from the high word
    slli t4, t4, 12

    # Combine both portions
    or a0, t4, t3

    ret

    .size q_mul_asm, .-q_mul_asm
