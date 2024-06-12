@def title = "RAII in Julia"
@def tags = ["cpp", "techniques", "julia"]
@def rss_description = "RAII is a very powerful technique for managing access to external shared resources in C++. Is there an equivalent in Julia, and if so, how can we take advantage of it?"
@def rss_pubdate = Date(2024, 6, 12)

# RAII in Julia

I've recently had an interview for a position as a C++ Firmware Developer, where we talked a bit about resource management and lifetimes
of shared resources on microcontrollers. One key aspect that came up is of course RAII - or "Resource Acquisition is Initialization".
See the [C++ Reference](https://en.cppreference.com/w/cpp/language/raii) for a fully detailed definition, but in a nutshell, RAII is a technique for binding access to a shared resource to the lifetime
of an object. How does that work, and can we emulate those semantics in Julia?

For simplicities sake, I'm only going to talk about resources that require exclusive access. If there is some overlap in access possible, there can be
additional design considerations, but even this seemingly simple case already has lots of semantic complications. Additionally, while the motivational
example for this article is resource management on microcontrollers, I'm not actually going to talk a lot about microcontrollers here, particularly
when it comes to Julia code. I have written about [Julia on microcontrollers](https://seelengrab.github.io/articles/Julia%20Abstractions%20for%20Arduino%20registers/)
in the past, but for now, using the techniques presented here in that environment is not always practical. That'll be something for a future article ;)

## Why RAII?

Before we dive into some Julia code, let's establish a baseline and see in what sort of situations RAII is helpful.
For example, you might have a shared communication bus that various parts of your application use to communicate with some peripherals. Only one peripheral
can be communicated with at a time, so while one part of your application is busy talking to e.g. a sensor, noone else should be talking over that same bus
concurrently. You don't want to accidentally receive a message that was intended for someone else, or the other way around.
This can typically be achieved by creating a class that guards access to the bus through itself and an internal mutex. On creation of an object of that class,
the mutex is acquired and the Bus is set up for communication. As long as the object stays alive, nothing else is able to communicate on the Bus through that class.
When the object is destroyed, the mutex is released and some other part of our code can communicate on the bus.

This example might look like this:

```cpp
class CommunicationBus
{
  public:
    // the constructor of the RAII object
    CommunicationBus(Semaphore mutex) : mMutex(mutex)
    {
      // for illustration only, so assume success
      acquire(mutex);
      // now setup the bus...
    }

    // the destructor of the RAII object
    ~CommunicationBus()
    {
      // return the Bus to a safe default state
      // and then release the mutex
      release(mutex);
    }
  private:
    Semaphore mMutex;
}
```

And used like so:

```cpp
bool manage_peripheral()
{
  // Instantiate the class, thereby acquiring the mutex
  CommunicationBus bus(busMutex);

  if (!check_some_value()) {
    return false // the bus is released automatically!
  }
  
  // the bus is still alive & we have access!
  if (!check_some_other_data()) {
    return false // the bus is released automatically!
  }

  // the bus is still alive & we have access!
  // so manage/talk with the peripheral
  // ...

  return true // the bus is released!
}
```

In the above example, we acquire the bus through the dedicated mutex, and release the bus
as soon as we return. In case the code throws an exception, the destructor of `bus` is still called!
So even in the presence of stack unwinding, this will still do the right thing. What's even
better is that if we now want to add some other check to this function, we _cannot_ forget to
release the mutex, because the compiler already does it for us. Quite convenient for maintenance as
a codebase ages!

As another example, you might want to disable interrupts in a certain critical section of your code, so that you can be sure that the program is getting its work
done without having to worry about leaving some half-broken state lying around somewhere. It's important to remember (or rather, let the computer do the remembering
for you!) to reenable interrupts after you're done though! Otherwise, your application might not be able to communicate at all anymore, if your external communication
is interrupt driven. This would look similar to the above example, where we'd disable interrupts in the
constructor and reenable them in the destructor.

## Why RAII works in C++

Knowing how this technique helps with software development is one thing, but another important
aspect is knowing *why* it works. There's a few requirements on the object model & their lifetiems of C++
objects that are required to make this work. If I'm missing some aspect, please do reach out
and I'll amend this bit :)

Alright, so which semantics allow us to use RAII? First of all, it's that the lifetime
of a local, non-static C++ object is bound to the _entire_ scope of the object. In C++, scopes
are denoted by whatever you can fit inside of a pair of curly braces `{}` and an
object that is allocated inside of there is (if done automatically, not through something like `malloc`)
considered alive until the end of the scope.

Note how in the example above, we've created an instance of `CommunicationBus` right at the start
of the function, but then never again reference the object itself. Since we're guaranteed
that the object is alive until the scope exits, this is fine and is exactly what we're
leaning on here. We're guaranteed to hold the mutex until we're exiting from the function.

Secondly, C++ _guarantees_ that the destructor of `CommunicationBus` is called when an exception 
is thrown. This ensures that even non-standard return paths ensure that the resource we've acquired
is safely returned to the shared access. This doesn't guarantee that the entire program
is in a consistent state (there may be some other invariant that's been broken), but at
least in terms of this particular resource, we're A-OK.

Finally, and most importantly, destructors of RAII classes never throw an exception themselves, i.e.
they never themselves exit in a non-standard way. The reasoning for this is relatively straightforward:
the destructor must run to completion to ensure that all resources acquired by the object are themselves
released properly. If the destructor were to throw an exception midway through handling the destruction of its
constituent parts, we'd leave some invalid state lying around, and that's a recipe for future disaster.

There are some more niceties that RAII requires, but these three are the main things we're going to focus on in the next section.
Please do give the [C++ Reference section on RAII](https://en.cppreference.com/w/cpp/language/raii) a read for the full picture!

## Translating the concept to Julia

Ok, now that we know how & why RAII works, can we do much the same thing in Julia? The closest equivalent Julia has to
C++ classes with constructors & destructors are mutable structs & finalizers, so we might expect to translate the example
from above like so:

```julia
mutable struct CommunicationBus
    mMutex::Semaphore
    function CommunicationBus(Semaphore mutex)
        # for illustration only, so assume success
        acquire(mutex)

        # now setup the bus...
        obj = new(mMutex)

        # attach a finalizer to handle the mutex release
        # once we're done with it
        finalizer(obj) do
            # return Bus to a safe default state
            release(obj.mutex)
        end

        return obj
    end
end
```

And use it like so:

```julia
function manage_peripheral()
    # Instantiate the struct, thereby acquiring the mutex
    bus = CommunicationBus(busMutex);

    if (!check_some_value())
        return false # the bus is released?
    end
  
    if !check_some_other_data()
        return false # the bus is released?
    end

    # manage/talk with the peripheral
    # ...

    return true # the bus is released?
end
```

Unfortunately, this won't work as expected! Lifetimes of objects in Julia are not
simply bound by scope, but until their last use. Since nothing in our example
actually uses `bus`, the compiler is semantically allowed to finalize the
`bus` as soon as it's done creating it, effectively as if we acquired
and immediately released the `busMutex`. That would rob us of the exclusivity that
we wanted to achieve in the first place!

Ok, maybe not too big of a deal, just insert some dummy use in return paths
and we're good, right? Unfortunately, that's also not good. For one,
we'd have to think about doing this on every return path, meaning we'd lose
a big advantage of RAII in C++ by making our version hard to use & maintain correctly.
For another, the compiler is not _required_ to insert the finalizer eagerly!
It might not call the finalizer after the function returns at all, but
instead only call it later on when the garbage collector does a maintenance run,
which might be very far into the future. Much too late for our purposes.
This case would also be hit if our function throws an error! By using a non-standard
return path, the resource would be blocked much longer than necessary.

So, are we doomed in Julia? Of course not :) We can still make use of the RAII
pattern, we just have to go about it in a bit of a smarter way.

!!! note "Finalizers"
    Frankly, I'm not quite sure when I'd actually want to use a finalizer.
    Since there are no lifetime guarantees on when they are called (there's
    also active debate about whether they should be called when the program
    crashes..), they can at best provide eventual consistency/freeing of
    the shared resource. For most applications I've encountered so far,
    this isn't good - why hold onto a resource longer than necessary? That's
    just artificially limiting parallelism because of an implementation detail.

## Function-based RAII

The solution is to ditch mutable structs and finalizers entirely. Instead,
take advantage of _function scopes_ to free resources as soon as they're
ready to be freed.

Here's the way to go about it:

```julia
struct CommunicationBus
    mMutex::Semaphore
    function CommunicationBus(f, mutex::Semaphore)
        acquire(mutex)
        bus = new(mutex)
        try
            f(bus)
        finally
            release(bus.mutex)
        end
    end
end
```

That's it! This code would be used like so:

```julia
function manage_peripheral()
  # Instantiate the struct, thereby acquiring the mutex
  CommunicationBus(busMutex) do _
      if (!check_some_value())
          return false # the bus is released?
      end
  
      if !check_some_other_data()
          return false # the bus is released?
      end

      # manage/talk with the peripheral
      # ...

      return true # the bus is released?
  end
end
```

or alternatively like so, if using a closure & `do`-notation is undesirable:

```julia
# require an instance of `CommunicationBus`, so that users must have
# acquired the mutex required to instantiate the instance
function manage_peripheral(::CommunicationBus)
    if (!check_some_value())
        return false # the bus is released!
    end
  
    if !check_some_other_data()
        return false # the bus is released!
    end

    # manage/talk with the peripheral
    # ...

    return true # the bus is released!
end

function main()
    # ...

    # executes `manage_peripheral` using the resource `CommunicationBus`
    CommunicationBus(manage_peripheral, busMutex)

    # ...
end
```

How does this work now? Let's look at the definition of `CommunicationBus`
in detail:

```julia
# define a struct to act as a handle for our resource
struct CommunicationBus
    mMutex::Semaphore
    # override the default constructors & require a Semaphore
    function CommunicationBus(f, mutex::Semaphore)
        # acquire the mutex before we can construct an instance
        acquire(mutex)
        bus = new(mutex)
        try
            # pass the instance into our function, guaranteeing that
            # f has exclusive access to the specific resource
            f(bus)
        finally
            # release the mutex, no matter how we happen to exit f
            # and as soon as we do exit f
            release(bus.mutex)
        end
    end
end
```

C++ lifetimes are bound to scopes, so we have to first and foremost
emulate that behavior. We can achieve this by creating a struct & passing
that into the function we want to guard, calling the function with our struct
as an argument. This ensures that the lifetime of `bus` is at least
as long as the function we're calling. At the same time, we can fully control
acquisition & release of the mutex in our "constructor", using `finally`
to ensure the mutex is released even in the case of a thrown exception.

This also has the additional benefit of releasing the mutex as soon as
it's possible to do so, and not at some unspecified later date. Even more
awesome, the struct isn't mutable anymore and so will very likely end up
on the stack, not tracked by the garbage collector at all!

!!! note "Constructor returns"
    We don't actually have to return an instance of `CommunicationBus` from our constructor,
    and in fact we must not return an instance at all! If we were to return an
    actual instance, we'd leak our resource access outside of the limited
    scope where we can guarantee exclusivity, allowing third parties to call
    e.g. `manage_peripheral` without acquiring the resource in the constructor.

    If Julia ever requires constructors to return an instance of its type,
    we can (in theory) just give our "constructor" a different name and disable
    default constructor methods to achieve the same goal. The important part here
    is to guarantee that instances of `CommunicationBus` are always created through
    our safe method.

One detail in the above struct that's a design consideration is whether
you want to require that a semaphore is passed in explicitly. You could
also have a fixed, well-known semaphore just for `CommunicationBus` that
you then use directly in the constructor, instead of passing it in. This
could help prevent accidentally passing in an already-acquired mutex,
causing a deadlock.

## Julia-RAII in the real world

If you're a bit familiar with various IO in the Julia standard library, you might say "hey this looks familiar"
and I'd say "Have a cookie!" because you're absolutely right!
This pattern is pretty much how `lock`, `open` and some other IO & concurrency related functions already work:

```julia
# from https://github.com/JuliaLang/julia/blob/77c28ab286f48afe2512e2ae7f7310b87ca3345e/base/io.jl#L407-L414
function open(f::Function, args...; kwargs...)
    io = open(args...; kwargs...)
    try
        f(io)
    finally
        close(io)
    end
end
```

The main difference between the pattern presented here and what `open`/`lock` are doing
is that the resource here cannot be constructed without actually doing something with it.
`open`/`lock` allow the resource to exist without use, i.e. the "handles" are initialized
but access is not acquired immediately. By itself that's not a big deal,
but it does mean that you can't design your program around having _exclusive_ access
to the resource. `IO` (which is returned by the non-function `open`) in this
situation really doesn't act like a handle or shared resource at all, even though
it secretely is under the hood. E.g. `stdout` and similar are protected by internal locks
under the hood. If this were exposed in the API, it'd make some usecases
threadsafe by design, without having to lock/unlock on every access to the resource.
This would cleanly solve the problem of torn writes, where the representation of an object
can be intermixed with other printing in the final output when more than one thread tries to
write to `stdout` at the same time.

Additionally, if we'd have to acquire the lock on `stdout` on our first access and store
that information in the local task, subsequent acquisitions on the same task can be fasttracked
until we yield to another task. In the current design, that's hard to implement
because `stdout` is just a global variable that punts the locking to a `write` call.
Of course, this also has a downside in that you should not keep a live reference to `stdout`
around for long periods in your code so that you don't block other running tasks.
That change in thinking is quite a big shift!

## Conclusion

As we found out, RAII is not just a C++ exclusive thing, it's a much broader
technique that can be applied in more languages. The key is thinking about the
interplay between object lifetimes, resource management and the semantic guarantees
your language provides. If you can emulate the right semantics, you can use RAII
pretty much everywhere.

For the folks who want to know why I mentioned that this technique won't (for now)
work when programming microcontrollers with Julia: I haven't looked into supporting
`try`/`catch`/`finally` yet, which is a core requirement for making this work.
Regardless, that's about it for RAII in Julia! I hope you learned something here.
