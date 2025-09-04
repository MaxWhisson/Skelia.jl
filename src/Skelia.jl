module Skelia

export Feedback
export Workpool
export runSkeleton
export destroy
export create_structure
export orderedCollector

##############################################################################
####                               Imports                                ####
##############################################################################

using Base.Threads

##############################################################################
####                                Types                                 ####
##############################################################################

abstract type Skeleton end

struct QUIT

end

struct Workpool <: Skeleton
    n_workers::Int
    inner::Any
end

struct Feedback <: Skeleton
    predicate::Function # true to progress
    inner::Any
end

##############################################################################
####                              Functions                               ####
##############################################################################

function worker(f::Function, inputs::Channel, dest::Channel)
    while true
        item = take!(inputs)
        if typeof(item) == QUIT
            put!(inputs, QUIT())
            put!(dest, QUIT())
            break
        end

        (pos, val) = item
        map((res -> put!(dest, (pos, res))), f(val))
    end
end

function create_feedback(pred::Function, inputs::Channel, destOut::Channel, destIn::Channel)
    while true
        item = take!(inputs)
        if typeof(item) == QUIT
            put!(destOut, QUIT())
            break
        end
        if pred(item[2])
            put!(destOut, item)
        else
            put!(destIn, item)
        end
    end
end

function orderedCollector(n::Int, inputs::Channel, output::Channel)
    res = Vector{Any}(undef, n)
    for i in 1:n
        (pos, val) = take!(inputs)
        res[pos] = val
    end
    put!(output, res)
end

function runSkeleton(s::Any, data::AbstractArray, collector::Function)
    (inputChannel, uncolChannel) = create_structure(s)
    res = runSkeleton(inputChannel, uncolChannel, data, collector)
    destroy(inputChannel)
    return res
end

function runSkeleton(inputs::Channel, outputs::Channel, data::AbstractArray, collector::Function)
    resultsChannel = Channel(Inf)
    @Threads.spawn collector(length(data), outputs, resultsChannel)
    zip(1:length(data), data) .|> (item -> put!(inputs, item))
    res = take!(resultsChannel)
    return res
end

function destroy(inputs::Channel)
    put!(inputs, QUIT())
end

function create_structure(s::Any)
    uncolChannel = Channel(Inf)
    inputChannel = buildSkel(s, uncolChannel)
    return (inputChannel, uncolChannel)
end

function buildSkel(f::Function, dest::Channel; inChan = false)
    inputChannel = inChan == false ? Channel(Inf) : inChan
    @Threads.spawn worker(f, inputChannel, dest)
    return inputChannel
end

function buildSkel(s::Workpool, dest::Channel; inChan = false)
    entryChannel = inChan == false ? Channel(Inf) : inChan
    for i in 1:s.n_workers
        buildSkel(s.inner, dest, inChan = entryChannel)
    end
    return entryChannel
end

function buildSkel(stages::Vector, dest::Channel; inChan = false)
    if length(stages) == 1
        return buildSkel(stages[1], dest)
    end
    inChanNext = buildSkel(stages[2:end], dest)
    return buildSkel(stages[1], inChanNext)
end

function buildSkel(skeleton::Feedback, dest::Channel; inChan = false)
    feedIn = inChan == false ? Channel(Inf) : inChan
    innerIn = buildSkel(skeleton.inner, feedIn)
    @Threads.spawn create_feedback(skeleton.predicate, feedIn, dest, innerIn)
    return innerIn
end

end