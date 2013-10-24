--[[ This is called as the main coroutine by the host. If this returns the
     computer crashes. It should never ever return "normally", only when an
     error occurred. Shutdown / reboot are signalled via special yields. ]]

local deadline = 0

local function checkDeadline()
  if os.realTime() > deadline then
    error("too long without yielding", 0)
  end
end

local function checkArg(n, have, ...)
  have = type(have)
  local function check(want, ...)
    if not want then
      return false
    else
      return have == want or check(...)
    end
  end
  if not check(...) then
    local msg = string.format("bad argument #%d (%s expected, got %s)", n, table.concat({...}, " or "), have)
    error(msg, 2)
  end
end

--[[ Set up the global environment we make available to userland programs. ]]
local sandbox
sandbox = {
  -- Top level values. The selection of kept methods rougly follows the list
  -- as available on the Lua wiki here: http://lua-users.org/wiki/SandBoxes
  assert = assert,
  error = error,
  load = function(ld, source, mode, env)
    assert((mode or "t") == "t", "unsupported mode")
    return load(ld, source, "t", env or sandbox)
  end,
  pcall = function(...)
    local result = table.pack(pcall(...))
    checkDeadline()
    return table.unpack(result, 1, result.n)
  end,
  xpcall = function(...)
    local result = table.pack(xpcall(...))
    checkDeadline()
    return table.unpack(result, 1, result.n)
  end,

  ipairs = ipairs,
  next = next,
  pairs = pairs,

  rawequal = rawequal,
  rawget = rawget,
  rawlen = rawlen,
  rawset = rawset,

  select = select,
  type = type,
  tonumber = tonumber,
  tostring = tostring,

  getmetatable = getmetatable,
  setmetatable = setmetatable,

  _VERSION = "Lua 5.2",

  checkArg = checkArg,

  bit32 = {
    arshift = bit32.arshift,
    band = bit32.band,
    bnot = bit32.bnot,
    bor = bit32.bor,
    btest = bit32.btest,
    bxor = bit32.bxor,
    extract = bit32.extract,
    replace = bit32.replace,
    lrotate = bit32.lrotate,
    lshift = bit32.lshift,
    rrotate = bit32.rrotate,
    rshift = bit32.rshift
  },

  --[[ Install wrappers for coroutine management that reserves the first value
       returned by yields for internal stuff. Used for sleeping and message
       calls (sendToAddress) that happen synchronized (Server thread).
  --]]
  coroutine = {
    create = coroutine.create,
    running = coroutine.running,
    resume = function(co, ...)
      local args = table.pack(...)
      while true do
        if not debug.gethook(co) then -- don't reset counter
          debug.sethook(co, checkDeadline, "", 10000)
        end
        local result = table.pack(coroutine.resume(co, table.unpack(args, 1, args.n)))
        checkDeadline()
        if result[1] then
          local isSystemYield = coroutine.status(co) ~= "dead" and result[2] ~= nil
          if isSystemYield then
            args = table.pack(coroutine.yield(result[2]))
          else
            return true, table.unpack(result, 3, result.n)
          end
        else -- error: result = (bool, string)
          return table.unpack(result, 1, result.n)
        end
      end
    end,
    status = coroutine.status,
    yield = function(...)
      return coroutine.yield(nil, ...)
    end,
    wrap = function(f) -- for sandbox's coroutine.resume
      local co = sandbox.coroutine.create(f)
      return function(...)
        local result = table.pack(sandbox.coroutine.resume(co, ...))
        if result[1] then
          return table.unpack(result, 2, result.n)
        else
          error(result[2], 0)
        end
      end
    end
  },

  math = {
    abs = math.abs,
    acos = math.acos,
    asin = math.asin,
    atan = math.atan,
    atan2 = math.atan2,
    ceil = math.ceil,
    cos = math.cos,
    cosh = math.cosh,
    deg = math.deg,
    exp = math.exp,
    floor = math.floor,
    fmod = math.fmod,
    frexp = math.frexp,
    huge = math.huge,
    ldexp = math.ldexp,
    log = math.log,
    max = math.max,
    min = math.min,
    modf = math.modf,
    pi = math.pi,
    pow = math.pow,
    rad = math.rad,
    random = math.random,
    randomseed = function(seed)
      checkArg(1, seed, "number")
      math.randomseed(seed)
    end,
    sin = math.sin,
    sinh = math.sinh,
    sqrt = math.sqrt,
    tan = math.tan,
    tanh = math.tanh
  },

  os = {
    clock = os.clock,
    date = os.date,
    difftime = function(t2, t1)
      return t2 - t1
    end,
    time = os.time,
    uptime = os.uptime,
    freeMemory = os.freeMemory,
    totalMemory = os.totalMemory,
    address = os.address,
    romAddress = os.romAddress,
    tmpAddress = os.tmpAddress
  },

  string = {
    byte = string.byte,
    char = string.char,
    dump = string.dump,
    find = string.find,
    format = string.format,
    gmatch = string.gmatch,
    gsub = string.gsub,
    len = string.len,
    lower = string.lower,
    match = string.match,
    rep = string.rep,
    reverse = string.reverse,
    sub = string.sub,
    upper = string.upper,
    uchar = string.uchar,
    ulen = string.ulen,
    ureverse = string.ureverse,
    usub = string.usub,
    trim = function(s) -- from http://lua-users.org/wiki/StringTrim
      local from = s:match("^%s*()")
      return from > #s and "" or s:match(".*%S", from)
    end
  },

  table = {
    concat = table.concat,
    insert = table.insert,
    pack = table.pack,
    remove = table.remove,
    sort = table.sort,
    unpack = table.unpack
  },

  -- TODO evaluate whether this can be used to do evil things (TM)
  debug = {
    traceback = debug.traceback
  }
}
sandbox._G = sandbox

-------------------------------------------------------------------------------

function sandbox.os.shutdown(reboot)
  coroutine.yield(reboot ~= nil and reboot ~= false)
end

function sandbox.os.signal(name, timeout)
  local waitUntil = os.uptime() + (type(timeout) == "number" and timeout or math.huge)
  repeat
    local signal = table.pack(coroutine.yield(waitUntil - os.uptime()))
    if signal.n > 0 and (name == signal[1] or name == nil) then
      return table.unpack(signal, 1, signal.n)
    end
  until os.uptime() >= waitUntil
end

-------------------------------------------------------------------------------

sandbox.driver = {}

function sandbox.driver.componentType(address)
  checkArg(1, address, "string")
  return nodeName(address)
end

do
  local function send(address, name, ...)
    checkArg(1, address, "string")
    checkArg(2, name, "string")
    return sendToAddress(address, name, ...)
  end
  local env = setmetatable({send = send},
                           { __index = sandbox, __newindex = sandbox })
  for name, code in pairs(drivers()) do
    local driver, reason = load(code, "=" .. name, "t", env)
    if not driver then
      print("Failed loading driver '" .. name .. "': " .. reason)
    else
      local result, reason = xpcall(driver, function(msg)
        return debug.traceback(msg, 2)
      end)
      if not result then
        print("Failed initializing driver '" .. name .. "': " ..
              (reason or "unknown error"))
      end
    end
  end
end

-------------------------------------------------------------------------------

local function main(args)
  local function bootstrap()
    local fs = sandbox.driver.filesystem
    fs.mount(os.romAddress(), "/")
    fs.mount(os.tmpAddress(), "/tmp")

    -- Custom dofile implementation since we don't have the baselib yet.
    local function dofile(file)
      local stream, reason = fs.open(file)
      if not stream then
        error(reason)
      end
      if stream then
        local buffer = ""
        repeat
          local data = stream:read(math.huge)
          if data then
            buffer = buffer .. data
          end
        until not data
        stream:close()
        stream = nil
        local program, reason = sandbox.load(buffer, "=" .. file)
        buffer = nil
        if program then
          return program()
        else
          error("error loading lib '" .. file .. "': " .. reason)
        end
      end
    end

    local init = {}
    for api in fs.dir("lib") do
      local path = fs.concat("lib", api)
      if not fs.isDirectory(path) then
        local install = dofile(path)
        if type(install) == "function" then
          table.insert(init, install)
        end
      end
    end
    for _, install in ipairs(init) do
      install()
    end
    init = nil

    return coroutine.create(function(...)
      sandbox.event.fire(...) -- handle the first signal
      while true do
        sandbox.os.execute("/bin/sh")
      end
    end)
  end
  local co = bootstrap()
  while true do
    deadline = os.realTime() + timeout -- timeout global is set by host
    if not debug.gethook(co) then
      debug.sethook(co, checkDeadline, "", 10000)
    end
    local result = table.pack(coroutine.resume(co, table.unpack(args, 1, args.n)))
    if not result[1] then
      error(result[2] or "unknown error", 0)
    elseif coroutine.status(co) == "dead" then
      error("computer stopped unexpectedly", 0)
    else
      args = table.pack(coroutine.yield(result[2])) -- system yielded value
    end
  end
end

-- JNLua converts the coroutine to a string immediately, so we can't get the
-- traceback later. Because of that we have to do the error handling here.
-- Also, yield once to allow initializing up to here to get a memory baseline.
return pcall(main, table.pack(coroutine.yield()))
