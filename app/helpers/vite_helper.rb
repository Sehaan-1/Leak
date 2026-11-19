# Script and stylesheet tags for the Vite-built SPA in web/.
#
# Development: the browser talks to the Vite dev server (localhost:5173),
# which proxies every non-Vite request to Rails, so the dev-server URLs
# below are same-origin and hot reload works.
#
# Production: tags point at the hashed files Vite wrote to public/spa,
# looked up in its manifest.
module ViteHelper
  ENTRY = "src/main.tsx"
  MANIFEST = Rails.root.join("public/spa/.vite/manifest.json")

  def vite_tags
    if Rails.env.development? && ENV["VITE_DEV_SERVER"] != "0"
      vite_dev_tags
    else
      vite_build_tags
    end
  end

  private
    # main.tsx imports @vitejs/plugin-react/preamble, so no inline script is
    # needed for React Fast Refresh.
    def vite_dev_tags
      safe_join([ tag.script(src: "/@vite/client", type: "module"), tag.script(src: "/#{ENTRY}", type: "module") ], "\n")
    end

    def vite_build_tags
      entry = vite_manifest&.fetch(ENTRY, nil)
      unless entry
        raise "SPA not built: run `npm --prefix web run build`" if Rails.env.production?
        return tag.meta(name: "leak-spa", content: "not built")
      end

      css = Array(entry["css"]).map { |file| tag.link(rel: "stylesheet", href: "/spa/#{file}") }
      safe_join([ *css, tag.script(src: "/spa/#{entry.fetch("file")}", type: "module") ], "\n")
    end

    def vite_manifest
      return @vite_manifest if defined?(@vite_manifest)

      @vite_manifest = MANIFEST.exist? ? JSON.parse(MANIFEST.read) : nil
    end
end
