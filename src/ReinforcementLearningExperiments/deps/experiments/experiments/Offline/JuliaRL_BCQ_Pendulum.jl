# ---
# title: JuliaRL\_BCQ\_Pendulum
# cover: assets/JuliaRL_BCQ_Pendulum_medium.png
# description: BCQ applied to Pendulum
# date: 2021-09-17
# author: "[Guoyu Yang](https://github.com/pilgrimygy)"
# ---

#+ tangle=true
using ReinforcementLearning
using StableRNGs
using Flux
using Flux.Losses

function RL.Experiment(
    ::Val{:JuliaRL},
    ::Val{:BCQ},
    ::Val{:Pendulum},
    type::AbstractString;
    save_dir = nothing,
    seed = 123,
)
    rng = StableRNG(seed)
    inner_env = PendulumEnv(T = Float32, rng = rng)
    A = action_space(inner_env)
    low = A.left
    high = A.right
    ns = length(state(inner_env))
    na = 1
    latent_dims = 10

    trajectory_num = 10000
    dataset_size = 10000
    batch_size = 64

    env = ActionTransformedEnv(
        inner_env;
        action_mapping = x -> low + (x[1] + 1) * 0.5 * (high - low),
    )
    init = glorot_uniform(rng)

    create_policy_net() = NeuralNetworkApproximator(
        model = PerturbationNetwork(
            base = Chain(
                Dense(ns + na, 64, relu; init = glorot_uniform(rng)),
                Dense(64, 64, relu; init = glorot_uniform(rng)),
                Dense(64, na; init = glorot_uniform(rng))
            ),
            ϕ = 0.05f0,
        ),
        optimizer = ADAM(0.003),
    )

    create_q_net() = NeuralNetworkApproximator(
        model = Chain(
            Dense(ns + na, 64, relu; init = init),
            Dense(64, 64, relu; init = init),
            Dense(64, 1; init = init),
        ),
        optimizer = ADAM(0.003),
    )

    create_vae_net() = NeuralNetworkApproximator(
        model = VAE(
            encoder = GaussianNetwork(
                pre = Chain(
                    Dense(ns + na, 64, relu), 
                    Dense(64, 64, relu),
                ),
                μ = Chain(Dense(64, latent_dims, init = init)),
                logσ = Chain(Dense(64, latent_dims, init = init)),
            ),
            decoder = Chain(
                Dense(ns + latent_dims, 64, relu; init = init),
                Dense(64, 64, relu; init = init),
                Dense(64, na; init = init),
            ),
            latent_dims = latent_dims,
        ),
        optimizer = ADAM(0.003),
    )

    agent = Agent(
        policy = OfflinePolicy(
            learner = BCQLearner(
                policy = create_policy_net() |> cpu,
                target_policy = create_policy_net() |> cpu,
                qnetwork1 = create_q_net() |> cpu,
                qnetwork2 = create_q_net() |> cpu,
                target_qnetwork1 = create_q_net() |> cpu,
                target_qnetwork2 = create_q_net() |> cpu,
                vae = create_vae_net() |> cpu,
                γ = 0.99f0,
                τ = 0.005f0,
                λ = 0.75f0,
                p = 10, 
                batch_size = batch_size,
                start_step = 1000,
                update_freq = 1,
            ),
            dataset = gen_JuliaRL_dataset(:SAC, :Pendulum, type; dataset_size = dataset_size),
            continuous = true,
            batch_size = batch_size,
        ),
        trajectory = CircularArraySARTTrajectory(
            capacity = trajectory_num,
            state = Vector{Float32} => (ns,),
            action = Vector{Float32} => (na,),
        ),
    )

    stop_condition = StopAfterStep(trajectory_num, is_show_progress=!haskey(ENV, "CI"))
    hook = TotalRewardPerEpisode()
    Experiment(agent, env, stop_condition, hook, "BCQ <-> Pendulum ($type dataset)")
end

#+ tangle=false
using Plots
pyplot() #hide
ex = E`JuliaRL_BCQ_Pendulum(medium)`
run(ex)
plot(ex.hook.rewards)
savefig("assets/JuliaRL_BCQ_Pendulum_medium.png") #hide

# ![](assets/JuliaRL_BCQ_Pendulum.png)
