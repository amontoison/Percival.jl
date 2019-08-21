export al

using Logging, SolverTools

"""Implementation of a augmented Lagrangian method for:

	min f(x)  s.t.  c(x) = 0, l ≦ x ≦ u"""

function al(nlp :: AbstractNLPModel; max_iter :: Int = 1000, max_time :: Real = 30.0)

	x = copy(nlp.meta.x0)
	gp = zeros(nlp.meta.nvar)
	cx = cons(nlp, x)
	gx = grad(nlp, x)
	Jx = jac(nlp, x)

	# penalty parameter
	μ = 10.0
	# Lagrange multiplier
	y = cgls(Jx', gx)[1]
	# tolerance
	eta = 0.5

	# create initial subproblem
	al_nlp = AugLagModel(nlp, y, μ)

	# stationarity measure
	gL =  grad(nlp, x) - jtprod(nlp, x, y)
	project_step!(gp, x, -gL, nlp.meta.lvar, nlp.meta.uvar) # Proj(x - gL) - x
	normgp = norm(gp)
	normcx = norm(cx)

	iter = 0
	start_time = time()
	el_time = 0.0

 	@info log_header([:iter, :normgp, :normcx], [Int, Float64, Float64])
	@info log_row(Any[iter, normgp, normcx])

	# TODO: Add keyword arguments atol, rtol, max_eval
	solved = normgp ≤ 1e-5 && normcx ≤ 1e-8
	tired = iter > max_iter || el_time > max_time

	#adaptive tolerance
	#atol = 0.5

	while !(solved || tired)

		# solve subproblem
		S = with_logger(NullLogger()) do
			tron(al_nlp, x = x)
		end
		x = S.solution
		cx = cons(nlp, x)
		normcx = norm(cx)

		if normcx <= eta
			al_nlp.y = al_nlp.y - al_nlp.mu * cx
			eta = eta / (al_nlp.mu)^0.9
		else
			μ = 100 * μ
			al_nlp.mu  = μ
			eta = 1 / μ^0.1
		end

		# stationarity measure
		gL = grad(nlp, x) - jtprod(nlp, x, al_nlp.y)
		project_step!(gp, x, -gL, nlp.meta.lvar, nlp.meta.uvar) # Proj(x - gL) - x
		normgp = norm(gp)

		iter += 1
		el_time = time() - start_time
		solved = normgp ≤ 1e-5 && normcx ≤ 1e-8
		tired = iter > max_iter || el_time > max_time

		@info log_row(Any[iter, normgp, normcx])
	end

	if solved
		status = :first_order
	elseif tired
		if iter > max_iter
			status = :max_iter
		end
		if el_time > max_time
			status = :max_time
		end
	end

	return GenericExecutionStats(status, nlp, solution = x, objective = obj(nlp, x), dual_feas = normgp, primal_feas = normcx,
			iter = iter, elapsed_time = el_time)
end
