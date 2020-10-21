"""accept/reject previous step and chose new dt

"This is done at the top so that way the interator interface happens mid-step instead of post-step"
UPDATE 17-09-2020:
Had trouble with correclty handling the exact step to T, so I moved the "apply step" stuff
into loopfooter!.
"""
function loopheader!(integ)
    integ.iter += 1
    fix_dt_at_bounds!(integ)
end

function fix_dt_at_bounds!(integ)
    integ.dt = min(integ.opts.dtmax, integ.dt)
    integ.opts.force_dtmin && (integ.dt = max(integ.opts.dtmin, integ.dt))

    if integ.dt^(1/integ.cache.q) < eps(eltype(integ.u))
        @warn "Small step size: h^q < eps(u)! Continuing, but this could lead to numerical issues" integ.dt
    end

    next_t = integ.t + integ.dt
    if next_t + integ.opts.dtmin^(1/2) > integ.prob.tspan[2]
        # Avoid having to make a step smaller than dtmin in the next step
        @debug "Increasing the step size now to avoid having to do a really small step next to hit t_max"
        integ.dt = integ.prob.tspan[2] - integ.t
    end
end


"""Calculate new timesteps, save, apply the callbacks"""
function loopfooter!(integ)

    integ.accept_step = integ.opts.adaptive ? integ.EEst < 1 : true


    integ.opts.adaptive && (integ.dt = propose_step!(integ.steprule, integ))

    integ.accept_step ? (integ.destats.naccept += 1) : (integ.destats.nreject += 1)

    any(isnan.(integ.cache.diffmat)) && error("Estimated diffusion is NaN")
    integ.opts.adaptive && isnan(integ.EEst) && error("Error estimate is NaN")

    # Accept or reject the step: Moved this here from loopheader!
    if integ.iter > 0 && integ.accept_step
        integ.success_iter += 1
        apply_step!(integ)
    end
end


"""This could handle smoothing and uncertainty-calibration"""
function postamble!(integ)
    if isstatic(integ.diffusionmodel) # Calibrate
        for s in integ.state_estimates
            s.Σ .*= integ.diffusions[end]
        end
        integ.diffusions = [integ.diffusions[end] for s in integ.diffusions]
    end
    integ.smooth && smooth_all!(integ)

    integ.sol = DiffEqBase.build_solution(
        integ.prob, integ.alg,
        integ.times,
        integ.state_estimates,
        integ.diffusions,
        integ;
        retcode=integ.retcode,
        destats=integ.destats)
end


function apply_step!(integ)
    copy!(integ.cache.x, integ.cache.x_filt)
    copy!(integ.u, integ.cache.u_filt)
    integ.t = integ.t + integ.dt

    # For the solution
    push!(integ.state_estimates, copy(integ.cache.x))
    push!(integ.times, copy(integ.t))
    push!(integ.diffusions, copy(integ.cache.diffmat))
end
