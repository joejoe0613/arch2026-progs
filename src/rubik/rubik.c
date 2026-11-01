
#include "rubik.h"
#include "solver_core.h"

int rubik_solve(const char *state, char *out, size_t cap)
{
    uint8_t path[11];

    /* Run the existing C IDA* solver. */
    int n = minirubik_solve(state, path);

    /* Invalid input must leave out untouched. */
    if (n < 0)
        return n;

    /* Calculate space for text, spaces and NUL. */
    size_t required = 1;

    for (int i = 0; i < n; ++i) {
        const char *move = minirubik_move_name(path[i]);

        if (i != 0)
            ++required;

        while (*move++)
            ++required;
    }

    /* Reject insufficient output capacity. */
    if (required > cap) {
        if (cap > 0)
            out[0] = '\0';

        return -2;
    }

    /* Convert the move sequence into text. */
    size_t pos = 0;

    for (int i = 0; i < n; ++i) {
        const char *move = minirubik_move_name(path[i]);

        if (i != 0)
            out[pos++] = ' ';

        while (*move)
            out[pos++] = *move++;
    }

    out[pos] = '\0';

    return n;
}
