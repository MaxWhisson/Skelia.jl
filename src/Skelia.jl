module Skelia

export Seq
export Pipeline
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

struct Seq <: Skeleton
    f::Function
end

struct Pipeline <: Skeleton
    stages::Vector{Skeleton}
end

struct Workpool <: Skeleton
    n_workers::Int
    inner::Skeleton
end

struct Feedback <: Skeleton
    predicate::Function # true to progress
    inner::Skeleton
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

function orderedCollector(n::Int, inputs::Channel, output::Channel; resType::Type = Any)
    res = Vector{resType}(undef, n)
    for i in 1:n
        (pos, val) = take!(inputs)
        res[pos] = val
    end
    put!(output, res)
end

function runSkeleton(s::Skeleton, data::AbstractArray, collector::Function)
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

function create_structure(s::Skeleton)
    uncolChannel = Channel(Inf)
    inputChannel = buildSkel(s, uncolChannel)
    return (inputChannel, uncolChannel)
end

function buildSkel(s::Seq, dest::Channel; inChan = false)
    inputChannel = inChan == false ? Channel(Inf) : inChan
    @Threads.spawn worker(s.f, inputChannel, dest)
    return inputChannel
end

function buildSkel(s::Workpool, dest::Channel; inChan = false)
    entryChannel = inChan == false ? Channel(Inf) : inChan
    for i in 1:s.n_workers
        buildSkel(s.inner, dest, inChan = entryChannel)
    end
    return entryChannel
end

function buildSkel(s::Pipeline, dest::Channel; inChan = false)
    if length(s.stages) == 1
        return buildSkel(s.stages[1], dest)
    end
    inChanNext = buildSkel(Pipeline(s.stages[2:end]), dest)
    return buildSkel(s.stages[1], inChanNext, inChan = inChan)
end

function buildSkel(skeleton::Feedback, dest::Channel; inChan = false)
    feedIn = inChan == false ? Channel(Inf) : inChan
    innerIn = buildSkel(skeleton.inner, feedIn)
    @Threads.spawn create_feedback(skeleton.predicate, feedIn, dest, innerIn)
    return innerIn
end

end