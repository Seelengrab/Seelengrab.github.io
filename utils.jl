function hfun_bar(vname)
  val = Meta.parse(vname[1])
  return round(sqrt(val), digits=2)
end

function hfun_m1fill(vname)
  var = vname[1]
  return pagevar("index", var)
end

function lx_baz(com, _)
  # keep this first line
  brace_content = Franklin.content(com.braces[1]) # input string
  # do whatever you want here
  return uppercase(brace_content)
end

function hfun_pagetags()
    tags = locvar("tags"; default=nothing)
    tags == nothing && return ""
    isempty(tags) && return ""

    io = IOBuffer()
    write(io, """<ul class="franklin-content" id="tags">\n""")
    for tag in tags
        write(io, """<li><a href="/tag/$tag/">$tag</a></li>""")
    end
    write(io, "</ul>")

    return String(take!(io))
end

function articles()
    arts = map(d -> joinpath("./articles", d), readdir("./articles"))
    filter!(d -> isfile(joinpath(d, "index.md")), arts)
    arts
end

function hfun_allarticles()
    arts = articles()
    isempty(arts) && return "No articles written"
    sort!(arts)
    io = IOBuffer()
    write(io, "<ul>")
    for art in arts
        article = basename(art)
        write(io, """<li><a href="$article/index.html">$article</a></li>\n""")
    end
    write(io, "</ul>")
    return String(take!(io))
end

function hfun_recentarticles()
    arts = articles()
    isempty(arts) && return "No articles written"
    mtime(f) = stat(f).mtime
    partialsort!(arts, 1:min(5,lastindex(arts)); by=mtime)
    @info arts
    io = IOBuffer()
    write(io, """<ul class="recent">""")
    for art in @view(arts[1:min(5, end)])
        article = basename(art)
        write(io, """<li><a href="$art/index.html">$article</a></li>\n""")
    end
    write(io, "</ul>")
    return String(take!(io))
end
