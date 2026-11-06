#include "fixed.h"

/*

op1: Addition using bitwise operations.
The result wraps modulo 2^32.
Store the number of carry propagation passes in *n.*/
uint32_t op1(uint32_t a, uint32_t b, int *n)
{
    int count = 0;

    while (b != 0) {
        uint32_t carry = (a & b) << 1;

        a = a ^ b;
        b = carry;

        ++count;
    }

    *n = count;
    return a;
}

/*
 * op2: Subtraction modulo 2^32.
 */
uint32_t op2(uint32_t a, uint32_t b)
{
    return a - b;
}

/*
 * op3: Floor of the exact average without overflow.
 */
uint32_t op3(uint32_t a, uint32_t b)
{
    return (a & b) + ((a ^ b) >> 1);
}

/*
 * q_mul: Signed Q11.20 fixed-point multiplication.
 *
 * Form the 64-bit product without hardware multiplication.
 * Add half a fixed-point unit for rounding.
 * Keep the low 32 bits of the shifted result.
 */
int32_t q_mul(int32_t a, int32_t b)
{
    /* Step 1: Determine the sign of the product. */
    uint32_t negative = (a < 0) != (b < 0);

    /* Step 2: Convert operands to unsigned magnitudes. */
    uint32_t ua = (uint32_t) a;
    uint32_t ub = (uint32_t) b;

    if (a < 0)
        ua = 0u - ua;

    if (b < 0)
        ub = 0u - ub;

    /* Step 3: Initialize 64-bit multiplication. */
    uint32_t multiplicand_lo = ua;
    uint32_t multiplicand_hi = 0;

    uint32_t product_lo = 0;
    uint32_t product_hi = 0;

    /* Step 4: Shift-and-add multiplication. */
    while (ub != 0) {
        if (ub & 1u) {
            uint32_t old_lo = product_lo;

            product_lo += multiplicand_lo;

            /* Propagate carry to the high word. */
            uint32_t carry = product_lo < old_lo;

            product_hi += multiplicand_hi + carry;
        }

        /* Shift the multiplier right. */
        ub >>= 1;

        /* Shift the 64-bit multiplicand left. */
        uint32_t carry_bit = multiplicand_lo >> 31;

        multiplicand_lo <<= 1;
        multiplicand_hi = (multiplicand_hi << 1) | carry_bit;
    }

    /* Step 5: Restore the signed 64-bit product. */
    if (negative) {
        product_lo = ~product_lo + 1u;

        /* Carry from the low word during negation. */
        product_hi = ~product_hi + (product_lo == 0);
    }

    /* Step 6: Add rounding bias 2^19. */
    uint32_t old_lo = product_lo;

    product_lo += 1u << (Q - 1);

    if (product_lo < old_lo)
        ++product_hi;

    /* Step 7: Shift right by 20 and retain low 32 bits. */
    uint32_t result = (product_hi << (32 - Q)) | (product_lo >> Q);

    return (int32_t) result;
}
