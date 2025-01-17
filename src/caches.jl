########################################################################################
# Caches
########################################################################################
mutable struct EKCache{
    RType,ProjType,SolProjType,PType,PIType,EType,uType,duType,xType,AType,QType,
    matType,diffusionType,diffModelType,measType,puType,llType,rateType,UF,JC,
    uNoUnitsType,
} <: AbstractODEFilterCache
    # Constants
    d::Int                  # Dimension of the problem
    q::Int                  # Order of the prior
    A::AType
    Q::QType
    Ah::AType
    Qh::QType
    diffusionmodel::diffModelType
    R::RType
    Proj::ProjType
    SolProj::SolProjType
    # Also mutable
    P::PType
    PI::PIType
    E0::EType
    E1::EType
    E2::EType
    # Mutable stuff
    u::uType
    u_pred::uType
    u_filt::uType
    tmp::uType
    atmp::uNoUnitsType
    x::xType
    x_pred::xType
    x_filt::xType
    x_tmp::xType
    x_tmp2::xType
    measurement::measType
    m_tmp::measType
    pu_tmp::puType
    H::matType
    du::duType
    ddu::matType
    K1::matType
    G1::matType
    Smat::matType
    C_dxd::matType
    C_dxD::matType
    C_Dxd::matType
    C_DxD::matType
    C_2DxD::matType
    C_3DxD::matType
    default_diffusion::diffusionType
    local_diffusion::diffusionType
    global_diffusion::diffusionType
    err_tmp::duType
    log_likelihood::llType
    du1::rateType
    uf::UF
    jac_config::JC
end

function OrdinaryDiffEq.alg_cache(
    alg::AbstractEK,
    u,
    rate_prototype,
    ::Type{uEltypeNoUnits},
    ::Type{uBottomEltypeNoUnits},
    ::Type{tTypeNoUnits},
    uprev,
    uprev2,
    f,
    t,
    dt,
    reltol,
    p,
    calck,
    ::Val{IIP},
) where {IIP,uEltypeNoUnits,uBottomEltypeNoUnits,tTypeNoUnits}
    if u isa Number
        error("We currently don't support scalar-valued problems")
    end

    is_secondorder_ode = f isa DynamicalODEFunction

    q = alg.order
    d = is_secondorder_ode ? length(u[1, :]) : length(u)
    D = d * (q + 1)

    uType = typeof(u)
    # uElType = eltype(u_vec)
    uElType = uBottomEltypeNoUnits
    matType = Matrix{uElType}

    # Projections
    Proj = projection(d, q, uElType)
    E0, E1, E2 = Proj(0), Proj(1), Proj(2)
    @assert f isa AbstractODEFunction
    SolProj = f isa DynamicalODEFunction ? [Proj(1); Proj(0)] : Proj(0)

    # Prior dynamics
    P, PI = init_preconditioner(d, q, uElType)
    A, Q = ibm(d, q, uElType)
    Ah, Qh = copy(A), copy(Q)

    # Initial State
    initial_variance = ones(uElType, D)
    x0 = Gaussian(zeros(uElType, D), PSDMatrix(diagm(sqrt.(initial_variance))))

    # Diffusion Model
    diffmodel = alg.diffusionmodel
    initdiff = initial_diffusion(diffmodel, d, q, uEltypeNoUnits)
    copy!(x0.Σ, apply_diffusion(x0.Σ, initdiff))

    # Measurement model related things
    R = zeros(uElType, d, d)
    H = f isa DynamicalODEFunction ? copy(E2) : copy(E1)
    v = zeros(uElType, d)
    S = PSDMatrix(zeros(uElType, D, d))
    measurement = Gaussian(v, S)

    # Caches
    du = f isa DynamicalODEFunction ? similar(u[2, :]) : similar(u)
    ddu = f isa DynamicalODEFunction ? zeros(uElType, d, 2d) : zeros(uElType, d, d)
    pu_tmp =
        f isa DynamicalODEFunction ?
        Gaussian(zeros(uElType, 2d), PSDMatrix(zeros(uElType, D, 2d))) : copy(measurement)
    K = zeros(uElType, D, d)
    G = zeros(uElType, D, D)
    Smat = zeros(uElType, d, d)

    C_dxd = zeros(uElType, d, d)
    C_dxD = zeros(uElType, d, D)
    C_Dxd = zeros(uElType, D, d)
    C_DxD = zeros(uElType, D, D)
    C_2DxD = zeros(uElType, 2D, D)
    C_3DxD = zeros(uElType, 3D, D)

    if alg isa EK1FDB
        H = [E1; E2]
        v = [v; v]
        S = PSDMatrix(zeros(uElType, D, 2d))
        measurement = Gaussian(v, S)
        K = zeros(uElType, D, 2d)
    end

    u_pred = copy(u)
    u_filt = copy(u)
    tmp = copy(u)
    x_pred = copy(x0)
    x_filt = copy(x0)
    x_tmp = copy(x0)
    x_tmp2 = copy(x0)
    m_tmp = copy(measurement)
    err_tmp = copy(du)

    # Things for calc_J
    uf = get_uf(f, t, p, Val(IIP))
    du1 = similar(rate_prototype)
    dw1 = zero(u)
    atmp = similar(u, uEltypeNoUnits)
    if OrdinaryDiffEq.isimplicit(alg)
        jac_config = OrdinaryDiffEq.build_jac_config(alg, f, uf, du1, uprev, u, tmp, dw1)
    else
        jac_config = nothing
    end

    ll = zero(uEltypeNoUnits)
    return EKCache{
        typeof(R),typeof(Proj),typeof(SolProj),typeof(P),typeof(PI),typeof(E0),
        uType,typeof(du),typeof(x0),typeof(A),typeof(Q),matType,typeof(initdiff),
        typeof(diffmodel),typeof(measurement),typeof(pu_tmp),uEltypeNoUnits,
        typeof(du1),typeof(uf),typeof(jac_config),typeof(atmp),
    }(
        d, q, A, Q, Ah, Qh, diffmodel, R, Proj, SolProj, P, PI, E0, E1, E2,
        u, u_pred, u_filt, tmp, atmp,
        x0, x_pred, x_filt, x_tmp, x_tmp2,
        measurement, m_tmp, pu_tmp,
        H, du, ddu, K, G, Smat,
        C_dxd, C_dxD, C_Dxd, C_DxD, C_2DxD, C_3DxD,
        initdiff, initdiff * NaN, initdiff * NaN,
        err_tmp, ll, du1, uf, jac_config,
    )
end

get_uf(f, t, p, ::Val{true}) = OrdinaryDiffEq.UJacobianWrapper(f, t, p)
get_uf(f, t, p, ::Val{false}) = OrdinaryDiffEq.UDerivativeWrapper(f, t, p)
