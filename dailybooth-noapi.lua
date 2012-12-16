
dofile("table_show.lua")

read_file = function(file)
  if file then
    local f = io.open(file)
    local data = f:read("*all")
    f:close()
    return data
  else
    return ""
  end
end

url_count = 0
picture_count = 0

previous_stats = ""

print_stats = function()
  s = " - Downloaded: "..url_count
  s = s.." URLs. "
  s = s.."Pictures: "..picture_count
  if s ~= previous_stats then
    io.stdout:write("\r"..s)
    io.stdout:flush()
    previous_stats = s
  end
end

wget.callbacks.get_urls = function(file, url, is_css, iri)
  local urls = {}

  -- progress message
  url_count = url_count + 1
  if url_count % 50 == 0 then
    print_stats()
  end

  -- HTML: user page, not private
  local u = string.match(url, "^http://dailybooth%.com/([^/]+)$")
  if u then
    table.insert(urls, { url=("http://dailybooth.com/"..u.."/quilt"), link_expect_html=1 })
    table.insert(urls, { url=("http://dailybooth.com/"..u.."/activity"), link_expect_html=1 })
    table.insert(urls, { url=("http://dailybooth.com/"..u.."/likes"), link_expect_html=1 })
    table.insert(urls, { url=("http://dailybooth.com/"..u.."/followers"), link_expect_html=1 })
    table.insert(urls, { url=("http://dailybooth.com/"..u.."/following"), link_expect_html=1 })

    local html = read_file(file)
    local next_page = string.match(html, "href=\"([^\"]+/page/[^\"]+)\" class=\"right\">Older")
    if next_page then
      table.insert(urls, { url=("http://dailybooth.com"..next_page), link_expect_html=1 })
    end
  end

  -- HTML: user page, pagination
  local u = string.match(url, "^http://dailybooth%.com/([^/]+)/page/%d+$")
  if u then
    local html = read_file(file)
    local next_page = string.match(html, "href=\"([^\"]+/page/[^\"]+)\" class=\"right\">Older")
    if next_page then
      table.insert(urls, { url=("http://dailybooth.com"..next_page), link_expect_html=1 })
    end
  end

  -- HTML: user page, quilt
  local u = string.match(url, "^http://dailybooth%.com/([^/]+)/quilt")
  if u then
    local html = read_file(file)

    -- pictures
    for picture_path in string.gmatch(html, "<a href=\"(/"..u.."/%d+)\"") do
      table.insert(urls, { url=("http://dailybooth.com"..picture_path), link_expect_html=1 })
      picture_count = picture_count + 1
    end

    local next_page = string.match(html, "href=\"([^\"]+/quilt/page/[^\"]+)\" class=\"right\">Older")
    if next_page then
      table.insert(urls, { url=("http://dailybooth.com"..next_page), link_expect_html=1 })
    end
  end

  -- HTML: picture page
  local u = string.match(url, "^http://dailybooth%.com/([^/]+)/%d+$")
  if u then
    local html = read_file(file)

    -- different sizes
    local path_a, path_b = string.match(html, "main_picture_container.-<img src=\"(http://cloudfront%.dailybooth%.com/%d+/pictures/)large(/[a-z_0-9]+%.jpg)\"")
    if path_a and path_b then
      table.insert(urls, { url=(path_a.."tiny"..path_b) })
      table.insert(urls, { url=(path_a.."small"..path_b) })
      table.insert(urls, { url=(path_a.."medium"..path_b) })
      table.insert(urls, { url=(path_a.."large"..path_b) })
      table.insert(urls, { url=(path_a.."original"..path_b) })
    end
  end

  -- HTML: the followers page
  local u = string.match(url, "^http://dailybooth%.com/[^/]+/followers")
  if u then
    local html = read_file(file)
    local next_page = string.match(html, "href=\"([^\"]+/followers/[^\"]+)\" class=\"right\">Older")
    if next_page then
      table.insert(urls, { url=("http://dailybooth.com"..next_page), link_expect_html=1 })
    end
  end

  -- HTML: the following page
  local u = string.match(url, "^http://dailybooth%.com/[^/]+/following")
  if u then
    local html = read_file(file)
    local next_page = string.match(html, "href=\"([^\"]+/following/[^\"]+)\" class=\"right\">Older")
    if next_page then
      table.insert(urls, { url=("http://dailybooth.com"..next_page), link_expect_html=1 })
    end
  end

  -- HTML: the activity page
  local u = string.match(url, "^http://dailybooth%.com/[^/]+/activity")
  if u then
    local html = read_file(file)
    local next_page = string.match(html, "href=\"([^\"]+/activity/[^\"]+)\" class=\"right\">Older")
    if next_page then
      table.insert(urls, { url=("http://dailybooth.com"..next_page), link_expect_html=1 })
    end
  end

  -- HTML: the likes page
  local u = string.match(url, "^http://dailybooth%.com/[^/]+/likes")
  if u then
    local html = read_file(file)
    local next_page = string.match(html, "href=\"([^\"]+/likes/[^\"]+)\" class=\"right\">Older")
    if next_page then
      table.insert(urls, { url=("http://dailybooth.com"..next_page), link_expect_html=1 })
    end
  end

  return urls
end

wget.callbacks.httploop_result = function(url, err, http_stat)
  if http_stat.statcode == 503 and string.match(url.url, "https://api") then
    -- try again
    io.stdout:write("\nRate limited. Waiting for 120 seconds...\n")
    io.stdout:flush()
    os.execute("sleep 120")
    return wget.actions.CONTINUE
  elseif http_stat.statcode == 504 then
    -- gateway timeout, retry
    os.execute("sleep 10")
    return wget.actions.CONTINUE
  else
    return wget.actions.NOTHING
  end
end

