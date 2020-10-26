using ProbNumODE
using Test
using Plots
using GaussianDistributions
using LinearAlgebra
using OrdinaryDiffEq
using DiffEqProblemLibrary.ODEProblemLibrary: importodeproblems; importodeproblems()
import DiffEqProblemLibrary.ODEProblemLibrary: prob_ode_linear, prob_ode_2Dlinear, prob_ode_lotkavoltera, prob_ode_fitzhughnagumo


@testset "Solution" begin
    prob = ProbNumODE.remake_prob_with_jac(prob_ode_lotkavoltera)
    sol = solve(prob, EKF1(), adaptive=false, dt=1e-2)

    @test length(sol) > 2
    @test length(sol.t) == length(sol.u)
    @test length(prob.u0) == length(sol.u[end])

    # Destats
    @testset "DEStats" begin
        @test length(sol.t) == sol.destats.naccept + 1
        @test sol.destats.naccept <= sol.destats.nf
    end

    @testset "Hit the provided tspan" begin
        @test sol.t[1] == prob.tspan[1]
        @test sol.t[end] == prob.tspan[2]
    end

    @testset "Prob and non-prob u" begin
        @test sol.u == sol.pu.μ
    end

    @testset "Call on known t" begin
        @test sol(sol.t) == sol.pu
    end

    @testset "Correct initial values" begin
        @test sol.pu[1].μ == prob.u0
        @test iszero(sol.pu[1].Σ)
    end

    # Interpolation
    @testset "Dense Solution" begin
        t0 = prob.tspan[1]
        t1, t2 = t0 + 1e-2, t0 + 2e-2

        u0, u1, u2 = sol(t0), sol(t1), sol(t2)
        @test norm.(u0.μ - u1.μ) < norm.(u0.μ - u2.μ)

        @test all(diag(u1.Σ) .< diag(u2.Σ))

        @test sol(t0:1e-3:t1) isa StructArray{Gaussian{T,S}} where {T,S}
    end
end
