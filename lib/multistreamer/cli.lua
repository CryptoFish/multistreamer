local posix  = require'posix'
local etlua  = require'etlua'
local getopt = require'multistreamer.getopt'
local config = require'multistreamer.config'
local pgmoon = require'pgmoon'
local whereami = require'whereami'
local lfs = require'lfs'
local lua_bin = whereami()

local getenv = os.getenv
local exit   = os.exit
local len    = string.len
local insert = table.insert

local optarg, optind

local function help(code)
  io.stderr:write('Usage: multistreamer [-c /path/to/config.yaml] <action>\n')
  io.stderr:write('Available actions:\n')
  io.stderr:write('  run   -- run server\n')
  io.stderr:write('  check -- check config file\n')
  return code
end

local function try_load_config(check)
  check = check or false
  local filename,filename_list,err,_
  filename, filename_list = config.find_conf_file(optarg['c'])
  if not filename then
    io.stderr:write('Unable to find config file. Searched paths:\n')
    for _,v in pairs(filename_list) do
      io.stderr:write('  ' .. v .. '\n')
    end
    return 1
  end

  if check then
    io.stderr:write('Testing config file ' .. filename .. '\n')
  end
  _,err = config.loadconfig(filename)
  if err then
    io.stderr:write('Error loading config: ' .. err .. '\n')
    return 1
  end

  local c = config.get()

  if not c['nginx'] then
    io.stderr:write('nginx not specified\n')
    return 1
  end

  if not posix.stdlib.realpath(c['nginx']) then
    io.stderr:write('path to nginx does not exist\n')
    return 1
  end

  local nginx_handle = io.popen(c['nginx'] .. ' -V 2>&1 | grep lua')
  local res = nginx_handle:read('*all')
  nginx_handle:close()

  if len(res) == 0 then
    io.stderr:write("nginx doesn't support lua\n")
    return 1
  end

  if not c['postgres'] or type(c['postgres']) ~= 'table' then
    io.stderr:write('config missing postgres section\n')
    return 1
  end

  local pg = pgmoon.new(c['postgres'])
  _, err = pg:connect()
  if err then
    io.stderr:write('Unable to connect to postgres: ' .. err .. '\n')
    return 1
  end

  if optarg['V'] then
    io.stderr:write(c['_raw'] .. '\n')
  end

  if check then
    io.stderr:write('OK\n')
  end

  return 0
end

local functions = {
  ['run'] = function()
    local res = try_load_config()
    if res ~= 0 then
      return res
    end
    local c = config.get()

    if not posix.stdlib.realpath(c['work_dir']) then
      posix.mkdir(c['work_dir'])
    end
    if not posix.stdlib.realpath(c['work_dir'] .. '/logs') then
      posix.mkdir(c['work_dir'] .. '/logs')
    end
    c.lua_bin = lua_bin

    posix.setenv('CONFIG_FILE',c._filename)
    posix.setenv('LUA_PATH',package.path)
    posix.setenv('LUA_CPATH',package.cpath)

    local nginx_conf = etlua.compile(require'multistreamer.nginx-conf')
    local nof = io.open(c['work_dir'] .. '/nginx.conf', 'wb')
    nof:write(nginx_conf(c))
    nof:close()

    posix.exec(c['nginx'], { '-p', c['work_dir'], '-c', c['work_dir'] .. '/nginx.conf' } )
    return 0
  end,
  ['push'] = function(stream_id, account_id)
    if not stream_id or not account_id then
      return help(1)
    end

    local res = try_load_config()
    if res ~= 0 then
      return res
    end
    local c = config.get()

    local shell = require'multistreamer.shell'
    local Stream = require'multistreamer.models.stream'
    local StreamAccount = require'multistreamer.models.stream_account'
    local stream = Stream:find({ id = stream_id })
    local sa = StreamAccount:find({
      stream_id = stream_id,
      account_id = account_id,
    })
    local account = sa:get_account()

    local ffmpeg_args = {
      '-v',
      'error',
      '-copyts',
      '-vsync',
      '0',
      '-i',
      c.private_rtmp_url ..'/'.. c.rtmp_prefix ..'/'.. stream.uuid,
    }
    local args = {}

    if account.ffmpeg_args and len(account.ffmpeg_args) > 0 then
      args = shell.parse(account.ffmpeg_args)
    end

    if sa.ffmpeg_args and len(sa.ffmpeg_args) > 0 then
      args = shell.parse(sa.ffmpeg_args)
    end
    if #args == 0 then
      args = { '-c:v','copy','-c:a','copy' }
    end

    for _,v in pairs(args) do
      insert(ffmpeg_args,v)
    end

    insert(ffmpeg_args,'-muxdelay')
    insert(ffmpeg_args,'0')
    insert(ffmpeg_args,'-f')
    insert(ffmpeg_args,'flv')
    insert(ffmpeg_args,sa.rtmp_url)

    local _, err = posix.exec(config.ffmpeg,ffmpeg_args)
    return 1
  end,

  ['pull'] = function(stream_id)
    if not stream_id then
      return help(1)
    end

    local res = try_load_config()
    if res ~= 0 then
      return res
    end
    local c = config.get()

    local shell = require'multistreamer.shell'
    local StreamModel = require'multistreamer.models.stream'
    local stream = StreamModel:find({id = stream_id})

    local ffmpeg_args = {
      '-v',
      'error',
    }

    local args = shell.parse(stream.ffmpeg_pull_args)
    for _,v in pairs(args) do
      insert(ffmpeg_args,v)
    end
    insert(ffmpeg_args,'-f')
    insert(ffmpeg_args,'flv')
    insert(ffmpeg_args,c.private_rtmp_url ..'/'..c.rtmp_prefix..'/'..stream.uuid)
    local _, err = posix.exec(c.ffmpeg,ffmpeg_args)
    return 1
  end,
}

local function main(args)
  local _, err
  _, err = pcall(function()
    optarg,optind = getopt.get_opts(args,'l:hVvc:',{})
  end)

  if err then
    io.stderr:write('Error parsing argments: ' .. err .. '\n')
    return help(1)
  end

  if optarg['v'] then
    io.stderr:write('multistreamer: version ' .. version .. '\n')
    return 0
  end

  if optarg['h'] then
    return help(0)
  end

  if not args[optind] or not functions[args[optind]] then
    return help(1)
  end

  local func_args = {}
  for k=optind+1,#args,1 do
    insert(func_args,args[k])
  end

  return functions[args[optind]](unpack(func_args))
end

return main
