###############################################################################
#
#   Lie algebras
#
###############################################################################

const lie_algebra_serialization_attributes = [
  :is_abelian, :is_nilpotent, :is_perfect, :is_semisimple, :is_simple, :is_solvable
]

@register_serialization_type AbstractLieAlgebra uses_id lie_algebra_serialization_attributes

function save_object(s::SerializerState, L::AbstractLieAlgebra)
  save_data_dict(s) do
    save_typed_object(s, coefficient_ring(L), :base_ring)
    save_object(s, _struct_consts(L), :struct_consts)
    save_object(s, symbols(L), :symbols)
    save_root_system_data(s, L)
    save_attrs(s, L)
  end
end

function load_object(s::DeserializerState, ::Type{<:AbstractLieAlgebra})
  R = load_typed_object(s, :base_ring)
  struct_consts = load_object(s, Matrix, (sparse_row_type(R), R), :struct_consts)
  symbs = load_object(s, Vector, Symbol, :symbols)
  L = lie_algebra(R, struct_consts, symbs; check=false)
  load_root_system_data(s, L)
  load_attrs(s, L)
  return L
end

@register_serialization_type LinearLieAlgebra uses_id [
  lie_algebra_serialization_attributes;
  [:type, :form]
]

function save_object(s::SerializerState, L::LinearLieAlgebra)
  save_data_dict(s) do
    save_typed_object(s, coefficient_ring(L), :base_ring)
    save_object(s, L.n, :n)
    save_object(s, matrix_repr_basis(L), :basis)
    save_object(s, symbols(L), :symbols)
    save_root_system_data(s, L)
    save_attrs(s, L)
  end
end

function load_object(s::DeserializerState, ::Type{<:LinearLieAlgebra})
  R = load_typed_object(s, :base_ring)
  n = load_object(s, Int, :n)
  basis = load_object(s, Vector, (dense_matrix_type(R), matrix_space(R, n, n)), :basis)
  symbs = load_object(s, Vector, Symbol, :symbols)
  L = lie_algebra(R, n, basis, symbs; check=false)
  load_root_system_data(s, L)
  load_attrs(s, L)
  return L
end

@register_serialization_type DirectSumLieAlgebra uses_id lie_algebra_serialization_attributes

function save_object(s::SerializerState, L::DirectSumLieAlgebra)
  save_data_dict(s) do
    save_typed_object(s, coefficient_ring(L), :base_ring)
    save_data_array(s, :summands) do
      for summand in L.summands
        ref = save_as_ref(s, summand)
        save_object(s, ref)
      end
    end
    save_root_system_data(s, L)
    save_attrs(s, L)
  end
end

function load_object(s::DeserializerState, ::Type{<:DirectSumLieAlgebra})
  R = load_typed_object(s, :base_ring)
  summands = Vector{LieAlgebra{elem_type(R)}}(
    load_array_node(s, :summands) do _
      load_ref(s)
    end,
  )

  L = direct_sum(R, summands)
  load_root_system_data(s, L)
  load_attrs(s, L)
  return L
end

function save_root_system_data(s::SerializerState, L::LieAlgebra)
  if has_root_system(L)
    save_typed_object(s, root_system(L), :root_system)
    save_object(s, chevalley_basis(L), :chevalley_basis)
  end
end

function load_root_system_data(s::DeserializerState, L::LieAlgebra)
  if haskey(s, :root_system)
    rs = load_typed_object(s, :root_system)
    chev = NTuple{3,Vector{elem_type(L)}}(
      load_object(
        s, Tuple, [(Vector, (AbstractLieAlgebraElem, L)) for _ in 1:3], :chevalley_basis
      ),
    ) # coercion needed due to https://github.com/oscar-system/Oscar.jl/issues/3983
    set_root_system_and_chevalley_basis!(L, rs, chev)
  end
end

@register_serialization_type AbstractLieAlgebraElem uses_params
@register_serialization_type LinearLieAlgebraElem uses_params
@register_serialization_type DirectSumLieAlgebraElem uses_params

function save_object(s::SerializerState, x::LieAlgebraElem)
  save_object(s, coefficients(x))
end

function load_object(s::DeserializerState, ::Type{<:LieAlgebraElem}, L::LieAlgebra)
  return L(load_object(s, Vector, coefficient_ring(L)))
end

function save_type_params(s::SerializerState, x::LieAlgebraElem)
  save_data_dict(s) do
    save_object(s, encode_type(typeof(x)), :name)
    parent_x = parent(x)
    parent_ref = save_as_ref(s, parent_x)
    save_object(s, parent_ref, :params)
  end
end

function load_type_params(s::DeserializerState, ::Type{<:LieAlgebraElem})
  return load_typed_object(s)
end

###############################################################################
#
#   Lie algebra modules
#
###############################################################################

@register_serialization_type LieAlgebraModule uses_id

function save_object(s::SerializerState, V::LieAlgebraModule)
  save_data_dict(s) do
    save_typed_object(s, base_lie_algebra(V), :lie_algebra)
    save_object(s, dim(V), :dim)
    save_object(s, transformation_matrices(V), :transformation_matrices)
    save_object(s, symbols(V), :symbols)
    save_construction_data(s, V)
    save_attrs(s, V)
  end
end

function load_object(s::DeserializerState, T::Type{<:LieAlgebraModule})
  L = load_typed_object(s, :lie_algebra)
  R = coefficient_ring(L)
  dim = load_object(s, Int, :dim)
  transformation_matrices = load_object(
    s, Vector, (dense_matrix_type(R), matrix_space(R, dim, dim)), :transformation_matrices
  )
  symbs = load_object(s, Vector, Symbol, :symbols)
  V = load_construction_data(s, T)
  if isnothing(V)
    V = abstract_module(L, dim, transformation_matrices, symbs; check=false)
  end
  load_attrs(s, V)
  return V
end

function save_construction_data(s::SerializerState, V::LieAlgebraModule)
  with_attrs(s) || return nothing # attribute saving disabled
  save_data_dict(s, :construction_data) do
    if _is_standard_module(V)
      save_object(s, save_as_ref(s, base_lie_algebra(V)), :is_standard_module)
    elseif ((fl, W) = _is_dual(V); fl)
      save_object(s, save_as_ref(s, W), :is_dual)
    elseif ((fl, Vs) = _is_direct_sum(V); fl)
      save_object(s, Vs, :is_direct_sum)
    elseif ((fl, Vs) = _is_tensor_product(V); fl)
      save_object(s, Vs, :is_tensor_product)
    elseif ((fl, W, k) = _is_exterior_power(V); fl)
      save_object(s, (W, k), :is_exterior_power)
    elseif ((fl, W, k) = _is_symmetric_power(V); fl)
      save_object(s, (W, k), :is_symmetric_power)
    elseif ((fl, W, k) = _is_tensor_power(V); fl)
      save_object(s, (W, k), :is_tensor_power)
    end
  end
end

function load_construction_data(s::DeserializerState, T::Type{<:LieAlgebraModule})
  V = nothing
  with_attrs(s) && haskey(s, :construction_data) &&
    load_node(s, :construction_data) do _
      if haskey(s, :is_standard_module)
        V = standard_module(load_typed_object(s, :is_standard_module))
      elseif haskey(s, :is_dual)
        W = load_typed_object(s, :is_dual)
        V = dual(W)
      elseif haskey(s, :is_direct_sum)
        Vs = load_object(s, Vector, LieAlgebraModule, :is_direct_sum)
        V = direct_sum(Vs...)
      elseif haskey(s, :is_tensor_product)
        Vs = load_object(s, Vector, LieAlgebraModule, :is_tensor_product)
        V = tensor_product(Vs...)
      elseif haskey(s, :is_exterior_power)
        W, k = load_object(s, Tuple, [LieAlgebraModule, Int], :is_exterior_power)
        V = exterior_power(W, k)[1]
      elseif haskey(s, :is_symmetric_power)
        W, k = load_object(s, Tuple, [LieAlgebraModule, Int], :is_symmetric_power)
        V = symmetric_power(W, k)[1]
      elseif haskey(s, :is_tensor_power)
        W, k = load_object(s, Tuple, [LieAlgebraModule, Int], :is_tensor_power)
        V = tensor_power(W, k)[1]
      end
    end
  return V::Union{T,Nothing}
end

@register_serialization_type LieAlgebraModuleElem uses_params

function save_object(s::SerializerState, x::LieAlgebraModuleElem)
  save_object(s, coefficients(x))
end

function load_object(
  s::DeserializerState, ::Type{<:LieAlgebraModuleElem}, V::LieAlgebraModule
)
  return V(load_object(s, Vector, coefficient_ring(V)))
end

function save_type_params(s::SerializerState, v::LieAlgebraModuleElem)
  save_data_dict(s) do
    save_object(s, encode_type(typeof(v)), :name)
    parent_x = parent(v)
    parent_ref = save_as_ref(s, parent_x)
    save_object(s, parent_ref, :params)
  end
end

function load_type_params(s::DeserializerState, ::Type{<:LieAlgebraModuleElem})
  return load_typed_object(s)
end
