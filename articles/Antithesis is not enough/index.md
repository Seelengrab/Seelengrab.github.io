@def title = "Antithesis is not enough"
@def tags = ["PBT", "Determinism", "Antithesis", "Supposition.jl", "testing", "julia"]
@def rss_description = "A look at determinism and why it's required, but not sufficient for good testing"

# Antithesis is not enough

Over the past few weeks, [Antithesis](https://antithesis.com) has been all the rage in the tech world,
especially on HackerNews. The proposition (though not the execution) is simple:
A deterministic hypervisor to aid in debugging of so-called Heisenbugs, i.e.
bugs that happen due to nondeterministic effects of OS scheduling, I/O times
etc. In this article, we're going to take a short look at what this enables
in terms of debugging, and why the properties of such a deterministic hypervisor 
alone are not enough.

That being said, I haven't used Antithesis, so this article may be inaccurate
in some places. Most of what I could gather about how it works is from their
[blog posts](https://antithesis.com/blog/) and marketing material (which is hopefully accurate)
and comparing that to my experience from writing [Supposition.jl](https://github.com/Seelengrab/Supposition.jl),
a property based testing framework for Julia.

## Determinism in Testing

Before we get to concrete difficulties, let's first take a small detour about
determinism in testing, with examples using Supposition.jl. The example I'm using
in this section is based on the talk [Property-testing async code in Rust to build reliable distributed systems](https://www.youtube.com/watch?v=ms8zKpS_dZE) by Antonio Scandurra.
If you're already familiar with Antithesis and/or deterministic property based testing, you can probably skip this bit.
If you're interested in the full example code I'm using here, see [this gist](https://gist.github.com/Seelengrab/f0eddb28f139644ec71a9a1e8c4b42cd).

So, why is determinism for testing a big deal? Simply put, without determinism you
have to be lucky while debugging rare failures. EXTREMELY lucky. Not only does
someone/some CI job have to hit your specific bug, but without determinism you'll
often have a hard time reproducing the failure, slowing down a potential fix
immensely. Let's look at an example:

```julia
function run_test(exe::Executor)
    t = @spawn exe begin
        @debug "Starting test"
        l = ReentrantLock()
        data = Ref(0)

        future1 = @spawn exe begin
            @debug "Future 1 scheduled"
            @lock l begin
                if data[] == 0
                    data[] += 1
                end
            end
            @debug "Done with 1!"
        end

        future2 = @spawn exe begin
            @debug "Future 2 scheduled"
            @lock l begin
                if data[] == 1
                    data[] += 1
                end
            end
            @debug "Done with 2!"
        end

        wait(future1)
        wait(future2)
        @debug "Done with subtasks!"
        @lock l begin
            data[]
        end
    end
    res = @something block_on(exe, t) Some(nothing)
    res == 2
end
```

This is a very small function making use of the asynchronous runtime used in Julia,
with some small abstractions sprinkled on top to allow for custom Rust-like executors to
be passed in. The task is to spawn two futures and
increment a shared mutable object that's being protected by a lock if some condition
is fulfilled. The first future only increments if the data is zero, while the second
only increments if the data is one. Finally, we check that the ultimate result is 
`2`, i.e. we expect `future1` to execute first, followed by `future2`.

This code has a race condition - if `future2` executes before `future1` does, we only
end up with `data` holding `1` (incremented by `future1`). There's two ways to schedule
the two futures, so we'd expect the test to fail 50% of the time. However, that's
not what happens - if we pass in a `BaseExecutor` (a Rust-like executor that just falls back
on the default Julia runtime), we get very consistent results:

```julia-repl
julia> count( run_test(BaseExecutor()) for _ in 1:1_000 )
994
```

Out of 1000 executions, 994 returned `true` - i.e., almost all executions just happened
to schedule the two futures in the "happy" order, avoiding the race condition. `future1` executed first, incrementing
the shared state to `1`, followed by `future2`, incrementing the shared state to `2`.
Only a tiny fraction of executions managed to hit the race condition! What's worse is
that running the test locally is also just as unlikely to produce that failure:

```julia
julia> run_test(BaseExecutor())
true

julia> run_test(BaseExecutor())
true

julia> run_test(BaseExecutor())
true

julia> run_test(BaseExecutor())
true

julia> run_test(BaseExecutor())
true
```

Of course, this is a tiny and artificial example, but these kinds of rare failures
are exactly the kinds of heisenbugs that are difficult to debug when they do occur.
Note how there is no I/O or even randomness involved - the only variable is the
order futures are scheduled in.

We can do slightly better if we use a deterministic scheduler:

```julia-repl
julia> count( run_test(ConcurrentExecutor(i)) for i in 1:1_000 )
465
```

In contrast to `BaseExecutor` (which just spawns the future eagerly and blocks as usual),
`ConcurrentExecutor` takes a seed value and *randomly* schedules tasks based on
that, instead of a naive FIFO. This is already much better; we get a roughly 50%
failure rate, which is exactly what we expected to get in the first place!
Moreover, because the scheduling decisions are purely based on the seed, any
individual failure is tied to precisely that seed, so we can always perfectly reproduce
any given failure:

```julia
# find any failure
julia> findfirst( !run_test(ConcurrentExecutor(i)) for i in 1:1_000 )
2

julia> run_test(ConcurrentExecutor(2))
false

julia> run_test(ConcurrentExecutor(2))
false

julia> run_test(ConcurrentExecutor(2))
false
```

!!! note "Eager async"
    Unlike `async` in Rust, async code in Julia (through the most commonly used APIs)
    is executed eagerly, and there's no callback possible to hook into for when a future
    yields to the runtime (which is necessary for controlling re-scheduling). As such,
    more complicated examples involving I/O or actual reliance on parallel execution of
    spawned tasks quickly fall apart, which is why I haven't released these Rust-like
    executors as a standalone package.

This is a situation where Antithesis can help, because it makes the underlying
scheduling decisions reproducible within Antithesis, even for `BaseExecutor`.
If such a failure occurs in Antithesis-hosted CI, you can at least reproduce it
in a local Antithesis instance. Of course, this doesn't help at all if a failure
occurs on the machine of a user, where you're not necessarily running under a
deterministic OS. Moreover, determinism by itself doesn't make it more likely
to encounter a failure; for that you need some kind of "malicious" scheduler
like `ConcurrentExecutor` that actively tries to induce these kinds of failures
in a deterministic way. If you have such a deterministic executor in your application,
you have a much better chance at reproducing failures locally when they're only occuring
on some OS/hardware of your customers.

## Shrinking Examples

Ok, so much for asynchronous code, but surely the situation is better when it
comes to synchronous code, right? Well.. to answer that, we'll have to learn
about what "shrinking" is when it comes to property based testing.

Simply put, "shrinking" refers to the process of transforming some (possibly large) input
that causes a test failure into a smaller input that causes the same failure. For instance,
for the property `iseven`, any odd number results in a failure/returning `false`. This
can be `7`, `99`, `23456721` or any other odd number. Property based testing libraries take
that input and (depending on their design) "shrink" that input to a smaller example. In this case,
we'd likely end up with `1`:

```julia
julia> using Supposition

julia> data = Any[]; # store the failures somewhere

julia> function shrinkExample(p)
           iseven(p) && return true
           # record failures in our memory
           push!(data, p)
           false
       end
shrinkExample (generic function with 2 methods)

julia> @check db=false shrinkExample(Data.Integers{UInt8}());
┌ Error: Property doesn't hold!
│   Description = "shrinkExample"
│   Example = (0x01,)
└ @ Supposition ~/Documents/projects/Supposition.jl/src/testset.jl:292
Test Summary: | Fail  Total  Time
shrinkExample |    1      1  0.0s

julia> data
6-element Vector{Any}:
 0x17
 0x0b
 0x05
 0x03
 0x03
 0x01
```

The initial failure was `0x17` (or 23 in decimal) and successfull shrinks reduced
the input to `0x01` (or just 1 in decimal), which is a minimal counterexample for `iseven` on `UInt8`.

!!! note "Complexity"
    This example is purposefully simple - Supposition.jl can do much more complex shrinks of composite
    objects out of the box. Check out the [documentation](https://seelengrab.github.io/Supposition.jl/stable/index.html) if you're interested!

For such a simple property, shrinking was straightforward. The statespace of the input is relatively small (just 256 states), and half
of those will result in a failure. However, even slightly more complicated examples will give much worse results (through no fault of the shrinking process). For example,
consider this function that checks whether the third element in a random vector is not `0x5`:

```julia
function third_is_not_five(v)
   # we can assume `v` has at least 5 elements, fill those with random data
   v .= rand(UInt8, 5)
   v[3] != 0x5
end
```

We can run this for a number of inputs and see that this property does fail
every so often, albeit inconsistently:

```julia
julia> findfirst(!third_is_not_five(rand(UInt8, 5)) for _ in 1:10_000 )
409

julia> findfirst(!third_is_not_five(rand(UInt8, 5)) for _ in 1:10_000 )
423

julia> findfirst(!third_is_not_five(rand(UInt8, 5)) for _ in 1:10_000 )
741
```

If we now try to find a counterexample with Supposition.jl, we find something intriguing:

```julia
julia> using Supposition

# generate random `Vector{UInt8}` with 5 elements
julia> vec = Data.Vectors(Data.Integers{UInt8}();min_size=5,max_size=5);

julia> @check third_is_not_five(vec);
┌ Error: Property doesn't hold!
│   Description = "third_is_not_five"
│   Example = (UInt8[0x00, 0x00, 0x00, 0x00, 0x00],)
└ @ Supposition ~/Documents/projects/Supposition.jl/src/testset.jl:292
Test Summary:     | Fail  Total  Time
third_is_not_five |    1      1  0.0s
```

Supposition.jl finds the minimum input - it's completely filled with `0x0`! This
makes sense, because we're replacing the contents of the vector we're putting
into `third_is_not_five` with random data, and only *then* check whether the property
holds. We can record that data with `event!`, and inspect it in the final report afterwards:

```julia
julia> @check function third_is_not_five(v=vec)
           v .= rand(UInt8, 5)
           event!("ACTUAL DATA", v)
           v[3] != 5
       end;
Events occured: 1
    ACTUAL DATA
        UInt8[0xf7, 0x46, 0x05, 0x71, 0x1e]
┌ Error: Property doesn't hold!
│   Description = "third_is_not_five"
│   Example = (v = UInt8[0x00, 0x00, 0x00, 0x00, 0x00],)
└ @ Supposition ~/Documents/projects/Supposition.jl/src/testset.jl:292
Test Summary:     | Fail  Total  Time
third_is_not_five |    1      1  0.0s
```

And now we can see that indeed, the third element of the actual data we're
checking is `0x05`. Unfortunately, all of the other data is a jumbled mess,
and Supposition.jl did seemingly nothing to shrink that. This is not quite
true - Supposition.jl is able to reproduce that exact failure again if we
rerun the test:

```julia
julia> @check third_is_not_five(vec)
Events occured: 1
    ACTUAL DATA
        UInt8[0xf7, 0x46, 0x05, 0x71, 0x1e]
┌ Error: Property doesn't hold!
│   Description = "third_is_not_five"
│   Example = (UInt8[0x00, 0x00, 0x00, 0x00, 0x00],)
└ @ Supposition ~/Documents/projects/Supposition.jl/src/testset.jl:292
Test Summary:     | Fail  Total  Time
third_is_not_five |    1      1  0.0s
```

The problem is that the relationship between the RNG object used by `rand`
(a `Xoshiro256++`, for the curious) and that test failure is quite complicated.
For any individual invocation of `rand(UInt8)`, we'd expect to get `0x05`
with a probability of `1/256`. For the 10_000 examples Supposition.jl tries
by default, we'd expect to see a five 39 times, which is quite rare. In total, there are `256^5` different `Vector{UInt8}` of length 5,
and only `256^4` of those have a 5 in position 3. Supposition.jl
does control the seed of the RNG object, but figuring that relationship out while also shrinking data is,
by the nature of `Xoshiro256++` being a good PRNG, very difficult. The relationship between the seed and values in the vector is highly
nonlinear, and there may not even be a seed that produces the minimal example at all!

!!! note "Antithesis & Meta knowledge "
    For Antithesis, this is a problem - from what I could gather, it has no such "meta knowledge" about the data
    an application generates, so it must immediately run into the same problems Supposition.jl runs in when we
    just generate some data with `rand`. The people behind Antithesis know this, which is why their [talk about running Super Mario](https://antithesis.com/blog/sdtalk/)
    focuses most of its time on how a programmer can guide Antithesis towards "better" executions that get Mario farther into levels,
    as well as on how to model Super Mario in such a way as to make it likely to hit good inputs.

Of course, if we don't rely on the randomness of `rand` directly but instead check the
generated vector, Supposition.jl has no problems to minimize the example as far
as possible:

```julia
julia> @check function third_is_not_five(v=vec)
           event!("ACTUAL DATA", v)
           v[3] != 5
       end;
Events occured: 1
    ACTUAL DATA
        UInt8[0x00, 0x00, 0x05, 0x00, 0x00]
┌ Error: Property doesn't hold!
│   Description = "third_is_not_five"
│   Example = (v = UInt8[0x00, 0x00, 0x05, 0x00, 0x00],)
└ @ Supposition ~/Documents/projects/Supposition.jl/src/testset.jl:292
Test Summary:     | Fail  Total  Time
third_is_not_five |    1      1  0.0s
```

This is because Supposition.jl has much more knowledge about the vector it generated
itself than is known just from the seed of the RNG. This additional structure allows it to shrink properly and more
targeted than if it had to shrink purely through an RNG seed.

This too is not a panacea though - if we put in 64-bit `UInt` instead of 8-bit `UInt8`, the test passes even for a million random inputs:

```julia
julia> uint_vec = Data.Vectors(Data.Integers{UInt}();min_size=5,max_size=5);

julia> @check db=false max_examples=1_000_000 function third_is_not_five(v=uint_vec)
           event!("ACTUAL DATA", v)
           v[3] != 5
       end;
Test Summary:     | Pass  Total  Time
third_is_not_five |    1      1  1.9s
```

And still the same for ten million inputs:

```julia
julia> @check db=false max_examples=10_000_000 function third_is_not_five(v=uint_vec)
           event!("ACTUAL DATA", v)
           v[3] != 5
       end;
Test Summary:     | Pass  Total   Time
third_is_not_five |    1      1  18.6s
```

This once again comes back around to probabilities. With `UInt`, it's exceedingly
unlikely to hit exactly `5` in the third position at all, so Supposition.jl never
encounters a counterexample it could shrink. The probabilities for hitting
e.g. data races or otherwise extremely rare failures just get worse as programs & their statespaces
grow larger. There are some techniques you can use to help Supposition.jl along (e.g. nudging the generation
process in a certain direction with [`target!`](https://seelengrab.github.io/Supposition.jl/stable/Examples/target.html)),
but those come at the cost of requiring quite a lot of domain specific knowledge to use correctly.

## Conclusion

The people behind Anthithesis are well aware of these problems,
which is why they're not *just* selling a deterministic hypervisor, but
also [an API](https://antithesis.com/docs/using_antithesis/sdk/overview.html) to give guidance for debugging.
A brief look at the SDKs suggest that they're very bare bones for now, and don't seem to
provide any shrinking capability of their own (though [some comments on HackerNews](https://news.ycombinator.com/item?id=40069361) suggest that
the Antithesis team is actively working on that, so this will probably improve with time).

That said, there's also the fact that a deterministic OS gives you much more than just scheduling reproducibility,
such as deterministic RAM contents and I/O timing (up to a minimum the operation takes,
I guess?), which may be immensely helpful for some failures in e.g. code you as a developer don't have control over.

My gut feeling is that running deterministic property based tests inside of a system like Antithesis is
a good idea. Even better if you can leverage determinism in your actual application as well, e.g. by using
a deterministic scheduler/executor to allow exact reproducibility of issues encountered by your users.
Even with those capabilities, just running/testing your application under Antithesis (while undoubtedly helpful & a good idea)
doesn't remove having to think carefully about how & where to ensure your application has the properties you want it to have.

In terms of testing & reliability overall, these are certainly amazing developments. The future of testing is very exciting, and I hope
more people use this approach over conventional testing!
