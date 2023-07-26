local utils = require('focus.modules.utils')
local M = {}

local golden_ratio = 1.618

local golden_ratio_width = function()
    local maxwidth = vim.o.columns
    return math.floor(maxwidth / golden_ratio)
end

local golden_ratio_minwidth = function()
    return math.floor(golden_ratio_width() / (3 * golden_ratio))
end

local golden_ratio_height = function()
    local maxheight = vim.o.lines
    return math.floor(maxheight / golden_ratio)
end

local golden_ratio_minheight = function()
    return math.floor(golden_ratio_height() / (3 * golden_ratio))
end

local easing = {}

function easing.linear(t, b, c, d)
    return c * t / d + b
end

function easing.outQuad(t, b, c, d)
    t = t / d
    return -c * t * (t - 2) + b
end

function easing.inOutQuad(t, b, c, d)
    t = t / d * 2
    if t < 1 then
        return c / 2 * t * t + b
    end
    t = t - 1
    return -c / 2 * (t * (t - 2) - 1) + b
end

function easing.outCubic(t, b, c, d)
    t = t / d - 1
    return c * (t * t * t + 1) + b
end

function easing.inOutCubic(t, b, c, d)
    t = t / d * 2
    if t < 1 then
        return c / 2 * t * t * t + b
    end
    t = t - 2
    return c / 2 * (t * t * t + 2) + b
end

local function animate(
    from,
    to,
    duration,
    easing_function,
    callback,
    done_callback,
    cancellable
)
    local start_time = vim.loop.now()
    local timer = vim.loop.new_timer()
    local stop = false
    local last = from
    timer:start(
        0,
        30,
        vim.schedule_wrap(function()
            local elapsed = vim.loop.now() - start_time
            if stop then
                if timer then
                    timer:stop()
                    if not timer:is_closing() then
                        timer:close()
                    end
                    timer = nil
                end
                return
            end
            local raw = easing_function(elapsed, from, to - from, duration)
            local value = math.min(math.ceil(raw), to)
            if elapsed >= duration or (raw - last) < 1e-1 then
                callback(to)
                if done_callback then
                    done_callback()
                end
                if timer then
                    timer:stop()
                    if not timer:is_closing() then
                        timer:close()
                    end
                    timer = nil
                end
            else
                callback(value)
            end
        end)
    )
    return function()
        stop = true
        if cancellable and done_callback then
            done_callback()
        end
    end
end

local animating = {}

M.view_cache = {}

M.ntimers = 0

function M.is_animating()
    return M.ntimers > 0
end

function M.animate(win, to_width, to_height, config, cancel, on_done)
    if cancel then
        if animating.width then
            animating.width()
        end
        if animating.height then
            animating.height()
        end
    end

    local view = vim.fn.winsaveview()
    local start_width = vim.api.nvim_win_get_width(win)
    local start_height = vim.api.nvim_win_get_height(win)
    local ease_fn
    if type(config.autoresize.animation.easing) == 'string' then
        ease_fn = easing[config.autoresize.animation.easing] or easing.linear
    else
        ease_fn = config.autoresize.animation.easing or easing.linear
    end

    local winheight = vim.o.winheight
    vim.o.winheight = 10
    local done = false
    M.ntimers = M.ntimers + 1
    local width_animation = animate(
        start_width,
        to_width,
        300,
        ease_fn,
        function(value)
            if vim.api.nvim_win_is_valid(win) then
                if
                    M.view_cache[win]
                    and (M.view_cache[win][1] < view.topline - 1)
                    and cancel
                then
                    vim.api.nvim_win_set_cursor(win, M.view_cache[win])
                end
                vim.api.nvim_win_set_width(win, value)
            end
        end,
        function()
            if done then
                M.ntimers = M.ntimers - 1
                if
                    M.view_cache[win]
                    and vim.api.nvim_win_is_valid(win)
                    and cancel
                then
                    vim.api.nvim_win_set_cursor(win, M.view_cache[win])
                end
                vim.o.winheight = winheight
                if on_done then
                    on_done()
                end
            end
            done = true
        end,
        cancel
    )
    animating.width = width_animation
    local height_animation = animate(
        start_height,
        to_height,
        300,
        ease_fn,
        function(value)
            if vim.api.nvim_win_is_valid(win) then
                if
                    M.view_cache[win]
                    and (M.view_cache[win][1] < view.topline - 1)
                    and cancel
                then
                    vim.api.nvim_win_set_cursor(win, M.view_cache[win])
                end
                vim.api.nvim_win_set_height(win, value)
            end
        end,
        function()
            if done then
                M.ntimers = M.ntimers - 1
                if
                    M.view_cache[win]
                    and vim.api.nvim_win_is_valid(win)
                    and cancel
                then
                    vim.api.nvim_win_set_cursor(win, M.view_cache[win])
                end
                vim.o.winheight = winheight
            end
            done = true
        end,
        cancel
    )
    animating.height = height_animation
end

function M.autoresize(config)
    local width
    if config.autoresize.width > 0 then
        width = config.autoresize.width
    else
        width = golden_ratio_width()
        if config.autoresize.minwidth > 0 then
            width = math.max(width, config.autoresize.minwidth)
        elseif width < golden_ratio_minwidth() then
            width = golden_ratio_minwidth()
        end
    end

    local height
    if config.autoresize.height > 0 then
        height = config.autoresize.height
    else
        height = golden_ratio_height()
        if config.autoresize.minheight > 0 then
            height = math.max(height, config.autoresize.minheight)
        elseif height < golden_ratio_minheight() then
            height = golden_ratio_minheight()
        end
    end

    local win = vim.api.nvim_get_current_win()
    local view = vim.fn.winsaveview()
    if config.autoresize.animation.enable then
        M.animate(win, width, height, config, true)
    else
        vim.api.nvim_win_set_width(win, width)
        vim.api.nvim_win_set_height(win, height)
        vim.fn.winrestview(view)
    end
end

function M.equalise(config)
    local wins_pre = {}
    for _, win in ipairs(vim.api.nvim_list_wins()) do
        wins_pre[win] = {
            width = vim.api.nvim_win_get_width(win),
            height = vim.api.nvim_win_get_height(win),
        }
    end

    vim.api.nvim_exec2('wincmd =', { output = false })
    for win, size in pairs(wins_pre) do
        local width = vim.api.nvim_win_get_width(win)
        local height = vim.api.nvim_win_get_height(win)
        if config.autoresize.animation.enable then
            vim.api.nvim_win_set_width(win, size.width)
            vim.api.nvim_win_set_height(win, size.height)
            M.animate(win, width, height, config)
        end
    end
end

function M.maximise(config)
    local width, height = vim.o.columns, vim.o.lines

    local win = vim.api.nvim_get_current_win()
    local view = vim.fn.winsaveview()
    if config.autoresize.animation.enable then
        M.animate(win, width, height, config, true)
    else
        vim.api.nvim_win_set_width(win, width)
        vim.api.nvim_win_set_height(win, height)
        vim.fn.winrestview(view)
    end
end

M.goal = 'autoresize'

function M.split_resizer(config) --> Only resize normal buffers, set qf to 10 always
    if
        utils.is_disabled()
        or vim.api.nvim_win_get_option(0, 'diff')
        or vim.api.nvim_win_get_config(0).relative ~= ''
    then
        return
    end

    if vim.bo.ft == 'qf' then
        vim.api.nvim_win_set_height(0, config.autoresize.height_quickfix)
        return
    end

    M[M.goal](config)
end

return M
