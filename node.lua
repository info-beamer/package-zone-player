local matrix = require "matrix2d"

gl.setup(NATIVE_WIDTH, NATIVE_HEIGHT)

util.no_globals()

local function log(msg, ...)
    print(string.format(msg, ...))
end

local function round(v)
    return math.floor(v+.5)
end

local function Screen()
    local rotation = 0
    local is_portrait = false
    local gl_transform, video_transform

    local w, h = NATIVE_WIDTH, NATIVE_HEIGHT

    local function set_rotation(new_rotation)
        rotation = new_rotation
        is_portrait = rotation == 90 or rotation == 270

        gl.setup(w, h)
        gl_transform = util.screen_transform(rotation)

        if rotation == 0 then
            video_transform = matrix.ident()
        elseif rotation == 90 then
            video_transform = matrix.trans(w, 0) *
                              matrix.rotate_deg(rotation)
        elseif rotation == 180 then
            video_transform = matrix.trans(w, h) *
                              matrix.rotate_deg(rotation)
        elseif rotation == 270 then
            video_transform = matrix.trans(0, h) *
                              matrix.rotate_deg(rotation)
        else
            return error(string.format("cannot rotate by %d degree", rotation))
        end
    end

    local function place_video(vid, x1, y1, x2, y2)
        local tx1, ty1 = video_transform(x1, y1)
        local tx2, ty2 = video_transform(x2, y2)
        local x1, y1, x2, y2 = round(math.min(tx1, tx2)),
                               round(math.min(ty1, ty2)),
                               round(math.max(tx1, tx2)),
                               round(math.max(ty1, ty2))
        return vid:place(x1, y1, x2, y2, rotation)
    end

    local function draw_image(img, x1, y1, x2, y2)
        return img:draw(x1, y1, x2, y2)
    end

    local function frame_setup()
        return gl_transform()
    end

    local function size()
        if is_portrait then
            return h, w
        else
            return w, h
        end
    end

    set_rotation(0)

    return {
        set_rotation = set_rotation;
        frame_setup = frame_setup;
        draw_image = draw_image;
        place_video = place_video;
        size = size;
    }
end

local screen = Screen()


local function image(file, duration)
    local img, ends
    return {
        prepare = function()
            img = resource.load_image{
                file = file,
            }
        end;
        start = function()
            ends = sys.now() + duration
        end;
        draw = function(pos)
            screen.draw_image(img, pos.x1, pos.y1, pos.x2, pos.y2)
            return sys.now() <= ends
        end;
        dispose = function()
            img:dispose()
        end;
    }
end

local function video(file, duration)
    local vid, ends
    return {
        prepare = function()
            log "video prepare"
            vid = resource.load_video{
                file = file,
                paused = true,
                raw = true,
            }
        end;
        start = function()
            log "video start"
            ends = sys.now() + duration
        end;
        draw = function(pos)
            local state, width, height = vid:state()
            if state == "loaded" then
                screen.place_video(vid, pos.x1, pos.y1, pos.x2, pos.y2)
            elseif state == "paused" then
                vid:layer(1):start()
            end
            return sys.now() <= ends -- and (state == "paused" or state == "loaded")
        end;
        dispose = function()
            log "video dispose"
            vid:dispose()
        end;
    }
end

local function Runner(scheduler)
    local cur, nxt, old
    local pos
    local function set_pos(new_pos)
        pos = new_pos
    end
    local function prepare()
        assert(not nxt)
        nxt = scheduler.get_next()
        nxt.prepare()
    end
    local function down()
        assert(not old)
        old = cur
        cur = nil
    end
    local function switch()
        assert(nxt)
        cur = nxt
        cur.start()
        nxt = nil
    end
    local function dispose()
        old.dispose()
        old = nil
    end
    local function tick()
        if not nxt then
            prepare()
        end
        if old then
            dispose()
        end
        if not cur then
            switch()
        end
        if not cur.draw(pos) then
            down()
        end
    end
    local function stop()
        if nxt then nxt.dispose() end
        if cur then cur.dispose() end
        if old then old.dispose() end
    end

    return {
        set_pos = set_pos;
        tick = tick;
        stop = stop;
    }
end

local function cycled(items, offset)
    if #items == 0 then
        return nil, 0
    end
    offset = offset % #items + 1
    return items[offset], offset
end

local function Scheduler()
    local items = {}
    local offset = 0

    local function set_playlist(playlist)
        local new_items = {}
        for _, item in ipairs(playlist) do
            new_items[#new_items+1] = {
                file = resource.open_file(item.asset.asset_name),
                type = item.asset.type,
                duration = item.duration,
            }
        end
        items = new_items

        -- uncomment if a playlist change should start that playlist from the beginning
        -- offset = 0
    end

    local function get_next()
        local item
        log("next item? offset=%d, items=%d", offset, #items)
        item, offset = cycled(items, offset)
        item = item or { -- fallback?
            file = resource.open_file("empty.png"),
            type = "image",
            duration = 1,
        }
        return ({
            image = image,
            video = video,
        })[item.type](item.file:copy(), item.duration)
    end

    return {
        set_playlist = set_playlist,
        get_next = get_next,
    }
end

local function Area()
    local scheduler = Scheduler()
    local runner = Runner(scheduler)
    return {
        tick = runner.tick,
        set_pos = runner.set_pos,
        set_playlist = scheduler.set_playlist,
        stop = runner.stop,
    }
end

local function Areas()
    local areas = {}

    local function update(new_areas)
        for n = #areas, #new_areas+1, -1 do
            log("removing area %d", n)
            areas[n].stop()
            areas[n] = nil
        end
        for n = #areas+1, #new_areas do
            log("adding area %d", n)
            areas[n] = Area()
        end
        for n, area in ipairs(areas) do
            area.set_pos{
                x1 = new_areas[n].x1,
                y1 = new_areas[n].y1,
                x2 = new_areas[n].x2,
                y2 = new_areas[n].y2,
            }
            area.set_playlist(
                new_areas[n].playlist
            )
        end
    end
    local function tick()
        for n, area in ipairs(areas) do
            area.tick()
        end
    end
    return {
        tick = tick;
        update = update;
    }
end

local areas = Areas()

util.json_watch("config.json", function(config)
    areas.update(config.areas)
    screen.set_rotation(config.rotation)
end)

function node.render()
    screen.frame_setup()
    areas.tick()
end
