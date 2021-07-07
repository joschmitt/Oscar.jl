using Documenter, Oscar

module BuildDocu
using Oscar

include(normpath(joinpath(Oscar.oscardir, "docs", "make_work.jl")))
end

using .BuildDocu
Main.BuildDocu.doit(true, false)

deploydocs(
   repo   = "github.com/oscar-system/Oscar.jl.git",
#  deps = Deps.pip("pymdown-extensions", "pygments", "mkdocs", "python-markdown-math", "mkdocs-material", "mkdocs-cinder"),
   deps = nothing,
   target = "build",
   push_preview = true,
#  make = () -> run(`mkdocs build`),
   make = nothing
)
