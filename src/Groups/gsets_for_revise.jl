mutable struct OrbitIterator{T, S}
  gset::GSetByElements{T, S}
end

function iterate_orbits(Omega::GSetByElements{T, S}) where {T, S}
  return OrbitIterator{T, S}(Omega)
end

function iterate(iter::OrbitIterator{T, S}, state = nothing) where {T <: Union{Group, FinGenAbGroup}, S}
  Omega = iter.gset
  if isnothing(state)
    s = 0
    orbs = typeof(Omega)[]
  else
    s = state[1]
    orbs = state[2]
  end

  while s < length(Omega.seeds)::Int
    s += 1
    p = (Omega.seeds[s])::S
    if any(o -> p in o, orbs)
      continue
    end
    o = orbit(Omega, p)
    return o, (s, push!(orbs, o))
  end
  return nothing
end

function my_orbits(Omega::GSetByElements)
  iter = iterate_orbits(Omega)
  orbs = typeof(Omega)[]
  x = iterate(iter)
  while !isnothing(x)
    push!(orbs, x[1])
    x = iterate(iter, x[2])
  end
  return orbs
end
