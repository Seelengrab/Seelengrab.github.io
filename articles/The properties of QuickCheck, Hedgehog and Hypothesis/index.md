@def title = "The Properties of QuickCheck, Hedgehog and Hypothesis"
@def tags = ["PBT", "QuickCheck", "Hedgehog", "Hypothesis", "testing"]

# The Properties of QuickCheck, Hedgehog and Hypothesis

If you're writing software, chances are that you're also writing tests for that software in some form
or another (if you're not, you really should be). As far as testing frameworks go, there are
quite a lot to choose from. They are often language specific, with various setup, teardown and
assertion steps, but most boil down to "run my code with some specific input and see that it works".

This is at face value a good approach, but limiting your testing to some small known cases can severely
limit your ability to detect failures on unexpected input. This is where an approach called "fuzz testing"
comes in; in a nutshell, "fuzz testing" is about exercising your code with random input and checking whether
the code still works as expected. There is a downside to this, however: due to the random nature, failure
cases can be extremely difficult to trace & debug, since the generated inputs are often not well-structured.
This is where a technique called "Property Based Testing" (in the following abbreviated as "PBT") comes in:
By generating input conforming to a given set of properties, the random input can be "tamed" a bit, by ensuring
for a given test case only e.g. random even numbers are generated. While this ensures that input is more
well-behaved, in the sense that it's less likely to encounter failures due to known-bad input, the generated
test examples can still be very complicated to human eyes.

This problem of "too complicated test examples" was first tackled by QuickCheck in the 90s (TODO: factcheck & accurate date),
with more recent work in the form of Hedgehog and Hypothesis refining the concept through different approaches.
In this article, I'll try to build some intuition for how each of these testing frameworks work conceptually and what their
tradeoffs are.

## QuickCheck

QuickCheck is the "grandfather" of property based testing frameworks. Originally developed for the Haskell programming language,
it was (to my knowledge) the first property based testing framework with shrinking of examples in widespread use, at least in the Haskell
ecosystem.
At its core, QuickCheck works with types, both for generating values as well as shrinking them. To understand how this is done,
we'll first have to take a (very small) excursion into type theory, to learn what a "type" even is (don't worry, this won't go
very deep), at least for the purposes of this article. 

Generally speaking, a type is a (potentially infinitely large) collection of values. For example, the `Int32` type in Julia
(corresponding to `int32_t` in C) is a type representing all possible 32-bit integers from the interval `[-(2^31), 2^31 - 1]`, encoded
in Two's complement binary. Since the source set is finite, so is the type.
As another example, the `String` type in Julia represents all possible UTF-8 strings, i.e. sequences of Unicode codepoints.
Because there is only a minimum length but not a (theoretical) maximum, `String` is an example of a type that can potentially grow
infinitely large.

For `Int32`, generating an example is relatively trivial; just pick a random number from all valid instances. For `String`, you
might start out with the empty string `""`, flip a coin to decide whether you should generate more characters or stop generation and return.
If you generate more, you simply concatenate it onto the end of the result and flip a coin again.

Now that we have some random input generated from a type, we need a predicate function (a function returning only `true` and `false`) to
test - `true` corresponds to "the tested property holds for the given input" and `false` to "the tested property doesn't hold for the given
input". Our goal now is to find some input to that predicate such that it returns `false`. In effect, we're expecting the predicate to
hold on the generated input and we're looking for examples where it _doesn't_ hold, falsifying our assumptions about how the code behaves.

## Hedgehog

## Hypothesis
