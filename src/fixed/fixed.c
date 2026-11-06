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
    /* Step 1: Convert operands to unsigned magnitudes. */
    uint32_t ua = (uint32_t) a;
    uint32_t ub = (uint32_t) b;

    if (a < 0)
        ua = 0u - ua;

    if (b < 0)
        ub = 0u - ub;

    /* Step 2: Compute the full 64-bit unsigned product. */
    uint64_t product = 0;
    uint64_t multiplicand = (uint64_t) ua;

    while (ub != 0) {
        if ((ub & 1u) != 0)
            product += multiplicand;

        multiplicand <<= 1;
        ub >>= 1;
    }

    /* Step 3: Restore the sign in 64-bit two's complement. */
    if ((a < 0) != (b < 0))
        product = (uint64_t) 0 - product;

    /* Step 4: Add half a fixed-point unit. */
    product += (uint64_t) 1 << (Q - 1);

    /* Step 5: Shift and retain the low 32 result bits. */
    uint32_t result = (uint32_t) (product >> Q);

    return (int32_t) result;
}
