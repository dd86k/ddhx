/// Mathematic utilities.
/// Copyright: dd86k <dd@dax.moe>
/// License: MIT
/// Authors: $(LINK2 https://github.com/dd86k, dd86k)
module ddhx.utils.math;

T min(T)(T a, T b) pure @safe
{
    return a < b ? a : b;
}
@safe unittest
{
    assert(min(1, 2) == 1);
    assert(min(2, 2) == 2);
    assert(min(3, 2) == 2);
}

T max(T)(T a, T b) pure @safe
{
    return a > b ? a : b;
}
@safe unittest
{
    assert(max(1, 2) == 2);
    assert(max(2, 2) == 2);
    assert(max(3, 2) == 3);
}