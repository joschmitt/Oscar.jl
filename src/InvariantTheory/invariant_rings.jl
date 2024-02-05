################################################################################
#
#  Field access
#
################################################################################

coefficient_ring(I::FinGroupInvarRing) = I.field

polynomial_ring(I::FinGroupInvarRing) = I.poly_ring

action(I::FinGroupInvarRing) = I.action

group(I::FinGroupInvarRing) = I.group

is_modular(I::FinGroupInvarRing) = I.modular

function _internal_polynomial_ring(I::FinGroupInvarRing)
  if isdefined(I, :poly_ring_internal)
    return I.poly_ring_internal
  end
  return I.poly_ring
end

# Return f as an element of R. Assumes that ngens(R) == ngens(parent(f))
# and coefficient_ring(R) === coefficient_ring(parent(f)). This is not checked.
function __cast_forced(R::MPolyRing{T}, f::MPolyRingElem{T}) where T
  F = MPolyBuildCtx(R)
  for (c, e) in zip(AbstractAlgebra.coefficients(f), AbstractAlgebra.exponent_vectors(f))
    push_term!(F, c, e)
  end
  return finish(F)
end

# Assumes that parent(f) === I.poly_ring
function _cast_in_internal_poly_ring(I::FinGroupInvarRing, f::MPolyRingElem)
  if !isdefined(I, :poly_ring_internal)
    return f
  end
  return __cast_forced(_internal_polynomial_ring(I), f)
end

# Assumes that parent(f) === I.poly_ring_internal, if this is assigned,
# and parent(f) === I.poly_ring otherwise
function _cast_in_external_poly_ring(I::FinGroupInvarRing, f::MPolyRingElem)
  if !isdefined(I, :poly_ring_internal)
    return f
  end
  return __cast_forced(polynomial_ring(I), f)
end

################################################################################
#
#  Constructors
#
################################################################################

function invariant_ring(M::Vector{<: MatrixElem})
  return invariant_ring(base_ring(M[1]), M)
end

function invariant_ring(R::MPolyDecRing, M::Vector{<: MatrixElem})
  K = coefficient_ring(R)
  return invariant_ring(R, matrix_group([change_base_ring(K, g) for g in M]))
end

function invariant_ring(m::MatrixElem{T}, ms::MatrixElem{T}...) where {T} 
  return invariant_ring([m, ms...])
end

function invariant_ring(R::MPolyDecRing, m::MatrixElem{T}, ms::MatrixElem{T}...) where {T} 
  return invariant_ring(R, [m, ms...])
end

function invariant_ring(K::Field, M::Vector{<: MatrixElem})
  return invariant_ring(matrix_group([change_base_ring(K, g) for g in M]))
end

@doc raw"""
    invariant_ring(G::MatrixGroup)
    invariant_ring(K::Field = QQ, G::PermGroup)
    invariant_ring(R::MPolyDecRing, G::MatrixGroup)
    invariant_ring(R::MPolyDecRing, G::PermGroup)

Return the invariant ring of the finite matrix group or permutation group `G`.

In the latter case, use the specified field `K` as the coefficient field. 
The default value for `K` is `QQ`.

The polynomial ring `R` on which `G` acts can be supplied as a first argument,
in case an existing ring should be used.

!!! note
    The creation of invariant rings is lazy in the sense that no explicit computations are done until specifically invoked (for example, by the `primary_invariants` function).

# Examples
```jldoctest
julia> K, a = cyclotomic_field(3, "a");

julia> M1 = matrix(K, [0 0 1; 1 0 0; 0 1 0]);

julia> M2 = matrix(K, [1 0 0; 0 a 0; 0 0 -a-1]);

julia> G = matrix_group(M1, M2);

julia> IRm = invariant_ring(G)
Invariant ring
  of matrix group of degree 3 over K

julia> IRp = invariant_ring(symmetric_group(3))
Invariant ring
  of Sym(3)

julia> coefficient_ring(IRp)
Rational field
```
"""
function invariant_ring(G::MatrixGroup)
  action = mat_elem_type(typeof(G))[g.elm for g in gens(G)]
  return FinGroupInvarRing(base_ring(G), G, action)
end

function invariant_ring(R::MPolyDecRing, G::MatrixGroup)
  action = mat_elem_type(typeof(G))[g.elm for g in gens(G)]
  return FinGroupInvarRing(base_ring(G), G, action, R)
end

invariant_ring(K::Field, G::PermGroup) = FinGroupInvarRing(K, G, gens(G))

invariant_ring(G::PermGroup) = invariant_ring(QQ, G)

invariant_ring(R::MPolyDecRing, G::PermGroup) = FinGroupInvarRing(coefficient_ring(R), G, gens(G), R)

function Base.show(io::IO, ::MIME"text/plain", RG::FinGroupInvarRing)
  io = pretty(io)
  println(io, "Invariant ring")
  print(io, Indent(), "of ", Lowercase(), group(RG), Dedent())
end

function Base.show(io::IO, RG::FinGroupInvarRing)
  if get(io, :supercompact, false)
    print(io, "Invariant ring")
  else
    io = pretty(io)
    print(io, "Invariant ring of ")
    print(IOContext(io, :supercompact => true), Lowercase(), group(RG))
  end
end

# Return a map performing the right action of M on the ring R.
function right_action(R::MPolyRing{T}, M::MatrixElem{T}) where T
  @assert nvars(R) == ncols(M)
  @assert nrows(M) == ncols(M)
  n = nvars(R)

  # We consider gens(R) as the basis of a vector space given as row vectors
  # on which M acts by multiplication from the right.
  # That is, we identify gen(R, i) with the vector (0 ... 0 1 0 ... 0)
  # with 1 in position i. Then M acts on gen(R, i) via
  #   gen(R, i)^M = (0 ... 0 1 0 ... 0)*M = (M[i, 1] ... M[i, n])
  #               = M[i, 1]*gen(R, 1) + ... + M[i, n]*gen(R, n)
  # We now compute these actions of M on the variables of R.
  vars = zeros(R, n)
  x = gens(R)
  for i = 1:n
    for j = 1:n
      if iszero(M[i, j])
        continue
      end
      vars[i] = addeq!(vars[i], M[i, j]*x[j])
    end
  end

  # The action of M on an arbitrary polynomial is given by evaluating the
  # polynomial at gen(R, 1)^M, ..., gen(R, n)^M.
  right_action_by_M = (f::MPolyRingElem{T}) -> evaluate(f, vars)

  return MapFromFunc(R, R, right_action_by_M)
end

right_action(R::MPolyRing{T}, M::MatrixGroupElem{T}) where T = right_action(R, M.elm)
right_action(f::MPolyRingElem{T}, M::MatrixElem{T}) where T = right_action(parent(f), M)(f)
right_action(f::MPolyRingElem{T}, M::MatrixGroupElem{T}) where T = right_action(f, M.elm)

function right_action(R::MPolyRing{T}, p::PermGroupElem) where T
  n = nvars(R)
  @assert n == degree(parent(p))

  right_action_by_p = (f::MPolyRingElem{T}) -> on_indeterminates(f, p)

  return MapFromFunc(R, R, right_action_by_p)
end

right_action(f::MPolyRingElem, p::PermGroupElem) = right_action(parent(f), p)(f)

function is_invariant(f::MPolyRingElem, G::AbstractAlgebra.Group)
  return all(g -> f^g == f, gens(G))
end

function Base.in(f::MPolyRingElem, RG::FinGroupInvarRing)
  @req parent(f) === polynomial_ring(RG) "Polynomial rings do not coincide"
  return is_invariant(f, group(RG))
end

################################################################################
#
#  Reynolds operator
#
################################################################################

# Check whether d*f has coefficients which are within distance b of an integer
function _is_approx_integral(f::QQMPolyRingElem, d::ZZRingElem, b::QQFieldElem = QQFieldElem(1, 1))
  g = MPolyBuildCtx(parent(f))
  for (c, e) in zip(AbstractAlgebra.coefficients(f), AbstractAlgebra.exponent_vectors(f))
    cd = c*d
    if abs(round(cd) - cd) < b
      push_term!(g, round(cd)//d, e)
    else
      return false, finish(g)
    end
  end
  return true, finish(g)
end

function _is_approx_integral(f::AbstractAlgebra.Generic.MPoly{AbsSimpleNumFieldElem}, d::ZZRingElem, b::QQFieldElem = QQFieldElem(1, 1))
  g = MPolyBuildCtx(parent(f))
  K = coefficient_ring(parent(f))
  for (c, e) in zip(AbstractAlgebra.coefficients(f), AbstractAlgebra.exponent_vectors(f))
    cd = c*d
    roundcd = K(map(round, coefficients(cd)))
    if all(x -> abs(x) < b, coefficients(roundcd - cd))
      push_term!(g, roundcd//d, e)
    else
      return false, finish(g)
    end
  end
  return true, finish(g)
end

#function _round(f::QQMPolyRingElem, d::ZZRingElem)
#  g = MPolyBuildCtx(parent(f))
#  for (c, e) in zip(AbstractAlgebra.coefficients(f), AbstractAlgebra.exponent_vectors(f))
#    cd = round(c*d)
#    push_term!(g, cd//d, e)
#  end
#  return finish(g)
#end

# Return T in GL_n(QQ) such that TgT^-1 is in GL_n(ZZ) for all g in G.
function _make_integral(G::MatrixGroup{<:QQFieldElem})
  @assert is_finite(G)
  if all(g -> all(is_integral, matrix(g)), gens(G))
    return identity_matrix(QQ, degree(G))
  end

  # Build a full G-invariant ZZ-lattice
  # TODO: try to use not all of G (but the generators are unfortunately not enough)
  L = reduce(vcat, [ FakeFmpqMat(matrix(g)) for g in G ])
  T = hnf(L)
  # The HNF is "lowerleft"
  return view(QQMatrix(T), nrows(L) - ncols(L) + 1:nrows(L), 1:ncols(L))
end

# Theorem 2.1 in Plesken, Souvignier "Constructing rational representations of
# finite groups"
function reynolds_operator_approximate(RG::FinGroupInvarRing{FldT, GrpT, PolyRingElemT}, f::PolyRingElemT; attempts::Int = 100) where {FldT, GrpT, PolyRingElemT}
  @assert is_zero(characteristic(coefficient_ring(RG)))

  @assert is_homogeneous(f)

  t_precomp = 0.0
  t_h = 0.0
  t_round = 0.0
  t_check = 0.0
  t = 0.0

  K = coefficient_ring(RG)
  R = polynomial_ring(RG)
  G = group(RG)
  E = gens(G)
  t = time()
  filter!(!is_one, E)
  #T = _make_integral(G)
  T = identity_matrix(K, degree(G))
  invT = inv(T)
  # The action by the element e = \prod_{g\in E} (1//2(1 - g\in E)) in the
  # group algebra QQG on a polynomial
  # See the paper Section 3: acting by this element is supposed to lead to
  # "drastic improvements".
  function action_by_e(h::PolyRingElemT)
    for g in E
      # The paper puts a minus instead of a plus. I don't understand why this
      # should be true or work. (-g is not in G)
      h = 1//2*(h + right_action(h, T*g*inv(T)))
    end
    return h
  end

  #actions = [ right_action(R, T*g*invT) for g in E ]
  t_precomp = time() - t
  attempt = 0
  mon_cache = Dict{typeof(f), typeof(f)}()
  while attempt <= attempts
    attempt += 1
    if is_zero(attempt % 100)
      #@show attempt
    end

    t = time()
    # The commented out parts would be the action by 1/|E|*sum_{g in E} g
    #h = deepcopy(f) # action by 1
    f = action_by_e(f)
    #for (c, m) in zip(AbstractAlgebra.coefficients(f), AbstractAlgebra.monomials(f))
    #  mm = get!(mon_cache, m) do
    #    return sum( action(m) for action in actions )
    #  end
    #  h = addeq!(h, mm*c)
    #end
    t_h += time() - t
    #f = h*K(1//(length(E) + 1)) # + 1 for the action by 1
    t = time()
    fl, g = _is_approx_integral(forget_grading(f), order(ZZRingElem, G))
    t_round += time() - t
    if fl
      gg = polynomial_ring(RG)(g)
      t = time()
      #if all(a -> a(gg) == gg, actions)
      #aoei = all(a -> a(gg) == gg, actions)
      aoei = (right_action(gg, T) in RG)
      t_check += time() - t
      if aoei
        #@show attempt
        #@show t_precomp
        #@show t_h
        #@show t_round
        #@show t_check
        return right_action(gg, T)
      end
    end
  end
  error("Did not converge to an invariant in $attempts attempts")
end

function reynolds_operator(IR::FinGroupInvarRing{FldT, GrpT, PolyRingElemT}) where {FldT, GrpT, PolyRingElemT}
  @assert !is_modular(IR)

  if isdefined(IR, :reynolds_operator)
    return IR.reynolds_operator
  end

  actions = [ right_action(polynomial_ring(IR), g) for g in group(IR) ]
  function reynolds(f::PolyRingElemT)
    g = parent(f)()
    for action in actions
      g = addeq!(g, action(f))
    end
    return g*base_ring(f)(1//order(group(IR)))
  end

  IR.reynolds_operator = MapFromFunc(polynomial_ring(IR), polynomial_ring(IR), reynolds)
  return IR.reynolds_operator
end

@doc raw"""
     reynolds_operator(IR::FinGroupInvarRing{FldT, GrpT, T}, f::T) where {FldT, GrpT, T <: MPolyRingElem}

In the non-modular case, return the image of `f` under the Reynolds operator
projecting onto `IR`.

# Examples
```jldoctest
julia> K, a = cyclotomic_field(3, "a")
(Cyclotomic field of order 3, a)

julia> M1 = matrix(K, [0 0 1; 1 0 0; 0 1 0])
[0   0   1]
[1   0   0]
[0   1   0]

julia> M2 = matrix(K, [1 0 0; 0 a 0; 0 0 -a-1])
[1   0        0]
[0   a        0]
[0   0   -a - 1]

julia> G = matrix_group(M1, M2)
Matrix group of degree 3
  over cyclotomic field of order 3

julia> IR = invariant_ring(G)
Invariant ring
  of matrix group of degree 3 over K

julia> R = polynomial_ring(IR)
Multivariate polynomial ring in 3 variables over K graded by
  x[1] -> [1]
  x[2] -> [1]
  x[3] -> [1]

julia> x = gens(R)
3-element Vector{MPolyDecRingElem{AbsSimpleNumFieldElem, AbstractAlgebra.Generic.MPoly{AbsSimpleNumFieldElem}}}:
 x[1]
 x[2]
 x[3]

julia> f = x[1]^3
x[1]^3

julia> reynolds_operator(IR, f)
1//3*x[1]^3 + 1//3*x[2]^3 + 1//3*x[3]^3

julia> M = matrix(GF(3), [0 1 0; -1 0 0; 0 0 -1])
[0   1   0]
[2   0   0]
[0   0   2]

julia> G = matrix_group(M)
Matrix group of degree 3
  over prime field of characteristic 3

julia> IR = invariant_ring(G)
Invariant ring
  of matrix group of degree 3 over GF(3)

julia> R = polynomial_ring(IR)
Multivariate polynomial ring in 3 variables over GF(3) graded by
  x[1] -> [1]
  x[2] -> [1]
  x[3] -> [1]

julia> x = gens(R)
3-element Vector{MPolyDecRingElem{FqFieldElem, FqMPolyRingElem}}:
 x[1]
 x[2]
 x[3]

julia> f = x[1]^2
x[1]^2

julia> reynolds_operator(IR, f)
2*x[1]^2 + 2*x[2]^2

julia> f = x[1]^3
x[1]^3

julia> reynolds_operator(IR, f)
0
```
"""
function reynolds_operator(IR::FinGroupInvarRing{FldT, GrpT, T}, f::T) where {FldT, GrpT, T <: MPolyRingElem}
  @assert !is_modular(IR)
  @assert parent(f) === polynomial_ring(IR)

  if !isdefined(IR, :reynolds_operator)
    reynolds_operator(IR)
  end
  return IR.reynolds_operator(f)
end

function reynolds_operator(IR::FinGroupInvarRing, f::MPolyRingElem)
  @assert parent(f) === forget_grading(polynomial_ring(IR))
  return reynolds_operator(IR, polynomial_ring(IR)(f))
end

function reynolds_operator(IR::FinGroupInvarRing{FldT, GrpT, PolyRingElemT}, chi::GAPGroupClassFunction) where {FldT, GrpT, PolyRingElemT}
# I expect that this also works in the non-modular case, but haven't found a reference.
  # The only reference for this version of the reynolds operator appears to be [Gat96].
  @assert is_zero(characteristic(coefficient_ring(IR)))
  @assert is_irreducible(chi)

  K = coefficient_ring(IR)

  conjchi = conj(chi)

  actions_and_values = [ (right_action(polynomial_ring(IR), g), K(conjchi(g).data)) for g in group(IR) ]

  function reynolds(f::PolyRingElemT)
    g = parent(f)()
    for (action, val) in actions_and_values
      g = addeq!(g, action(f)*val)
    end
    return g*base_ring(f)(1//order(group(IR)))
  end

  return MapFromFunc(polynomial_ring(IR), polynomial_ring(IR), reynolds)
end

@doc raw"""
     reynolds_operator(IR::FinGroupInvarRing{FldT, GrpT, T}, f::T, chi::GAPGroupClassFunction)
       where {FldT, GrpT, T <: MPolyRingElem}

In the case of characteristic zero, return the image of `f` under the twisted
Reynolds operator projecting onto the isotypic component of the polynomial ring
with respect to `chi`, that is, the semi-invariants (or relative invariants)
with respect to `chi`, see [Sta79](@cite).
It is assumed that `chi` is an irreducible character.

In case `chi` is a linear character, the returned polynomial, say `h`, fulfils
`h^g = chi(g)h` for all `g` in `group(IR)` (possibly `h` is zero).

!!! note
    If `coefficient_ring(IR)` does not contain all character values of `chi`, an error is raised.

# Examples
```jldoctest
julia> K, a = cyclotomic_field(3, "a");

julia> M1 = matrix(K, [0 0 1; 1 0 0; 0 1 0]);

julia> M2 = matrix(K, [1 0 0; 0 a 0; 0 0 -a-1]);

julia> G = matrix_group(M1, M2);

julia> IR = invariant_ring(G);

julia> R = polynomial_ring(IR);

julia> x = gens(R);

julia> f = x[1]^3
x[1]^3

julia> reynolds_operator(IR, f, trivial_character(G))
1//3*x[1]^3 + 1//3*x[2]^3 + 1//3*x[3]^3

julia> S2 = symmetric_group(2);

julia> IR = invariant_ring(QQ, S2);

julia> R = polynomial_ring(IR);

julia> x = gens(R);

julia> F = abelian_closure(QQ)[1];

julia> chi = Oscar.class_function(S2, [ F(sign(representative(c))) for c in conjugacy_classes(S2) ])
class_function(character table of S2, QQAbElem{AbsSimpleNumFieldElem}[1, -1])

julia> reynolds_operator(IR, x[1], chi)
1//2*x[1] - 1//2*x[2]
```
"""
function reynolds_operator(IR::FinGroupInvarRing{FldT, GrpT, T}, f::T, chi::GAPGroupClassFunction) where {FldT, GrpT, T <: MPolyRingElem}
  return reynolds_operator(IR, chi)(f)
end

function reynolds_operator(IR::FinGroupInvarRing, f::MPolyRingElem, chi::GAPGroupClassFunction)
  @assert parent(f) === forget_grading(polynomial_ring(IR))
  return reynolds_operator(IR, polynomial_ring(IR)(f), chi)
end

################################################################################
#
#  Bases
#
################################################################################

@doc raw"""
     basis(IR::FinGroupInvarRing, d::Int, algorithm::Symbol = :default)

Given an invariant ring `IR` and an integer `d`, return a basis for the invariants in degree `d`.

The optional argument `algorithm` specifies the algorithm to be used.
If `algorithm = :reynolds`, the Reynolds operator is utilized (this method is only available in the non-modular case).
Setting `algorithm = :linear_algebra` means that plain linear algebra is used.
The default option `algorithm = :default` asks to select the heuristically best algorithm.

See also [`iterate_basis`](@ref).

# Examples
```jldoctest
julia> K, a = cyclotomic_field(3, "a")
(Cyclotomic field of order 3, a)

julia> M1 = matrix(K, [0 0 1; 1 0 0; 0 1 0])
[0   0   1]
[1   0   0]
[0   1   0]

julia> M2 = matrix(K, [1 0 0; 0 a 0; 0 0 -a-1])
[1   0        0]
[0   a        0]
[0   0   -a - 1]

julia> G = matrix_group(M1, M2)
Matrix group of degree 3
  over cyclotomic field of order 3

julia> IR = invariant_ring(G)
Invariant ring
  of matrix group of degree 3 over K

julia> basis(IR, 6)
4-element Vector{MPolyDecRingElem{AbsSimpleNumFieldElem, AbstractAlgebra.Generic.MPoly{AbsSimpleNumFieldElem}}}:
 x[1]^2*x[2]^2*x[3]^2
 x[1]^4*x[2]*x[3] + x[1]*x[2]^4*x[3] + x[1]*x[2]*x[3]^4
 x[1]^3*x[2]^3 + x[1]^3*x[3]^3 + x[2]^3*x[3]^3
 x[1]^6 + x[2]^6 + x[3]^6

julia> M = matrix(GF(3), [0 1 0; -1 0 0; 0 0 -1])
[0   1   0]
[2   0   0]
[0   0   2]

julia> G = matrix_group(M)
Matrix group of degree 3
  over prime field of characteristic 3

julia> IR = invariant_ring(G)
Invariant ring
  of matrix group of degree 3 over GF(3)

julia> basis(IR, 2)
2-element Vector{MPolyDecRingElem{FqFieldElem, FqMPolyRingElem}}:
 x[1]^2 + x[2]^2
 x[3]^2

julia> basis(IR, 3)
2-element Vector{MPolyDecRingElem{FqFieldElem, FqMPolyRingElem}}:
 x[1]*x[2]*x[3]
 x[1]^2*x[3] + 2*x[2]^2*x[3]
```
"""
basis(IR::FinGroupInvarRing, d::Int, algorithm::Symbol = :default) = collect(iterate_basis(IR, d, algorithm))

@doc raw"""
    basis(IR::FinGroupInvarRing, d::Int, chi::GAPGroupClassFunction)

Given an invariant ring `IR`, an integer `d` and an irreducible character `chi`,
return a basis for the semi-invariants (or relative invariants) in degree `d`
with respect to `chi`.

This function is only implemented in the case of characteristic zero.

!!! note
    If `coefficient_ring(IR)` does not contain all character values of `chi`, an error is raised.

See also [`iterate_basis`](@ref).

# Examples
```
julia> K, a = cyclotomic_field(3, "a");

julia> M1 = matrix(K, [0 0 1; 1 0 0; 0 1 0]);

julia> M2 = matrix(K, [1 0 0; 0 a 0; 0 0 -a-1]);

julia> G = matrix_group(M1, M2);

julia> IR = invariant_ring(G);

julia> basis(IR, 6, trivial_character(G))
4-element Vector{MPolyDecRingElem{AbsSimpleNumFieldElem, AbstractAlgebra.Generic.MPoly{AbsSimpleNumFieldElem}}}:
 x[1]^6 + x[2]^6 + x[3]^6
 x[1]^4*x[2]*x[3] + x[1]*x[2]^4*x[3] + x[1]*x[2]*x[3]^4
 x[1]^3*x[2]^3 + x[1]^3*x[3]^3 + x[2]^3*x[3]^3
 x[1]^2*x[2]^2*x[3]^2

julia> S2 = symmetric_group(2);

julia> R = invariant_ring(QQ, S2);

julia> F = abelian_closure(QQ)[1];

julia> chi = Oscar.class_function(S2, [ F(sign(representative(c))) for c in conjugacy_classes(S2) ])
class_function(character table of group Sym( [ 1 .. 2 ] ), QQAbElem{AbsSimpleNumFieldElem}[1, -1])

julia> basis(R, 3, chi)
2-element Vector{MPolyDecRingElem{QQFieldElem, QQMPolyRingElem}}:
 x[1]^3 - x[2]^3
 x[1]^2*x[2] - x[1]*x[2]^2

```
"""
basis(IR::FinGroupInvarRing, d::Int, chi::GAPGroupClassFunction) = collect(iterate_basis(IR, d, chi))

################################################################################
#
#  Primary invariants
#
################################################################################

# See primary_invariants.jl

################################################################################
#
#  Secondary invariants
#
################################################################################

# See secondary_invariants.jl

################################################################################
#
#  Molien series
#
################################################################################

function _molien_series_char0(S::PolyRing, I::FinGroupInvarRing)
  G = group(I)
  n = degree(G)
  K = coefficient_ring(I)
  Kt, _ = polynomial_ring(K, "t", cached = false)
  C = conjugacy_classes(G)
  res = zero(fraction_field(Kt))
  for c in C
    g = representative(c)
    if g isa MatrixGroupElem
      f = charpoly(Kt, g.elm)
    elseif g isa PermGroupElem
      f = charpoly(Kt, permutation_matrix(K, g))
    else
      error("problem to compute the char. pol. of $g")
    end
    res = res + length(c)::ZZRingElem * 1//reverse(f)
  end
  res = divexact(res, order(ZZRingElem, G))
  num = change_coefficient_ring(coefficient_ring(S),
                                numerator(res), parent = S)
  den = change_coefficient_ring(coefficient_ring(S),
                                denominator(res), parent = S)
  return num//den
end

function _molien_series_nonmodular_via_gap(S::PolyRing, I::FinGroupInvarRing, chi::Union{GAPGroupClassFunction, Nothing} = nothing)
  @assert !is_modular(I)
  G = group(I)
  @assert G isa MatrixGroup || G isa PermGroup
  t = GAP.Globals.CharacterTable(G.X)
  if G isa MatrixGroup
    if is_zero(characteristic(coefficient_ring(I)))
      psi = natural_character(G).values
    else
      psi = [GAP.Globals.BrauerCharacterValue(GAPWrap.Representative(c))
             for c in GAPWrap.ConjugacyClasses(t)]
    end
  else
    deg = GAP.Obj(degree(G))
    psi = [deg - GAP.Globals.NrMovedPoints(GAPWrap.Representative(c))
           for c in GAPWrap.ConjugacyClasses(t)]
  end
  if chi === nothing
    info = GAP.Globals.MolienSeriesInfo(GAP.Globals.MolienSeries(t,
                                                                 GAP.GapObj(psi)))
  else
    info = GAP.Globals.MolienSeriesInfo(GAP.Globals.MolienSeries(t,
                                                                 GAP.GapObj(psi), chi.values))
  end
  num = S(Vector{ZZRingElem}(GAP.Globals.CoefficientsOfUnivariatePolynomial(info.numer))::Vector{ZZRingElem})
  den = S(Vector{ZZRingElem}(GAP.Globals.CoefficientsOfUnivariatePolynomial(info.denom))::Vector{ZZRingElem})
  return num//den
end

@doc raw"""
    molien_series([S::PolyRing], I::FinGroupInvarRing, [chi::GAPGroupClassFunction])

In the non-modular case, return the Molien series of `I` as a rational function.

If a univariate polynomial ring with rational coefficients is specified by the
optional argument `S::PolyRing`, then return the Molien series as an element
of the fraction field of that ring.

If a character `chi` is specified, the series relative to `chi` is returned.
This is the Molien series of the module of semi-invariants (or relative invariants)
with respect to `chi`, see [Sta79](@cite).

# Examples
```jldoctest
julia> K, a = cyclotomic_field(3, "a");

julia> M1 = matrix(K, [0 0 1; 1 0 0; 0 1 0]);

julia> M2 = matrix(K, [1 0 0; 0 a 0; 0 0 -a-1]);

julia> G = matrix_group(M1, M2);

julia> IR = invariant_ring(G);

julia> MS = molien_series(IR)
(-t^6 + t^3 - 1)//(t^9 - 3*t^6 + 3*t^3 - 1)

julia> parent(MS)
Fraction field
  of univariate polynomial ring in t over QQ

julia> expand(MS, 10)
1 + 2*t^3 + 4*t^6 + 7*t^9 + O(t^11)
```
```jldoctest
julia> S2 = symmetric_group(2);

julia> IR = invariant_ring(QQ, S2);

julia> F = abelian_closure(QQ)[1];

julia> chi = Oscar.class_function(S2, [ F(sign(representative(c))) for c in conjugacy_classes(S2) ])
class_function(character table of S2, QQAbElem{AbsSimpleNumFieldElem}[1, -1])

julia> molien_series(IR)
1//(t^3 - t^2 - t + 1)

julia> molien_series(IR, chi)
t//(t^3 - t^2 - t + 1)
```
"""
function molien_series(S::PolyRing, I::FinGroupInvarRing, chi::Union{GAPGroupClassFunction, Nothing} = nothing)
  if isdefined(I, :molien_series) && chi === nothing
    if parent(I.molien_series) === S
      return I.molien_series
    end
    num = change_coefficient_ring(coefficient_ring(S), numerator(I.molien_series), parent = S)
    den = change_coefficient_ring(coefficient_ring(S), denominator(I.molien_series), parent = S)
    return num//den
  end

  if characteristic(coefficient_ring(I)) == 0 && chi === nothing
    return _molien_series_char0(S, I)
  else
    if !is_modular(I)
      return _molien_series_nonmodular_via_gap(S, I, chi)
    else
      throw(Hecke.NotImplemented())
    end
  end
end

function molien_series(I::FinGroupInvarRing, chi::Union{GAPGroupClassFunction, Nothing} = nothing)
  if chi === nothing
    if !isdefined(I, :molien_series)
      S, t = polynomial_ring(QQ, "t", cached = false)
      I.molien_series = molien_series(S, I)
    end
    return I.molien_series
  else
    S, t = polynomial_ring(QQ, "t", cached = false)
    return molien_series(S, I, chi)
  end
end

# There are some situations where one needs to know whether one can ask for the
# Molien series without throwing an error.
# And maybe some day we can also compute Molien series in some modular cases.
is_molien_series_implemented(I::FinGroupInvarRing) = !is_modular(I)

################################################################################
#
#  Fundamental invariants
#
################################################################################

# See fundamental_invariants.jl

################################################################################
#
#  Presentation as affine algebra
#
################################################################################

# See affine_algebra.jl
