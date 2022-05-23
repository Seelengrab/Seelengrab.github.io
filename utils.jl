using Dates: unix2datetime

function hfun_bar(vname)
  val = Meta.parse(vname[1])
  return round(sqrt(val), digits=2)
end

function hfun_m1fill(vname)
  var = vname[1]
  return pagevar("index", var)
end

function hfun_pagetags()
    tags = locvar("tags"; default=nothing)
    tags == nothing && return ""
    isempty(tags) && return ""

    io = IOBuffer()
    write(io, """<ul class="franklin-content" id="tags">\n""")
    for tag in tags
        write(io, """<li><a href='/tag/$tag/'>$tag</a></li>""")
    end
    write(io, "</ul>")

    return String(take!(io))
end

function articles()
    arts = map(d -> joinpath("./articles", d), readdir("./articles"))
    filter!(arts) do d
        isfile(joinpath(d, "index.md")) &&
        isfile(joinpath(d, ".published"))
    end
    arts
end

function hfun_allarticles()
    arts = articles()
    isempty(arts) && return "No articles written"
    mtime(f) = stat(f).mtime
    sort!(arts; by=mtime, rev=true)
    io = IOBuffer()
    write(io, "<ul>")
    for art in arts
        article = basename(art)
        date = Date(unix2datetime(mtime(joinpath(art, ".published"))))
        write(io, """<li><a href='./$article/'>$date - $article</a></li>\n""")
    end
    write(io, "</ul>")
    return String(take!(io))
end

function hfun_recentarticles()
    arts = articles()
    isempty(arts) && return "No articles written"
    mtime(f) = stat(f).mtime
    partialsort!(arts, 1:min(5,lastindex(arts)); by=mtime, rev=true)
    @info arts
    io = IOBuffer()
    write(io, """<ul class="recent">""")
    for art in @view(arts[1:min(5, end)])
        article = basename(art)
        write(io, """<li><a href='$art/'>$article</a></li>\n""")
    end
    write(io, "</ul>")
    return String(take!(io))
end

function hfun_out(args)
    isempty(args) && return Franklin.html_err("no path given to {{output}} ")
    rpath = args[end]

    cpaths  = Franklin.form_codepaths(rpath)
    outpath = cpaths.out_path

    # does output exist?
    isfile(outpath) || return Franklin.html_err("could not find the relevant output file '$outpath'")
    output = read(outpath, String)
    lang = isone(length(args)) ? "" : first(args)
    return Franklin.html_code(output, lang; class="code-output")
end

function hfun_video(args)
    !isone(length(args)) && return Franklin.html_err("no path given to {{video <path>}}")
    path = only(args)

    snippet = """
              <p style="display: flex; justify-content: center;">
                  <video style="max-width: 80%; width: auto; height: auto" controls preload="metadata">
                      <source src='$path' type="video/webm"/>
                      Your browser does not support the video tag.
                  </video>
              </p>
              """
    return snippet
end
