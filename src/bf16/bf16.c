#include "bf16.h"

/* Dummies: every function returns 0. Replace with the real routines. */
uint16_t bf16_from_f32(uint32_t f32bits)
{
    uint32_t exp = (f32bits >> 23) & 0xFF;

    /* Preserve infinity and NaN patterns. */
    if (exp == 0xFF)
        return (uint16_t) (f32bits >> 16);

    /* Round to nearest, ties to even. */
    uint32_t bias = 0x7FFF + ((f32bits >> 16) & 1);

    f32bits += bias;

    return (uint16_t) (f32bits >> 16);
}

uint16_t bf16_mul(uint16_t a, uint16_t b)
{
    /* Step 1: Extract sign, exponent, and fraction. */
    uint16_t sign = (a ^ b) & 0x8000u;

    uint32_t exp_a = (a >> 7) & 0xFFu;
    uint32_t exp_b = (b >> 7) & 0xFFu;

    uint32_t frac_a = a & 0x7Fu;
    uint32_t frac_b = b & 0x7Fu;

    /* Step 2: Handle special values in operand order. */

    /* Examine operand a first. */
    if (exp_a == 0xFFu) {
        if (frac_a != 0)
            return a;

        /* Infinity multiplied by zero is NaN. */
        if ((b & 0x7FFFu) == 0)
            return 0x7FC0u;

        return sign | 0x7F80u;
    }

    /* Examine operand b second. */
    if (exp_b == 0xFFu) {
        if (frac_b != 0)
            return b;

        if ((a & 0x7FFFu) == 0)
            return 0x7FC0u;

        return sign | 0x7F80u;
    }

    /* Zero multiplied by a finite value. */
    if ((a & 0x7FFFu) == 0 || (b & 0x7FFFu) == 0)
        return sign;

    /* Step 3: Restore the significands. */
    uint32_t mant_a = frac_a;
    uint32_t mant_b = frac_b;

    int32_t e_a = (int32_t) exp_a;
    int32_t e_b = (int32_t) exp_b;

    /* Normalize denormal operand a. */
    if (e_a == 0) {
        e_a = 1;

        while ((mant_a & 0x80u) == 0) {
            mant_a <<= 1;
            --e_a;
        }
    } else {
        mant_a |= 0x80u;
    }

    /* Normalize denormal operand b. */
    if (e_b == 0) {
        e_b = 1;

        while ((mant_b & 0x80u) == 0) {
            mant_b <<= 1;
            --e_b;
        }
    } else {
        mant_b |= 0x80u;
    }

    /* Step 4: Multiply the significands. */
    uint32_t product = mant_a * mant_b;

    /* Add exponents and subtract the bias. */
    int32_t result_exp = e_a + e_b - 127;

    /* Step 5: Normalize the product. */
    uint32_t result_mant;

    if (product & 0x8000u) {
        result_mant = product >> 8;
        ++result_exp;
    } else {
        result_mant = product >> 7;
    }

    /* Step 6: Handle exponent overflow. */
    if (result_exp >= 0xFF)
        return sign | 0x7F80u;

    /* Step 7: Handle exponent underflow. */
    if (result_exp <= 0) {
        if (result_exp < -6)
            return sign;

        /* Extract the 7-bit fraction first. */
        uint32_t fraction = result_mant & 0x7Fu;

        /* Shift the fraction for a denormal result. */
        fraction >>= (1 - result_exp);

        return sign | (uint16_t) fraction;
    }

    /* Step 8: Pack sign, exponent, and fraction. */
    return sign | (uint16_t) ((uint32_t) result_exp << 7) |
           (uint16_t) (result_mant & 0x7Fu);
}

uint16_t bf16_sqrt(uint16_t a)
{
    /* Step 1: Extract sign, exponent, and fraction. */
    uint32_t sign = a & 0x8000u;
    uint32_t exp = (a >> 7) & 0xFFu;
    uint32_t frac = a & 0x7Fu;

    /* Step 2: Handle NaN and infinity. */
    if (exp == 0xFFu) {
        /* Preserve the original NaN bit pattern. */
        if (frac != 0)
            return a;

        /* Negative infinity produces a quiet NaN. */
        if (sign != 0)
            return 0x7FC0u;

        /* Positive infinity remains unchanged. */
        return a;
    }

    /* Step 3: Handle positive and negative zero. */
    if ((a & 0x7FFFu) == 0)
        return 0x0000u;

    /* Square root of a negative nonzero value. */
    if (sign != 0)
        return 0x7FC0u;

    /* Denormal inputs are flushed to positive zero. */
    if (exp == 0)
        return 0x0000u;

    /* Step 4: Restore the hidden leading bit. */
    uint32_t m = frac | 0x80u;

    /* Convert biased exponent to actual exponent. */
    int32_t e = (int32_t) exp - 127;
    int32_t new_exp;

    /* Step 5: Make the exponent even. */
    if (e & 1) {
        m <<= 1;
        new_exp = ((e - 1) / 2) + 127;
    } else {
        new_exp = (e / 2) + 127;
    }

    /* Step 6: Integer square root using binary search. */
    uint32_t low = 90;
    uint32_t high = 256;
    uint32_t result = 128;

    while (low <= high) {
        uint32_t mid = (low + high) >> 1;

        /* Division by 128 is equivalent to >> 7. */
        uint32_t sq = (mid * mid) >> 7;

        if (sq <= m) {
            result = mid;
            low = mid + 1;
        } else {
            high = mid - 1;
        }
    }

    /* Step 7: Normalize the result if necessary. */
    if (result >= 256) {
        result >>= 1;
        ++new_exp;
    }

    /* Step 8: Handle exponent overflow and underflow. */
    if (new_exp >= 0xFF)
        return 0x7F80u;

    if (new_exp <= 0)
        return 0x0000u;

    /* Step 9: Pack exponent and fraction. */
    return (uint16_t) (((uint32_t) new_exp << 7) | (result & 0x7Fu));
}
