using Skeleia
using Test

@testset "Skeleia.jl" begin
    @test Skeleia.run(
        Skeleia.Seq((x -> x + 1)), 
        [1,2,3,4,5], 
        Skeleia.orderedCollector) == [2,3,4,5,6]

    @test Skeleia.run(
        Skeleia.Feedback(
            (x -> x==1), 
            Skeleia.Seq(x -> x%2==0 ? x/2 : 3x+1)), 
        [99,82,15,112],
        Skeleia.orderedCollector) == [1,1,1,1]

    @test Skeleia.run(
        Skeleia.Workpool(
            5, 
            Skeleia.Seq((x -> x + 1))), 
        [1,2,3,4,5], 
        Skeleia.orderedCollector) == [2,3,4,5,6]

    @test Skeleia.run(
        Skeleia.Pipeline(
            [
                Skeleia.Seq((x -> x + 1)), 
                Skeleia.Seq((x -> 2x))
            ]), 
            [1,2,3,4,5], 
            Skeleia.orderedCollector) == [4,6,8,10,12]
end
