#include "gcd.h"

/* Dummy: returns 0 for every input. Replace with the binary GCD. */
uint32_t gcd_u32(uint32_t a, uint32_t b)
{
    /* Step 1: Handle zero operands. */
    if (a == 0)
        return b;

    if (b == 0)
        return a;

    /* Step 2: Remove common factors of two. */
    uint32_t shift = 0;

    while (((a | b) & 1u) == 0) {
        a >>= 1;
        b >>= 1;
        ++shift;
    }

    /* Step 3: Make operand a odd. */
    while ((a & 1u) == 0)
        a >>= 1;

    /* Step 4: Binary GCD reduction. */
    do {
        /* Make operand b odd. */
        while ((b & 1u) == 0)
            b >>= 1;

        /* Ensure a <= b. */
        if (a > b) {
            uint32_t temp = a;
            a = b;
            b = temp;
        }

        /* Subtract the smaller odd operand. */
        b -= a;

    } while (b != 0);

    /* Step 5: Restore common factors of two. */
    return a << shift;
}
