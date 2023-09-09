module ReactiveTools

using Stipple
using MacroTools
using MacroTools: postwalk
using OrderedCollections
import Genie
import Stipple: deletemode!, parse_expression!, init_storage

# definition of variables
export @readonly, @private, @in, @out, @jsfn, @readonly!, @private!, @in!, @out!, @jsfn!, @mixin

#definition of handlers/events
export @onchange, @onbutton, @event, @notify

# deletion
export @clear, @clear_vars, @clear_handlers

# app handling
export @page, @init, @handlers, @app, @appname

# js functions on the front-end (see Vue.js docs)
export @methods, @watch, @computed, @client_data, @add_client_data

export @before_create, @created, @before_mount, @mounted, @before_update, @updated, @activated, @deactivated, @before_destroy, @destroyed, @error_captured


export DEFAULT_LAYOUT, Page

export @onchangeany # deprecated

const REACTIVE_STORAGE = LittleDict{Module,LittleDict{Symbol,Expr}}()
const HANDLERS = LittleDict{Module,Vector{Expr}}()
const TYPES = LittleDict{Module,Union{<:DataType,Nothing}}()

function DEFAULT_LAYOUT(; title::String = "Genie App", meta::Dict{<:AbstractString,<:AbstractString} = Dict("og:title" => "Genie App"))
  tags = Genie.Renderers.Html.for_each(x -> """<meta name="$(x.first)" content="$(x.second)">\n    """, meta)
  """
<!DOCTYPE html>
<html>
  <head>
    <meta charset="utf-8">
    $tags
    <% Stipple.sesstoken() %>
    <title>$title</title>
    <% if isfile(joinpath(Genie.config.server_document_root, "css", "genieapp.css")) %>
    <link rel='stylesheet' href='$(Genie.Configuration.basepath())/css/genieapp.css'>
    <% else %>
    <% end %>
    <% if isfile(joinpath(Genie.config.server_document_root, "css", "autogenerated.css")) %>
    <link rel='stylesheet' href='$(Genie.Configuration.basepath())/css/autogenerated.css'>
    <% else %>
    <% end %>
    <style>
      ._genie_logo {
        background:url('https://genieframework.com/logos/genie/logo-simple-with-padding.svg') no-repeat;background-size:40px;
        padding-top:22px;padding-right:10px;color:transparent;font-size:9pt;
      }
      ._genie .row .col-12 { width:50%;margin:auto; }
    </style>
  </head>
  <body>
    <div class='container'>
      <div class='row'>
        <div class='col-12'>
          <% page(model, partial = true, v__cloak = true, [@yield], @iif(:isready)) %>
        </div>
      </div>
    </div>
    <% if isfile(joinpath(Genie.config.server_document_root, "js", "genieapp.js")) %>
    <script src='$(Genie.Configuration.basepath())/js/genieapp.js'></script>
    <% else %>
    <% end %>
    <footer class='_genie container'>
      <div class='row'>
        <div class='col-12'>
          <p class='text-muted credit' style='text-align:center;color:#8d99ae;'>Built with
            <a href='https://genieframework.com' target='_blank' class='_genie_logo' ref='nofollow'>Genie</a>
          </p>
        </div>
      </div>
    </footer>
  </body>
</html>
"""
end

function model_typename(m::Module)
  isdefined(m, :__typename__) ? m.__typename__[] : "$(m)_ReactiveModel"
end

macro appname(expr)
  expr isa Symbol || (expr = Symbol(@eval(__module__, $expr)))
  clear_type(__module__)
  ex = quote end
  if isdefined(__module__, expr)
    push!(ex.args, :(Stipple.ReactiveTools.delete_handlers_fn($__module__)))
    push!(ex.args, :(Stipple.ReactiveTools.delete_events($expr)))
  end
  if isdefined(__module__, :__typename__) && __module__.__typename__ isa Ref{String}
    push!(ex.args, :(__typename__[] = $(string(expr))))
  else
    push!(ex.args, :(const __typename__ = Ref{String}($(string(expr)))))
    push!(ex.args, :(__typename__[]))
  end
  :($ex) |> esc
end

macro appname()
  # reset appname to default
  appname = "$(__module__)_ReactiveModel"
  :(isdefined($__module__, :__typename__) ? @appname($appname) : $appname) |> esc
end

function Stipple.init_storage(m::Module)
  (m == @__MODULE__) && return nothing
  haskey(REACTIVE_STORAGE, m) || (REACTIVE_STORAGE[m] = Stipple.init_storage())
  haskey(TYPES, m) || (TYPES[m] = nothing)
  REACTIVE_STORAGE[m]
end

function Stipple.setmode!(expr::Expr, mode::Int, fieldnames::Symbol...)
  fieldname in [Stipple.CHANNELFIELDNAME, :modes__] && return
  expr.args[2] isa Expr && expr.args[2].args[1] == :(Stipple._deepcopy) && (expr.args[2] = expr.args[2].args[2])

  d = if expr.args[2] isa LittleDict
    copy(expr.args[2])
  elseif expr.args[2] isa QuoteNode
    expr.args[2].value
  else # isa Expr generating a LittleDict (hopefully ...)
    expr.args[2].args[1].args[1] == :(Stipple.LittleDict) || expr.args[2].args[1].args[1] == :(LittleDict) || error("Unexpected error while setting access properties of app variables")

    d = LittleDict{Symbol, Int}()
    for p in expr.args[2].args[2:end]
      push!(d, p.args[2].value => p.args[3])
    end
    d
  end
  for fieldname in fieldnames
    mode == PUBLIC ? delete!(d, fieldname) : d[fieldname] = mode
  end
  expr.args[2] = QuoteNode(d)
end

#===#

function clear_type(m::Module)
  TYPES[m] = nothing
end

function delete_bindings!(m::Module)
  clear_type(m)
  delete!(REACTIVE_STORAGE, m)
  nothing
end

function bindings(m)
  init_storage(m)
  REACTIVE_STORAGE[m]
end

function delete_handlers_fn(m::Module)
  if isdefined(m, :__GF_AUTO_HANDLERS__)
    Base.delete_method.(methods(m.__GF_AUTO_HANDLERS__))
  end
end

function delete_events(m::Module)
  haskey(TYPES, m) && TYPES[m] isa DataType && delete_events(TYPES[m])
end

function delete_events(::Type{M}) where M
  # delete event functions
  mm = methods(Base.notify)
  for m in mm
    hasproperty(m.sig, :parameters) || continue
    T =  m.sig.parameters[2]
    if T <: M || T == Type{M} || T == Type{<:M}
      Base.delete_method(m)
    end
  end
  nothing
 end

function delete_handlers!(m::Module)
  delete!(HANDLERS, m)
  delete_handlers_fn(m)
  delete_events(m)
  nothing
end

#===#

"""
```julia
@clear
```

Deletes all reactive variables and code in a model.
"""
macro clear()
  delete_bindings!(__module__)
  delete_handlers!(__module__)
end

macro clear(args...)
  haskey(REACTIVE_STORAGE, __module__) || return
  for arg in args
    arg in [Stipple.CHANNELFIELDNAME, :modes__] && continue
    delete!(REACTIVE_STORAGE[__module__], arg)
  end
  deletemode!(REACTIVE_STORAGE[__module__][:modes__], args...)

  update_storage(__module__)

  REACTIVE_STORAGE[__module__]
end

"""
```julia
@clear_vars
```

Deletes all reactive variables in a model.
"""
macro clear_vars()
  delete_bindings!(__module__)
end

"""
```julia
@clear_handlers
```

Deletes all reactive code handlers in a model.
"""
macro clear_handlers()
  delete_handlers!(__module__)
end

import Stipple.@type
macro type()
  Stipple.init_storage(__module__)
  type = if TYPES[__module__] !== nothing
    TYPES[__module__]
  else
    modelname = Symbol(model_typename(__module__))
    storage = REACTIVE_STORAGE[__module__]
    TYPES[__module__] = @eval(__module__, Stipple.@type($modelname, $storage))
  end

  esc(:($type))
end

import Stipple.@clear_cache
macro clear_cache()
  :(Stipple.clear_cache(Stipple.@type)) |> esc
end

import Stipple.@clear_route
macro clear_route()
  :(Stipple.clear_route(Stipple.@type)) |> esc
end

function update_storage(m::Module)
  clear_type(m)
  # isempty(Stipple.Pages._pages) && return
  # instance = @eval m Stipple.@type()
  # for p in Stipple.Pages._pages
  #   p.context == m && (p.model = instance)
  # end
end

import Stipple: @vars, @add_vars

macro vars(expr)
  init_storage(__module__)

  REACTIVE_STORAGE[__module__] = @eval(__module__, Stipple.@var_storage($expr))

  update_storage(__module__)
  REACTIVE_STORAGE[__module__]
end

macro add_vars(expr)
  init_storage(__module__)
  REACTIVE_STORAGE[__module__] = Stipple.merge_storage(REACTIVE_STORAGE[__module__], @eval(__module__, Stipple.@var_storage($expr)))

  update_storage(__module__)
end

macro model()
  esc(quote
    Stipple.@type() |> Base.invokelatest
  end)
end

"""
```julia
@app(expr)
```

Sets up and enables the reactive variables and code provided in the expression `expr`.

**Usage**

The code block passed to @app implements the app's logic, handling the states of the UI components and the code that is executed when these states are altered.

```julia
@app begin
   # reactive variables
   @in N = 0
   @out result = 0
   # reactive code to be executed when N changes
   @onchange N begin
     result = 10*N
   end
end
```
"""
macro app(expr)
  delete_bindings!(__module__)
  delete_handlers!(__module__)

  init_handlers(__module__)
  init_storage(__module__)

  quote
    $expr

    @handlers
  end |> esc
end

#===#

function binding(expr::Symbol, m::Module, @nospecialize(mode::Any = nothing); source = nothing, reactive = true)
  binding(:($expr = $expr), m, mode; source, reactive)
end

function binding(expr::Expr, m::Module, @nospecialize(mode::Any = nothing); source = nothing, reactive = true)
  (m == @__MODULE__) && return nothing

  intmode = mode isa Integer ? Int(mode) : @eval Stipple.$mode
  init_storage(m)

  var, field_expr = parse_expression!(expr, reactive ? mode : nothing, source, m)
  REACTIVE_STORAGE[m][var] = field_expr

  reactive || setmode!(REACTIVE_STORAGE[m][:modes__], intmode, var)
  reactive && setmode!(REACTIVE_STORAGE[m][:modes__], PUBLIC, var)

  # remove cached type and instance, update pages
  update_storage(m)
end

function binding(expr::Expr, storage::LittleDict{Symbol, Expr}, @nospecialize(mode::Any = nothing); source = nothing, reactive = true, m::Module)
  intmode = mode isa Integer ? Int(mode) : @eval Stipple.$mode

  var, field_expr = parse_expression!(expr, reactive ? mode : nothing, source, m)
  storage[var] = field_expr

  reactive || setmode!(storage[:modes__], intmode, var)
  reactive && setmode!(storage[:modes__], PUBLIC, var)

  storage
end

# this macro needs to run in a macro where `expr`is already defined
macro report_val()
  quote
    val = expr isa Symbol ? expr : expr.args[2]
    issymbol = val isa Symbol
    :(if $issymbol
      if isdefined(@__MODULE__, $(QuoteNode(val)))
        $val
      else
        @info(string("Warning: Variable '", $(QuoteNode(val)), "' not yet defined"))
      end
    else
      Stipple.Observables.to_value($val)
    end) |> esc
  end |> esc
end

# this macro needs to run in a macro where `expr`is already defined
macro define_var()
  quote
    ( expr isa Symbol || expr.head !== :(=) ) && return expr
    var = expr.args[1] isa Symbol ? expr.args[1] : expr.args[1].args[1]
    new_expr = :($var = Stipple.Observables.to_value($(expr.args[2])))
    esc(:($new_expr))
  end |> esc
end

# works with
# @in a = 2
# @in a::Vector = [1, 2, 3]
# @in a::Vector{Int} = [1, 2, 3]

# the @in, @out and @private macros below are defined so a docstring can be attached
# the actual macro definition is done in the for loop further down
"""
```julia
@in(expr)
```

Declares a reactive variable that is public and can be written to from the UI.

**Usage**
```julia
@app begin
    @in N = 0
end
```
"""
macro in end

"""
```julia
@out(expr)
```

Declares a reactive variable that is public and readonly.

**Usage**
```julia
@app begin
    @out N = 0
end
```
"""
macro out end

"""
```julia
@private(expr)
```

Declares a non-reactive variable that cannot be accessed by UI code.

**Usage**
```julia
@app begin
    @private N = 0
end
```
"""
macro private end

for (fn, mode) in [(:in, :PUBLIC), (:out, :READONLY), (:jsnfn, :JSFUNCTION), (:private, :PRIVATE)]
  fn! = Symbol(fn, "!")
  Core.eval(@__MODULE__, quote

    macro $fn!(expr)
      binding(expr isa Symbol ? expr : copy(expr), __module__, $mode; source = __source__)
      esc(:($expr))
    end

    macro $fn!(flag, expr)
      flag != :non_reactive && return esc(:(ReactiveTools.$fn!($flag, _, $expr)))
      binding(expr isa Symbol ? expr : copy(expr), __module__, $mode; source = __source__, reactive = false)
      esc(:($expr))
    end

    macro $fn(location, flag, expr)
      reactive = flag != :non_reactive
      ex = [expr isa Symbol ? expr : copy(expr)]
      loc = location isa Symbol ? QuoteNode(location) : location

      quote
        local location = isdefined($__module__, $loc) ? eval($loc) : $loc
        local storage = location isa DataType ? Stipple.model_to_storage(location) : location isa LittleDict ? location : Stipple.init_storage()

        Stipple.ReactiveTools.binding($ex[1], storage, $$mode; source = $__source__, reactive = $reactive, m = $__module__)
        location isa DataType || location isa Symbol ? eval(:(Stipple.@type($$loc, $storage))) : location
      end |> esc
    end

    macro $fn(expr)
      binding(expr isa Symbol ? expr : copy(expr), __module__, $mode; source = __source__)
      @report_val()
    end

    macro $fn(flag, expr)
      flag != :non_reactive && return esc(:(ReactiveTools.@fn($flag, _, $expr)))
      binding(expr isa Symbol ? expr : copy(expr), __module__, $mode; source = __source__, reactive = false)
      @report_val()
    end
  end)
end

macro mixin(expr, prefix = "", postfix = "")
  # if prefix is not a String then call the @mixin version for generic model types
  prefix isa String || return quote
    @mixin $expr $prefix $postfix ""
  end

  storage = init_storage(__module__)

  Stipple.ReactiveTools.update_storage(__module__)
  Core.eval(__module__, quote
    Stipple.ReactiveTools.@mixin $storage $expr $prefix $postfix
  end)
  quote end
end

macro mixin(location, expr, prefix, postfix)
  if hasproperty(expr, :head) && expr.head == :(::)
    prefix = string(expr.args[1])
    expr = expr.args[2]
  end
  loc = location isa Symbol ? QuoteNode(location) : location

  x = Core.eval(__module__, expr)
  quote
    local location = $loc isa Symbol && isdefined($__module__, $loc) ? $__module__.$(loc isa QuoteNode ? loc.value : loc) : $loc
    local storage = location isa DataType ? Stipple.model_to_storage(location) : location isa LittleDict ? location : Stipple.init_storage()
    M = $x isa DataType ? $x : typeof($x) # really needed?
    local mixin_storage = Stipple.model_to_storage(M, $(QuoteNode(prefix)), $postfix)

    merge!(storage, Stipple.merge_storage(storage, mixin_storage))
    location isa DataType || location isa Symbol ? eval(:(Stipple.@type($$loc, $storage))) : location
    mixin_storage
  end |> esc
end

#===#

function init_handlers(m::Module)
  get!(Vector{Expr}, HANDLERS, m)
end

"""
        @init(kwargs...)

Create a new app with the following kwargs supported:
- `debounce::Int = JS_DEBOUNCE_TIME`
- `transport::Module = Genie.WebChannels`
- `core_theme::Bool = true`

### Example
```
@app begin
  @in n = 10
  @out s = "Hello"
end

model = @init(debounce = 50)
```
------------

        @init(App, kwargs...)

Create a new app of type `App` with the same kwargs as above

### Example

```
@app MyApp begin
  @in n = 10
  @out s = "Hello"
end

model = @init(MyApp, debounce = 50)
```
"""
macro init(args...)
  init_args = Stipple.expressions_to_args(args)

  called_with_params = length(args) > 0 && args[1] isa Expr && args[1].head == :parameters
  called_without_type = isnothing(findfirst(x -> !isa(x, Expr) || x.head ∉ (:kw, :parameters), init_args))
  
  if called_without_type
    called_with_params ? insert!(init_args, 2, :(Stipple.@type())) : pushfirst!(init_args, :(Stipple.@type()))
  end
  
  quote
    local new_handlers = false
    local initfn =  if isdefined($__module__, :init_from_storage)
                      $__module__.init_from_storage
                    else
                      Stipple.init
                    end
    local handlersfn =  if isdefined($__module__, :__GF_AUTO_HANDLERS__)
                          if length(methods($__module__.__GF_AUTO_HANDLERS__)) == 0
                            @eval(@handlers())
                            new_handlers = true
                          end
                          $__module__.__GF_AUTO_HANDLERS__
                        else
                          identity
                        end
                        
    instance = let model = initfn($(init_args...))
      new_handlers ? Base.invokelatest(handlersfn, model) : handlersfn(model)
    end
    for p in Stipple.Pages._pages
      p.context == $__module__ && (p.model = instance)
    end
    instance
  end |> esc
end

macro handlers()
  handlers = init_handlers(__module__)

  quote
    function __GF_AUTO_HANDLERS__(__model__)
      $(handlers...)

      return __model__
    end
  end |> esc
end

macro handlers(expr)
  delete_handlers!(__module__)
  init_handlers(__module__)

  quote
    $expr

    @handlers
  end |> esc
end

macro app(typename, expr, handlers_fn_name = :handlers)
  # indicate to the @handlers macro that old typefields have to be cleared
  # (avoids model_to_storage)
  newtypename = Symbol(typename, "_!_")
  quote
    Stipple.ReactiveTools.@handlers $newtypename $expr $handlers_fn_name
  end |> esc
end

macro handlers(typename, expr, handlers_fn_name = :handlers)
  newtype = endswith(String(typename), "_!_")
  newtype && (typename = Symbol(String(typename)[1:end-3]))

  expr = wrap(expr, :block)
  i_start = 1
  handlercode = []
  initcode = quote end

  for (i, ex) in enumerate(expr.args)
    if ex isa Expr
      if ex.head == :macrocall && ex.args[1] in Symbol.(["@onbutton", "@onchange"])
        ex_index = .! isa.(ex.args, LineNumberNode)
        if sum(ex_index) < 4
          pos = findall(ex_index)[2]
          insert!(ex.args, pos, typename)
        end
        push!(handlercode, expr.args[i_start:i]...)
      else
        if ex.head == :macrocall && ex.args[1] in Symbol.(["@in", "@out", "@private", "@readonly", "@jsfn", "@mixin"])
          ex_index = isa.(ex.args, Union{Symbol, Expr})
          pos = findall(ex_index)[2]
          sum(ex_index) == 2 && ex.args[1] != Symbol("@mixin") && insert!(ex.args, pos, :_)
          insert!(ex.args, pos, :__storage__)
        end
        push!(initcode.args, expr.args[i_start:i]...)
      end
      i_start = i + 1
    end
  end
  
  # model_to_storage is only needed when we add variables to an existing type.
  no_new_vars = findfirst(x -> x isa Expr, initcode.args) === nothing
  # if we redefine a type newtype is true
  if isdefined(__module__, typename) && no_new_vars && ! newtype
    # model is already defined and no variables are added and we are not redefining a model type
  else
    # we need to define a type ...
    storage = if ! newtype && isdefined(__module__, typename) && ! no_new_vars
      @eval(__module__, Stipple.model_to_storage($typename))
    else
      Stipple.init_storage()
    end
    initcode = quote
      # define a local variable __storage__ with the value of storage
      # that will be used by the macro afterwards
      __storage__ = $storage
      # add more definitions to __storage___
      $(initcode.args...)
    end

    # needs to be executed before evaluation of handler code
    # because the handler code depends on the model fields.
    @eval __module__ begin
      # execution of initcode will fill up the __storage__
      $initcode
      Stipple.@type($typename, values(__storage__))
    end
  end

  handlercode_final = []
  for ex in handlercode
    if ex isa Expr
      push!(handlercode_final, @eval(__module__, $ex))
    else
      push!(handlercode_final, ex)
    end
  end

  quote
    Stipple.ReactiveTools.delete_events($typename)

    function $handlers_fn_name(__model__)
      $(handlercode_final...)

      __model__
    end
    ($typename, $handlers_fn_name)
  end |> esc
end

function wrap(expr, wrapper = nothing)
  if wrapper !== nothing && (! isa(expr, Expr) || expr.head != wrapper)
    Expr(wrapper, expr)
  else
    expr
  end
end

function transform(expr, vars::Vector{Symbol}, test_fn::Function, replace_fn::Function)
  replaced_vars = Symbol[]
  ex = postwalk(expr) do x
      if x isa Expr
          if x.head == :call
            f = x
            while f.args[1] isa Expr && f.args[1].head == :ref
              f = f.args[1]
            end
            if f.args[1] isa Symbol && test_fn(f.args[1])
              union!(push!(replaced_vars, f.args[1]))
              f.args[1] = replace_fn(f.args[1])
            end
            if x.args[1] == :notify && length(x.args) == 2
              if @capture(x.args[2], __model__.fieldname_[])
                x.args[2] = :(__model__.$fieldname)
              elseif x.args[2] isa Symbol
                x.args[2] = :(__model__.$(x.args[2]))
              end
            end
          elseif x.head == :kw && test_fn(x.args[1])
            x.args[1] = replace_fn(x.args[1])
          elseif x.head == :parameters
            for (i, a) in enumerate(x.args)
              if a isa Symbol && test_fn(a)
                new_a = replace_fn(a)
                x.args[i] = new_a in vars ? :($(Expr(:kw, new_a, :(__model__.$new_a[])))) : new_a
              end
            end
          elseif x.head == :ref && length(x.args) == 2 && x.args[2] == :!
            @capture(x.args[1], __model__.fieldname_[]) && (x.args[1] = :(__model__.$fieldname))
          elseif x.head == :macrocall && x.args[1] == Symbol("@push")
            x = :(push!(__model__))
          end
      end
      x
  end
  ex, replaced_vars
end

mask(expr, vars::Vector{Symbol}) = transform(expr, vars, in(vars), x -> Symbol("_mask_$x"))
unmask(expr, vars = Symbol[]) = transform(expr, vars, x -> startswith(string(x), "_mask_"), x -> Symbol(string(x)[7:end]))[1]

function fieldnames_to_fields(expr, vars)
  postwalk(expr) do x
    x isa Symbol && x ∈ vars ? :(__model__.$x) : x
  end
end

function fieldnames_to_fields(expr, vars, replace_vars)
  postwalk(expr) do x
    if x isa Symbol
      x ∈ replace_vars && return :(__model__.$x)
    elseif x isa Expr
      if x.head == Symbol("=")
        x.args[1] = postwalk(x.args[1]) do y
          y ∈ vars ? :(__model__.$y) : y
        end
      end
    end
    x
  end
end

function fieldnames_to_fieldcontent(expr, vars)
  postwalk(expr) do x
    x isa Symbol && x ∈ vars ? :(__model__.$x[]) : x
  end
end

function fieldnames_to_fieldcontent(expr, vars, replace_vars)
  postwalk(expr) do x
    if x isa Symbol
      x ∈ replace_vars && return :(__model__.$x[])
    elseif x isa Expr
      if x.head == Symbol("=")
        x.args[1] = postwalk(x.args[1]) do y
          y ∈ vars ? :(__model__.$y[]) : y
        end
      end
    end
    x
  end
end

function get_known_vars(M::Module)
  init_storage(M)
  reactive_vars = Symbol[]
  non_reactive_vars = Symbol[]
  for (k, v) in REACTIVE_STORAGE[M]
    k in [:channel__, :modes__] && continue
    is_reactive = startswith(string(Stipple.split_expr(v)[2]), r"(Stipple\.)?R(eactive)?($|{)")
    push!(is_reactive ? reactive_vars : non_reactive_vars, k)
  end
  reactive_vars, non_reactive_vars
end

function get_known_vars(::Type{M}) where M<:ReactiveModel
  CM = Stipple.get_concrete_type(M)
  reactive_vars = Symbol[]
  non_reactive_vars = Symbol[]
  for (k, v) in zip(fieldnames(CM), fieldtypes(CM))
    k in [:channel__, :modes__] && continue
    push!(v <: Reactive ? reactive_vars : non_reactive_vars, k)
  end
  reactive_vars, non_reactive_vars
end

"""
```julia
@onchange(var, expr)
```
Declares a reactive update such that when a reactive variable changes `expr` is executed.

**Usage**

This macro watches a list of variables and defines a code block that is executed when the variables change.

```julia
@app begin
    # reactive variables taking their value from the UI
    @in N = 0
    @in M = 0
    @out result = 0
    # reactive code to be executed when N changes
    @onchange N, M begin
        result = 10*N*M
    end
end
```

"""
macro onchange(var, expr)
  quote
    @onchange $__module__ $var $expr
  end |> esc
end

macro onchange(location, vars, expr)
  loc::Union{Module, Type{<:M}} where M<:ReactiveModel = @eval __module__ $location
  vars = wrap(vars, :tuple)
  expr = wrap(expr, :block)

  loc isa Module && init_handlers(loc)
  known_reactive_vars, known_non_reactive_vars = get_known_vars(loc)
  known_vars = vcat(known_reactive_vars, known_non_reactive_vars)
  on_vars = fieldnames_to_fields(vars, known_vars)

  expr, used_vars = mask(expr, known_vars)
  do_vars = Symbol[]

  for a in vars.args
    push!(do_vars, a isa Symbol && ! in(a, used_vars) ? a : :_)
  end

  replace_reactive_vars = setdiff(known_reactive_vars, do_vars)
  replace_non_reactive_vars = setdiff(known_non_reactive_vars, do_vars)

  expr = fieldnames_to_fields(expr, known_non_reactive_vars, replace_non_reactive_vars)
  expr = fieldnames_to_fieldcontent(expr, known_reactive_vars, replace_reactive_vars)
  expr = unmask(expr, vcat(replace_reactive_vars, replace_non_reactive_vars))

  fn = length(vars.args) == 1 ? :on : :onany
  ex = quote
    $fn($(on_vars.args...)) do $(do_vars...)
        $(expr.args...)
    end
  end

  loc isa Module && push!(HANDLERS[__module__], ex)
  output = [ex]
  quote
    function __GF_AUTO_HANDLERS__ end
    Base.delete_method.(methods(__GF_AUTO_HANDLERS__))
    $output[end]
  end |> esc
end

macro onchangeany(var, expr)
  quote
    @warn("The macro `@onchangeany` is deprecated and should be replaced by `@onchange`")
    @onchange $vars $expr
  end |> esc
end

"""
```julia
@onbutton
```
Declares a reactive update that executes `expr` when a button is pressed in the UI.

**Usage**
Define a click event listener with `@click`, and the handler with `@onbutton`.

```julia
@app begin
    @in press = false
    @onbutton press begin
        println("Button presed!")
    end
end

ui() = btn("Press me", @click(:press))

@page("/", ui)
```


"""
macro onbutton(var, expr)
  quote
    @onbutton $__module__ $var $expr
  end |> esc
end

macro onbutton(location, var, expr)
  loc::Union{Module, Type{<:ReactiveModel}} = @eval __module__ $location
  expr = wrap(expr, :block)
  loc isa Module && init_handlers(loc)

  known_reactive_vars, known_non_reactive_vars = get_known_vars(loc)
  known_vars = vcat(known_reactive_vars, known_non_reactive_vars)
  var = fieldnames_to_fields(var, known_vars)

  expr = fieldnames_to_fields(expr, known_non_reactive_vars)
  expr = fieldnames_to_fieldcontent(expr, known_reactive_vars)
  expr = unmask(expr, known_vars)

  ex = :(onbutton($var) do
    $(expr.args...)
  end)

  output = quote end

  if loc isa Module
    push!(HANDLERS[__module__], ex)
    push!(output.args, :(function __GF_AUTO_HANDLERS__ end))
    push!(output.args, :(Base.delete_method.(methods(__GF_AUTO_HANDLERS__))))
  end
  push!(output.args, QuoteNode(ex))

  output |> esc
end

#===#

"""
```julia
@page(url, view)
```
Registers a new page with source in `view` to be rendered at the route `url`.

**Usage**

```julia
@page("/", "view.html")
```
"""
macro page(expressions...)
    # for macros to support semicolon parameter syntax it's required to have no positional arguments in the definition
    # therefore find indexes of positional arguments by hand
    inds = findall(x -> !isa(x, Expr) || x.head ∉ (:parameters, :kw), expressions)
    length(inds) < 2 && throw("Positional arguments 'url' and 'view' required!")
    url, view = expressions[inds[1:2]]
    kwarg_inds = setdiff(1:length(expressions), inds)
    args = Stipple.expressions_to_args(
        expressions[kwarg_inds]; 
        args_to_kwargs = [:layout, :model, :context],
        defaults = Dict(
            :layout => Stipple.ReactiveTools.DEFAULT_LAYOUT(),
            :context => __module__,
            :model => () -> @eval(__module__, @init())
        )
    )
@show args
    :(Stipple.Pages.Page($(args...), $url, view = $view)) |> esc
end

for f in (:methods, :watch, :computed)
  f_str = string(f)
  Core.eval(@__MODULE__, quote
    """
        @$($f_str)(expr)
        @$($f_str)(App, expr)

    Defines js functions for the `$($f_str)` section of the vue element.
          
    `expr` can be
    - `String` containing javascript code
    - `Pair` of function name and function code
    - `Function` returning String of javascript code
    - `Dict` of function names and function code
    - `Vector` of the above
  
    ### Example 1

    ```julia
    @$($f_str) "greet: function(name) {console.log('Hello ' + name)}"
    ```

    ### Example 2

    ```julia
    js_greet() = :greet => "function(name) {console.log('Hello ' + name)}"
    js_bye() = :bye => "function() {console.log('Bye!')}"
    @$($f_str) MyApp [js_greet, js_bye]
    ```
    Checking the result can be done in the following way
    ```
    julia> render(MyApp())[:$($f_str)].s |> println
    {
        "greet":function(name) {console.log('Hello ' + name)},
        "bye":function() {console.log('Bye!')}
    }
    ```
    """
    macro $f(args...)
      vue_options($f_str, args...)
    end
  end)
end

#=== Lifecycle hooks ===#

for (f, field) in (
  (:before_create, :beforeCreate), (:created, :created), (:before_mount, :beforeMount), (:mounted, :mounted),
  (:before_update, :beforeUpdate), (:updated, :updated), (:activated, :activated), (:deactivated, :deactivated),
  (:before_destroy, :beforeDestroy), (:destroyed, :destroyed), (:error_captured, :errorCaptured),)

  f_str = string(f)
  field_str = string(field)
  Core.eval(@__MODULE__, quote
    """
        @$($f_str)(expr)

    Defines js statements for the `$($field_str)` section of the vue element.

    expr can be
      - `String` containing javascript code
      - `Function` returning String of javascript code
      - `Vector` of the above

    ### Example 1

    ```julia
    @$($f_str) \"\"\"
        if (this.cameraon) { startcamera() }
    \"\"\"
    ```

    ### Example 2

    ```julia
    startcamera() = "if (this.cameraon) { startcamera() }"
    stopcamera() = "if (this.cameraon) { stopcamera() }"

    @$($f_str) MyApp [startcamera, stopcamera]
    ```
    Checking the result can be done in the following way
    ```
    julia> render(MyApp())[:$($field_str)]
    JSONText("function(){\n    if (this.cameraon) { startcamera() }\n\n    if (this.cameraon) { stopcamera() }\n}")
    ```
    """
    macro $f(args...)
      vue_options($f_str, args...)
    end
  end)
end

#=== Lifecycle hooks ===#

function vue_options(hook_type, args...)
  if length(args) == 1
    expr = args[1]
    quote
      let M = Stipple.@type
        Stipple.$(Symbol("js_$hook_type"))(::M) = $expr
      end
    end |> esc
  elseif length(args) == 2
    T, expr = args[1], args[2]
    esc(:(Stipple.$(Symbol("js_$hook_type"))(::$T) = $expr))
  else
    error("Invalid number of arguments for vue options")
  end
end

macro event(M, eventname, expr)

  known_reactive_vars, known_non_reactive_vars = get_known_vars(@eval(__module__, $M))
  known_vars = vcat(known_reactive_vars, known_non_reactive_vars)
  expr, used_vars = mask(expr, known_vars)

  expr = fieldnames_to_fields(expr, known_non_reactive_vars)
  expr = fieldnames_to_fieldcontent(expr, known_reactive_vars)
  expr = unmask(expr, known_vars)

  expr = unmask(fieldnames_to_fieldcontent(expr, known_vars), known_vars)
  T = eventname isa QuoteNode ? eventname : QuoteNode(eventname)

  quote
    function Base.notify(__model__::$M, ::Val{$T}, @nospecialize(event))
        $expr
    end
  end |> esc
end

"""
```julia
@event(event, expr)
```
Executes the code in `expr` when a specific `event` is triggered by a UI component.

**Usage**

Define an event trigger such as a click, keypress or file upload for a component using the @on macro. Then, define the handler for the event with @event.


**Examples**

Keypress:


```julia
@app begin
    @event :keypress begin
        println("The Enter key has been pressed")
    end
end

ui() =  textfield(class = "q-my-md", "Input", :input, hint = "Please enter some words", @on("keyup.enter", :keypress))

@page("/", ui)
```

=======
```julia
<q-input hint="Please enter some words" v-on:keyup.enter="function(event) { handle_event(event, 'keypress') }" label="Input" v-model="input" class="q-my-md"></q-input>
```
File upload:

```julia
@app begin
    @event :uploaded begin
        println("Files have been uploaded!")
    end
end

ui() = uploader("Upload files", url = "/upload" , method="POST", @on(:uploaded, :uploaded), autoupload=true)

route("/upload", method=POST) do
    # process uploaded files
end

@page("/", ui)
```

```julia
julia> print(ui())
<q-uploader url="/upload" method="POST" auto-upload v-on:uploaded="function(event) { handle_event(event, 'uploaded') }">Upload files</q-uploader>
```
"""
macro event(event, expr)
  quote
    @event Stipple.@type() $event $expr
  end |> esc
end

macro client_data(expr)
  if expr.head != :block
    expr = quote $expr end
  end

  output = :(Stipple.client_data())
  for e in expr.args
    e isa LineNumberNode && continue
    e.head = :kw
    push!(output.args, e)
  end

  esc(quote
    let M = Stipple.@type
      Stipple.client_data(::M) = $output
    end
  end)
end

macro client_data(M, expr)
  if expr.head != :block
    expr = quote $expr end
  end

  output = :(Stipple.client_data())
  for e in expr.args
    e isa LineNumberNode && continue
    e.head = :kw
    push!(output.args, e)
  end

  :(Stipple.client_data(::$(esc(M))) = $(esc(output)))
end

macro add_client_data(expr)
  if expr.head != :block
    expr = quote $expr end
  end

  output = :(Stipple.client_data())
  for e in expr.args
    e isa LineNumberNode && continue
    e.head = :kw
    push!(output.args, e)
  end

  esc(quote
    let M = Stipple.@type
      cd_old = Stipple.client_data(M())
      cd_new = $output
      Stipple.client_data(::M) = merge(d1, d2)
    end
  end)
end

macro notify(args...)
  for arg in args
    arg isa Expr && arg.head == :(=) && (arg.head = :kw)
  end

  quote
    Base.notify(__model__, $(args...))
  end |> esc
end

end
