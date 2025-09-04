# Skelia

[![Build Status](https://github.com/test1932/Skelia.jl/actions/workflows/CI.yml/badge.svg?branch=master)](https://github.com/test1932/Skelia.jl/actions/workflows/CI.yml?query=branch%3Amaster)

## Description

This is a package with the goal of simplifying the creation of Parallel Algorithmic Skeletons (PAS) in Julia. The interface is inspired by the Skel (https://skel.weebly.com/about-skel.html) library for Erlang, with some functionality borrowed from C++'s Fastflow (https://github.com/fastflow/fastflow) library - namely the ability for a task to split into multiple tasks to allow for the parallelization of the dividing stage of Divide-and-Conquer (DaC) algorithms.

Additionally, this package also allows the creation of skeletons to be separated from their use. This functionality is intended for cases where the same operation needs to be performed multiple times, but some intermediate computation that can't be parallelized needs to be computed in between. This mode of operation is intended to reduce the overhead of creating the threads.

Like Skel, Fastflow, and GrPPI (another C++ PAS interface - https://github.com/arcosuc3m/grppi), Skelia also supports the nesting of PAS structures, e.g. having a `Workpool` of pipeline PAS for cases where the number of tasks is quite small, but each task is expensive and has a pipeline structure.

Something else to note is the lack of a farm PAS. This has been replaced with `Workpool` as the implementation is more efficient and the edge cases where a farm will outperform it should not be relied on.

## Interface

The general interface, like Skel, is very simple. Additional skeleton types may be added. For simplicity, when comparing to Skel, the explicit `Seq` and `Pipe` PAS have been removed, with `Seq`s being represented just by their function, and `Pipe`s being represented by a vector of PAS. This somewhat improves readability, but makes the typing of the functions a bit messier.

For specifying a PAS structure, the following structs are provided:

* `Workpool\2` which takes a `n`umber of workers and an `inner` PAS. This structure is replicated `n` times to execute in parallel, with each worker PAS requesting a new task when completed.

* `Feedback\2` which takes a `Any -> Bool` `predicate` and an `inner` skeleton. Tasks are fed into the `inner` PAS with the results are passed into the `predicate`. If this returns true, the result is passed onto the next stage, otherwise it is fed back into the `inner` PAS.

## Examples

The following is a simple example with a `Workpool`

```
function fib(n)
    if n <= 1
        return 1
    end
    return fib(n-1) + fib(n-2)
end

function singleWorker()
    Skelia.runSkeleton(
        fib, 
        [42,42,42,42,42], 
        Skelia.orderedCollector
    )
end

function multiWorker()
    Skelia.runSkeleton(
        Skelia.Workpool(5, fib), 
        [42,42,42,42,42], 
        Skelia.orderedCollector
    )
end
```

These PAS can be nested easily, the following is an example that nests a `Workpool` within `Feedback` to demonstrate the Collatz conjecture for some numbers in parallel:

```
Skelia.runSkeleton(
    Skelia.Feedback(
        (x -> x==1),
        Skelia.Workpool(
            5, 
            (x -> x%2==0 ? x/2 : 3x+1)
        )
    ), 
    [99,82,15,112],
    Skelia.orderedCollector
)
```

and here's a pipeline of farms that adds one one to each number then doubles them:

```
Skelia.runSkeleton(
    [
        Skelia.Workpool(5, (x -> x + 1)), 
        Skelia.Workpool(5, (x -> 2x))
    ], 
    [1,2,3,4,5], 
    Skelia.orderedCollector
)
```

Finally, an example that deals with splitting tasks:

```
function orderedTwiceCollector(n::Int, inputs::Channel, output::Channel)
    res = Vector{Any}(undef, 2n)
    for i in 1:2n
        (pos, val) = take!(inputs)
        res[(2(pos - 1)) + val[1]] = val[2]
    end
    put!(output, res)
end

Skelia.runSkeleton(
    [
        (x -> [(1, x + 1), (2, x + 1)]), 
        (x -> [(x[1], 2x[2])])
    ], 
    [1,2,3,4,5], 
    orderedTwiceCollector
)
```

This is obviously not a good example of *what* to use this for, but it demonstrates the functionality.