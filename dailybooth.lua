
JSON = (loadfile "JSON.lua")()
dofile("table_show.lua")

load_json_file = function(file)
  if file then
    local f = io.open(file)
    local data = f:read("*all")
    f:close()
    return JSON:decode(data)
  else
    return nil
  end
end

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

username = nil
url_count = 0
picture_count = 0

previous_stats = ""

print_stats = function()
  s = " - Downloaded: "..url_count
  s = s.." URLs. "
  if username then
    s = s.."Username: '"..username.."'. "
  end
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

  -- API: the user data
  local user_id = string.match(url, "^https://api%.dailybooth%.com/v1/users/(%d+)%.json$")
  if user_id then
    local json = load_json_file(file)
    if json and json["username"] then
      username = json["username"]

      -- further API urls
      -- pictures
      picture_count = tonumber(json["picture_count"])
      if picture_count > 2147483647 then
        picture_count = 0
      end
      picture_count = math.min(picture_count, 100000) -- sanity check
      for p=0, math.ceil(picture_count / 100)-1, 1 do
        table.insert(urls, { url=("https://api.dailybooth.com/v1/users/"..user_id.."/pictures.json?limit=100&page="..p) })
      end

      -- followers
      followers_count = tonumber(json["followers_count"])
      if followers_count > 2147483647 then
        followers_count = 0
      end
      followers_count = math.min(followers_count, 500000) -- sanity check
      for p=0, math.ceil(followers_count / 500)-1, 1 do
        table.insert(urls, { url=("https://api.dailybooth.com/v1/users/"..user_id.."/followers.json?limit=500&page="..p) })
      end

      -- following
      following_count = tonumber(json["following_count"])
      if following_count > 2147483647 then
        following_count = 0
      end
      following_count = math.min(following_count, 500000) -- sanity check
      for p=0, math.ceil(following_count / 500)-1, 1 do
        table.insert(urls, { url=("https://api.dailybooth.com/v1/users/"..user_id.."/following.json?limit=500&page="..p) })
      end

      -- favorites (number unknown)
      table.insert(urls, { url=("https://api.dailybooth.com/v1/users/"..user_id.."/favorites.json?limit=100&page=0") })

      -- activity (number unknown)
      table.insert(urls, { url=("https://api.dailybooth.com/v1/users/"..user_id.."/activity.json?limit=100&page=0") })

      -- username-to-id mapping
      table.insert(urls, { url=("https://api.dailybooth.com/v1/users.json?username="..username) })


      -- store user data
      local dailybooth_lua_json = os.getenv("dailybooth_lua_json")
      if dailybooth_lua_json then
        local fs = io.open(dailybooth_lua_json, "w")
        local name = nil
        if json["details"] and json["details"]["name"] then
          name = json["details"]["name"]
        end
        fs:write(JSON:encode({ id=json["user_id"], username=json["username"], name=name, picture_count=json["picture_count"], followers_count=json["followers_count"], following_count=json["following_count"] }))
        fs:close()
      end


      -- avatar images
      if json["avatars"] then
        for k, url in pairs(json["avatars"]) do
          table.insert(urls, { url=url })
        end
      end


      -- user page, rows, pagination
      table.insert(urls, { url=("http://dailybooth.com/"..username), link_expect_html=1 })
      for p=1, math.ceil(picture_count / 10)-1, 1 do
        table.insert(urls, { url=("http://dailybooth.com/"..username.."/page/"..p), link_expect_html=1 })
      end

      -- user page, grid, pagination
      table.insert(urls, { url=("http://dailybooth.com/"..username.."/quilt"), link_expect_html=1 })
      for p=1, math.ceil(picture_count / 50)-1, 1 do
        table.insert(urls, { url=("http://dailybooth.com/"..username.."/quilt/page/"..p), link_expect_html=1 })
      end

      -- followers, pagination
      table.insert(urls, { url=("http://dailybooth.com/"..username.."/followers"), link_expect_html=1 })
      for p=1, math.ceil(followers_count / 20)-1, 1 do
        table.insert(urls, { url=("http://dailybooth.com/"..username.."/followers/"..p), link_expect_html=1 })
      end

      -- following, pagination
      table.insert(urls, { url=("http://dailybooth.com/"..username.."/following"), link_expect_html=1 })
      for p=1, math.ceil(following_count / 20)-1, 1 do
        table.insert(urls, { url=("http://dailybooth.com/"..username.."/following/"..p), link_expect_html=1 })
      end

      -- start pages
      table.insert(urls, { url=("http://dailybooth.com/"..username.."/activity"), link_expect_html=1 })
      table.insert(urls, { url=("http://dailybooth.com/"..username.."/likes"), link_expect_html=1 })

      print_stats()
    end
  end

  -- API: the pictures list
  local user_id = string.match(url, "^https://api%.dailybooth%.com/v1/users/(%d+)%/pictures%.json")
  if user_id then
    local json = load_json_file(file)
    if json then
      for i, pic in ipairs(json) do
        -- comments
        local comment_count = tonumber(pic["comment_count"])
        if comment_count > 2147483647 then
          comment_count = 0
        end
        comment_count = math.min(comment_count, 100000) -- sanity check
        for p=0, math.ceil(comment_count / 500)-1, 1 do
          table.insert(urls, { url=("https://api.dailybooth.com/v1/pictures/"..pic["picture_id"].."/comments.json?limit=500&page="..p) })
        end

        -- picture images
        if pic["urls"] then
          for k, url in pairs(pic["urls"]) do
            table.insert(urls, { url=url })
          end
        end

        -- picture page
        table.insert(urls, { url=("http://dailybooth.com/"..username.."/"..pic["picture_id"]), link_expect_html=1 })

        -- comments json
        table.insert(urls, { url=("http://dailybooth.com/"..username.."/"..pic["picture_id"].."/comments?type=all") })
      end
    end
  end

  -- API: the followers list
  local user_id = string.match(url, "^https://api%.dailybooth%.com/v1/users/(%d+)%/followers%.json")
  if user_id then
    local json = load_json_file(file)
    if json then
      --      print(table.show(json))
    end
  end

  -- API: the following list
  local user_id = string.match(url, "^https://api%.dailybooth%.com/v1/users/(%d+)%/following%.json")
  if user_id then
    local json = load_json_file(file)
    if json then
      --      print(table.show(json))
    end
  end

  -- API: the favorites list
  local user_id, per_page, page = string.match(url, "^https://api%.dailybooth%.com/v1/users/(%d+)%/favorites%.json%?limit=(%d+)%&page=(%d+)$")
  if user_id then
    local json = load_json_file(file)
    if json then
      -- number of favorites is not given, so we continue until we reach an empty page
      -- (note: the number of pictures on a page isn't always equal to per_page)
      if (#json > 0) then
        table.insert(urls, { url=("https://api.dailybooth.com/v1/users/"..user_id.."/favorites.json?limit="..per_page.."&page="..(page + 1)) })
      end
    end
  end

  -- API: the activity list
  local user_id, per_page, page = string.match(url, "^https://api%.dailybooth%.com/v1/users/(%d+)%/activity%.json%?limit=(%d+)%&page=(%d+)$")
  if user_id then
    local json = load_json_file(file)
    if json then
      -- number of activities is not given, so we continue until we reach an empty page
      -- (note: the number of pictures on a page isn't always equal to per_page)
      if (#json > 0) then
        table.insert(urls, { url=("https://api.dailybooth.com/v1/users/"..user_id.."/activity.json?limit="..per_page.."&page="..(page + 1)) })
      end
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
  else
    return wget.actions.NOTHING
  end
end

