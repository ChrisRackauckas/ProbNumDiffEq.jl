using ProbNumODE
using Test
using DifferentialEquations
using Measurements
using DiffEqDevTools



@testset "Solve Fitzhugh-Nagumo with constant steps" begin

    prob = fitzhugh_nagumo()
    sol = solve(prob, EKF0(), steprule=:constant, dt=0.001, q=1)

    @test length(sol) > 2
    @test length(sol.t) == length(sol.u)
    @test length(prob.u0) == length(sol.u[end])

    true_sol = solve(prob, abstol=1e-10, reltol=1e-10)
    @test Measurements.values.(sol[end]) ≈ true_sol[end] atol=0.01
end



@testset "Gaussian" begin
    @test typeof(ProbNumODE.Gaussian([1.; -1.], [1. 0.1; 0.1 1.])) <: ProbNumODE.Gaussian
    # Non-symmetric covariance should throw an error
    @test_throws Exception ProbNumODE.Gaussian([1.; -1.], [1. 0.; 0.1 1.])
end


@testset "Priors" begin
    prior = ProbNumODE.ibm(1, 2)
    @test typeof(prior.A(0.1)) <: AbstractMatrix
    @test typeof(prior.Q(0.1)) <: AbstractMatrix
end
