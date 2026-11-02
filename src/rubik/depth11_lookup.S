
# Depth-11 Lookup: RV32I Binary Search
#
# a0 = permutation rank
# a1 = orientation rank
# a2 = path buffer
#
# Return:
#   11 = found, path filled
#   -1 = not found
#
# Table entry:
#   4 bytes key
#   11 bytes moves
#   1 byte padding
#   Total: 16 bytes

    .text
    .balign 4

    .globl rubik_depth11_lookup
    .type rubik_depth11_lookup, @function

rubik_depth11_lookup:

    # Build unique key: (p << 10) | o
    slli t0, a0, 10
    or   t0, t0, a1

    # Table base address
    la   t1, rubik_depth11_table

    li   t2, 0
    li   t3, 2644

.Llookup_search:

    # while (left < right)
    bgeu t2, t3, .Llookup_miss

    # mid = (left + right) / 2
    add  t4, t2, t3
    srli t4, t4, 1

    # Address = table + mid * 16
    slli t5, t4, 4
    add  t5, t1, t5

    # Compare state key
    lw   t6, 0(t5)

    bltu t0, t6, .Llookup_left
    bltu t6, t0, .Llookup_right

    # Match found, copy 11 moves
    addi t5, t5, 4

    li   t4, 11

.Llookup_copy:

    lbu  t6, 0(t5)
    sb   t6, 0(a2)

    addi t5, t5, 1
    addi a2, a2, 1
    addi t4, t4, -1

    bnez t4, .Llookup_copy

    li   a0, 11
    ret

.Llookup_left:

    mv t3, t4
    j  .Llookup_search

.Llookup_right:

    addi t2, t4, 1
    j    .Llookup_search

.Llookup_miss:

    li a0, -1
    ret

    .size rubik_depth11_lookup, .-rubik_depth11_lookup
