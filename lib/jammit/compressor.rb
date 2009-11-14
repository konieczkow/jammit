module Jammit

  # Uses the YUI Compressor to compress JavaScript and CSS. Also knows how to
  # create a concatenated JST file.
  class Compressor

    MIME_TYPE_MAP = {
      '.png'  => 'image/png',
      '.jpg'  => 'image/jpeg',
      '.jpeg' => 'image/jpeg',
      '.gif'  => 'image/gif',
      '.tif'  => 'image/tiff',
      '.tiff' => 'image/tiff'
    }

    URL_DETECTOR    = /url\(['"]?(\/[^\s)]*embed\/[^\s)]+)['"]?\)/

    JST_NAMER       = /\/(\w+)\.jst\Z/

    MHTML_START     = "/*\r\nContent-Type: multipart/related; boundary=\"JAMMIT_MHTML_SEPARATOR\"\r\n\r\n"
    MHTML_SEPARATOR = "--JAMMIT_MHTML_SEPARATOR\r\n"
    MHTML_END       = "*/\r\n"

    def initialize
      @yui_js  = YUI::JavaScriptCompressor.new(:munge => true)
      @yui_css = YUI::CssCompressor.new
    end

    # Delegates to the YUI compressor.
    def compress_js(paths)
      @yui_js.compress(concatenate(paths))
    end

    # Delegates to the YUI compressor.
    def compress_css(paths, variant=nil, stylesheet_url=nil)
      compressed_css = @yui_css.compress(concatenate(paths))
      case variant
      when nil      then compressed_css
      when :datauri then with_data_uris(compressed_css)
      when :mhtml   then with_mhtml(compressed_css)
      end
    end

    # Compiles a single JST file by writing out a javascript that adds
    # template properties to a "window.JST" object. Adds a JST-compilation
    # function, unless you've specified your own preferred function.
    def compile_jst(paths)
      compiled = paths.map do |path|
        template_name = path.match(JST_NAMER)[1]
        contents      = File.read(path).gsub(/\n/, '').gsub("'", '\\\\\'')
        "window.JST.#{template_name} = #{Jammit.template_function}('#{contents}');"
      end
      (Jammit.template_function == JST_COMPILER ? JST_SCRIPT : '') + compiled.join("\n")
    end


    private

    # TODO: See if we can fix to work with relative URLs, and still YUI in-advance.

    def with_data_uris(css)
      css.gsub(URL_DETECTOR) do |url|
        image_path = "public#{$1}"
        "url(\"data:#{mime_type(image_path)};base64,#{encoded_contents(image_path)}\")"
      end
    end

    def with_mhtml(css)
      paths = {}
      css = css.gsub(URL_DETECTOR) do |url|
        identifier = $1
        paths[identifier] ||= "public#{identifier}"
        "url(\"mhtml:REQUEST_URL!#{identifier}\")"
      end
      mhtml = paths.map do |identifier, path|
        mime, contents = mime_type(path), encoded_contents(path)
        [MHTML_SEPARATOR, "Content-Location: #{identifier}\r\n", "Content-Type: #{mime}\r\n", "Content-Transfer-Encoding: base64\r\n\r\n", contents, "\r\n"]
      end
      [MHTML_START, mhtml, MHTML_END, css].flatten.join('')
    end

    def encoded_contents(image_path)
      Base64.encode64(File.read(image_path)).gsub(/\n/, '')
    end

    def mime_type(image_path)
      MIME_TYPE_MAP[File.extname(image_path)]
    end

    # Concatenate together a list of asset files -- unfortunately we have to
    # read them into memory to use the YUI gem. At least it only happens once,
    # period.
    def concatenate(paths)
      [paths].flatten.map {|p| File.read(p) }.join("\n")
    end

  end

end
