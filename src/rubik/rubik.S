
# rubik_solve_asm: RV32I Mini-Rubik solver entry point
#
# int rubik_solve_asm(const char *state, char *out, size_t cap)
#
# a0 = state
# a1 = output buffer
# a2 = output capacity
#
# Returns:
#    0..11 : shortest solution length
#    -1    : invalid state (output unchanged)
#    -2    : insufficient output capacity
#
# Internal handwritten Assembly functions:
#    minirubik_asm_parse_po
#    minirubik_asm_solve_po

    .section .rodata,"a",@progbits

# Move indices: 0..8
# R R2 R' B B2 B' D D2 D'

.Lrubik_faces:
    .ascii "RRRBBBDDD"

.Lrubik_suffixes:
    .byte 0, '2', 39, 0, '2', 39, 0, '2', 39

    .text
    .balign 4

    .globl rubik_solve_asm
    .type rubik_solve_asm, @function

rubik_solve_asm:

    # ----------------------------------------
    # Prologue: reserve 64 bytes
    #
    # [0..10]  Move path
    # [36..60] Saved registers
    #
    # Stack remains 16-byte aligned.
    # ----------------------------------------

    addi sp, sp, -64

    sw ra, 60(sp)
    sw s0, 56(sp)
    sw s1, 52(sp)
    sw s2, 48(sp)
    sw s3, 44(sp)
    sw s4, 40(sp)
    sw s5, 36(sp)

    mv s0, a0       # state
    mv s1, a1       # output
    mv s2, a2       # capacity

    mv s4, sp       # temporary path[11]

    beqz s0, .Lrubik_invalid

    # ----------------------------------------
    # Part 1: Validate Cubie Permutation
    # ----------------------------------------

    li t0, 0        # i = 0
    li t1, 0        # Used-cubie bitmask

.Lrubik_perm_loop:

    add t2, s0, t0
    lbu t3, 0(t2)

    # ASCII '1'..'7' -> 0..6

    addi t3, t3, -49

    sltiu t4, t3, 7
    beqz t4, .Lrubik_invalid

    # bit = 1 << cubie

    li t4, 1
    sll t4, t4, t3

    # Reject duplicate cubies

    and t5, t1, t4
    bnez t5, .Lrubik_invalid

    or t1, t1, t4

    addi t0, t0, 1

    li t6, 7
    bltu t0, t6, .Lrubik_perm_loop

    # ----------------------------------------
    # Part 2: Validate Orientation
    # ----------------------------------------

    li t5, 0        # Orientation sum

.Lrubik_orient_loop:

    # t0 starts at 7

    add t2, s0, t0
    lbu t3, 0(t2)

    # ASCII '1'..'3' -> 0..2

    addi t3, t3, -49

    sltiu t4, t3, 3
    beqz t4, .Lrubik_invalid

    add t5, t5, t3

    addi t0, t0, 1

    li t6, 14
    bltu t0, t6, .Lrubik_orient_loop

    # Exactly 14 characters required

    lbu t3, 14(s0)
    bnez t3, .Lrubik_invalid

    # Orientation sum must be divisible by 3

.Lrubik_mod3:

    sltiu t4, t5, 3
    bnez t4, .Lrubik_orient_ok

    addi t5, t5, -3
    j .Lrubik_mod3

.Lrubik_orient_ok:

    bnez t5, .Lrubik_invalid

    # ----------------------------------------
    # Part 3: Parse state into P/O ranks
    # ----------------------------------------

    # Parse cube state
    mv a0, s0
    call minirubik_asm_parse_po

    # Save permutation/orientation ranks
    sw a0, 12(sp)
    sw a1, 16(sp)

    # Returned:
    # a0 = permutation rank
    # a1 = orientation rank


    # ----------------------------------------
    # Part 4: Depth-11 Lookup + IDA* Fallback
    # ----------------------------------------

    # Try Depth-11 Lookup first
    # a0 = permutation rank
    # a1 = orientation rank
    # a2 = path buffer

    mv a2, s4
    call rubik_depth11_lookup

    # Hit: a0 = 11
    # Miss: a0 = -1

    bge a0, zero, .Lrubik_have_length

    # ----------------------------------------
    # Lookup miss: restore P/O ranks
    # ----------------------------------------

    lw a0, 12(sp)
    lw a1, 16(sp)

    mv a2, s4
    call minirubik_asm_solve_po

.Lrubik_have_length:

    # Both paths return here
    # a0 = solution length
    # s4 = move path

    blt a0, zero, .Lrubik_invalid

    li t0, 11
    bltu t0, a0, .Lrubik_invalid

    mv s3, a0


    # ----------------------------------------
    # Part 5: Calculate required output size
    # ----------------------------------------

    # Include one byte for terminating NUL

    li s5, 1

    li t0, 0

    la a3, .Lrubik_suffixes

.Lrubik_size_loop:

    bgeu t0, s3, .Lrubik_size_done

    # One character for face letter

    addi s5, s5, 1

    # Add a separator before nonfirst moves

    beqz t0, .Lrubik_no_space

    addi s5, s5, 1

.Lrubik_no_space:

    # Read move index

    add t1, s4, t0
    lbu t2, 0(t1)

    li t4, 9
    bgeu t2, t4, .Lrubik_invalid

    # Add one extra character for '2' or apostrophe

    add t3, a3, t2
    lbu t3, 0(t3)

    beqz t3, .Lrubik_no_suffix

    addi s5, s5, 1

.Lrubik_no_suffix:

    addi t0, t0, 1
    j .Lrubik_size_loop

.Lrubik_size_done:

    # If cap < required, reject

    bltu s2, s5, .Lrubik_no_capacity

    # ----------------------------------------
    # Part 6: Format Move Sequence
    # ----------------------------------------

    mv t0, s1       # Output pointer
    li t1, 0        # Move index

    la a3, .Lrubik_faces
    la a4, .Lrubik_suffixes

.Lrubik_emit_loop:

    bgeu t1, s3, .Lrubik_emit_done

    # Write a space before nonfirst moves

    beqz t1, .Lrubik_emit_face

    li t2, 32
    sb t2, 0(t0)

    addi t0, t0, 1

.Lrubik_emit_face:

    # Get move number 0..8

    add t2, s4, t1
    lbu t2, 0(t2)

    # Write face letter: R, B or D

    add t3, a3, t2
    lbu t4, 0(t3)

    sb t4, 0(t0)
    addi t0, t0, 1

    # Write optional '2' or apostrophe

    add t3, a4, t2
    lbu t4, 0(t3)

    beqz t4, .Lrubik_emit_next

    sb t4, 0(t0)
    addi t0, t0, 1

.Lrubik_emit_next:

    addi t1, t1, 1
    j .Lrubik_emit_loop

.Lrubik_emit_done:

    # Terminate output string

    sb zero, 0(t0)

    # Return shortest solution length

    mv a0, s3
    j .Lrubik_return

    # ----------------------------------------
    # Part 7: Handle insufficient capacity
    # ----------------------------------------

.Lrubik_no_capacity:

    # Only modify out[0] when cap > 0

    beqz s2, .Lrubik_too_small

    sb zero, 0(s1)

.Lrubik_too_small:

    li a0, -2
    j .Lrubik_return

    # ----------------------------------------
    # Part 8: Handle invalid state
    # ----------------------------------------

.Lrubik_invalid:

    # Must leave output buffer untouched

    li a0, -1

    # ----------------------------------------
    # Epilogue: restore registers
    # ----------------------------------------

.Lrubik_return:

    lw s5, 36(sp)
    lw s4, 40(sp)
    lw s3, 44(sp)
    lw s2, 48(sp)
    lw s1, 52(sp)
    lw s0, 56(sp)
    lw ra, 60(sp)

    addi sp, sp, 64

    ret

    .size rubik_solve_asm, .-rubik_solve_asm
