module Skelia

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

struct Workpool <: Skeleton
    n_workers::Int
    inner::Skeleton
end

struct Pipeline <: Skeleton
    stages::Vector{Skeleton}
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
        f(item[2]) .|> (res -> put!(dest, (item[1], res)))
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

function run(s::Skeleton, data::AbstractArray, collector::Function)
    (inputChannel, uncolChannel) = create_structure(s)
    return run(inputChannel, uncolChannel, data, collector)
end

function run(inputs::Channel, outputs::Channel, data::AbstractArray, collector::Function)
    resultsChannel = Channel(Inf)
    @spawn collector(length(data), outputs, resultsChannel)
    zip(1:length(data), data) .|> (item -> put!(inputs, item))
    res = take!(resultsChannel)
    put!(inputs, QUIT())
    return res
end

function create_structure(s::Skeleton)
    uncolChannel = Channel(Inf)
    inputChannel = buildSkel(s, uncolChannel)
    return (inputChannel, uncolChannel)
end

function buildSkel(s::Seq, dest::Channel; inChan = false)
    inputChannel = inChan == false ? Channel(Inf) : inChan
    @spawn worker(s.f, inputChannel, dest)
    return inputChannel
end

function buildSkel(s::Workpool, dest::Channel; inChan = false)
    entryChannel = inChan == false ? Channel(Inf) : inChan
    buildSkel(s.inner, dest, inChan = entryChannel)
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
    @spawn create_feedback(skeleton.predicate, feedIn, dest, innerIn)
    return innerIn
end

end
