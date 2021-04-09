"""
# Stipple.Layout

Utilities for rendering the general layout of a Stipple app, such as of a data dashboard web page or supporting themes.
"""
module Layout

import Genie
using Stipple

export layout

"""
    `function layout(output::Union{String,Vector}; partial::Bool = false, title::String = "", class::String = "", style::String = "",
                      head_content::String = "", channel::String = Genie.config.webchannels_default_route) :: String`

Utility for creating a basic web page structure, including doctype as well as <HTML>, <HEAD>, <TITLE>, <META viewport>,
  and <BODY> tags, together with the output content.

If `partial` is `true`, the page layout HTML elements are not returned.

### Examples

```julia
julia> layout([
        span("Hello", @text(:greeting))
        ])
"<!DOCTYPE html>\n<html><head><title></title><meta name=\"viewport\" content=\"width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no, minimal-ui\" /></head><body class style><link href=\"https://fonts.googleapis.com/css?family=Material+Icons\" rel=\"stylesheet\" /><link href=\"https://fonts.googleapis.com/css2?family=Lato:ital,wght@0,400;0,700;0,900;1,400&display=swap\" rel=\"stylesheet\" /><link href=\"/css/stipple/stipplecore.min.css\" rel=\"stylesheet\" /><link href=\"/css/stipple/quasar.min.css\" rel=\"stylesheet\" /><span v-text='greeting'>Hello</span><script src=\"/js/channels.js?v=1.17.1\"></script><script src=\"/js/stipple/underscore-min.js\"></script><script src=\"/js/stipple/vue.js\"></script><script src=\"/js/stipple/quasar.umd.min.js\"></script>\n<script src=\"/js/stipple/apexcharts.min.js\"></script><script src=\"/js/stipple/vue-apexcharts.min.js\"></script><script src=\"/js/stipple/stipplecore.js\" defer></script><script src=\"/js/stipple/vue_filters.js\" defer></script></body></html>"
```

```julia
julia> layout([
        span("Hello", @text(:greeting))
        ], partial = true)
"<link href=\"https://fonts.googleapis.com/css?family=Material+Icons\" rel=\"stylesheet\" /><link href=\"https://fonts.googleapis.com/css2?family=Lato:ital,wght@0,400;0,700;0,900;1,400&display=swap\" rel=\"stylesheet\" /><link href=\"/css/stipple/stipplecore.min.css\" rel=\"stylesheet\" /><link href=\"/css/stipple/quasar.min.css\" rel=\"stylesheet\" /><span v-text='greeting'>Hello</span><script src=\"/js/channels.js?v=1.17.1\"></script><script src=\"/js/stipple/underscore-min.js\"></script><script src=\"/js/stipple/vue.js\"></script><script src=\"/js/stipple/quasar.umd.min.js\"></script>\n<script src=\"/js/stipple/apexcharts.min.js\"></script><script src=\"/js/stipple/vue-apexcharts.min.js\"></script><script src=\"/js/stipple/stipplecore.js\" defer></script><script src=\"/js/stipple/vue_filters.js\" defer></script>"
```
"""
function layout(output::Union{String,Vector}; partial::Bool = false, title::String = "", class::String = "", style::String = "",
                head_content::String = "", channel::String = Genie.config.webchannels_default_route) :: String

  isa(output, Vector) && (output = join(output, '\n'))

  content = string(
    theme(),
    output,
    Stipple.deps(channel)
  )

  partial && return content

  Genie.Renderer.Html.doc(
    Genie.Renderer.Html.html([
      Genie.Renderer.Html.head([
        Genie.Renderer.Html.title(title)
        Genie.Renderer.Html.meta(name="viewport", content="width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no, minimal-ui")
        head_content
      ])
      Genie.Renderer.Html.body(content, class=class, style=style)
    ])
  )
end

include(joinpath("layout", "page.jl"))
include(joinpath("layout", "theme.jl"))

end
