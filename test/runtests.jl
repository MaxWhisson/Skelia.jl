using Skelia
using Test

# silly toy collector
function orderedTwiceCollector(n::Int, inputs::Channel, output::Channel)
    res = Vector{Any}(undef, 2n)
    for i in 1:2n
        (pos, val) = take!(inputs)
        res[(2(pos - 1)) + val[1]] = val[2]
    end
    put!(output, res)
end

function createAndDestroy()
    (inputs, outputs) = Skelia.create_structure(
        Skelia.Workpool(
            5, 
            (x -> x + 1)
        )
    )
    res = Skelia.runSkeleton(inputs, outputs, collect(1:10), Skelia.orderedCollector)
    Skelia.destroy(inputs)
    return res
end

@testset "Skelia.jl" begin
    # build and test seq
    @test Skelia.runSkeleton(
        (x -> x + 1), 
        [1,2,3,4,5], 
        Skelia.orderedCollector) == [2,3,4,5,6]

        # build and test feedback
    @test Skelia.runSkeleton(
        Skelia.Feedback(
            (x -> x==1), 
            (x -> x%2==0 ? x/2 : 3x+1)
        ), 
        [99,82,15,112],
        Skelia.orderedCollector) == [1,1,1,1]

    # build and test workpool
    @test Skelia.runSkeleton(
        Skelia.Workpool(
            5, 
            (x -> x + 1)
        ), 
        [1,2,3,4,5], 
        Skelia.orderedCollector) == [2,3,4,5,6]

    # build and test pipe
    @test Skelia.runSkeleton(
            [
                (x -> x + 1), 
                (x -> 2x)
            ], 
            [1,2,3,4,5], 
            Skelia.orderedCollector) == [4,6,8,10,12]

    # build and test pipe of workpool
    @test Skelia.runSkeleton(
            [
                Skelia.Workpool(5, (x -> x + 1)), 
                Skelia.Workpool(5, (x -> 2x))
            ], 
            [1,2,3,4,5], 
            Skelia.orderedCollector) == [4,6,8,10,12]

    # build and test task splitting
    @test Skelia.runSkeleton(
            [
                (x -> [(1, x + 1), (2, x + 1)]), 
                (x -> [(x[1], 2x[2])])
            ], 
            [1,2,3,4,5], 
            orderedTwiceCollector) == [4,4,6,6,8,8,10,10,12,12]

    # test creating and destroying skeleton manually
    @test createAndDestroy() == collect(2:11)
end
