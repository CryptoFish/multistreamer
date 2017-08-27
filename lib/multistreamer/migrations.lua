local migrations = require'lapis.db.migrations'
local schema     = require'lapis.db.schema'
local util       = require'lapis.util'
local types = schema.types

local Account = require'multistreamer.models.account'

local schemas = {
  [1477785578] = function()
    schema.create_table('users', {
      { 'id'      , types.serial },
      { 'username', types.varchar },
      { 'created_at', types.time },
      { 'updated_at', types.time },
      'PRIMARY KEY(id)'
    })

    schema.create_table('accounts', {
      { 'id'      , types.serial },
      { 'user_id' , types.foreign_key },
      { 'network' , types.varchar },
      { 'network_user_id', types.varchar },
      { 'name'    , types.varchar },
      { 'created_at', types.time },
      { 'updated_at', types.time },
      'PRIMARY KEY(id)',
      'FOREIGN KEY(user_id) REFERENCES users(id)',
    })

    schema.create_table('shared_accounts', {
      { 'user_id', types.foreign_key },
      { 'account_id', types.foreign_key },
      { 'created_at', types.time },
      { 'updated_at', types.time },
      'PRIMARY KEY(user_id,account_id)',
      'FOREIGN KEY(user_id) REFERENCES users(id)',
      'FOREIGN KEY(account_id) REFERENCES accounts(id)',
    })

    schema.create_table('streams', {
      { 'id', types.serial },
      { 'uuid', types.varchar },
      { 'user_id', types.foreign_key },
      { 'name' , types.varchar },
      { 'slug' , types.varchar },
      { 'created_at', types.time },
      { 'updated_at', types.time },
      'PRIMARY KEY(id)',
      'UNIQUE(uuid)',
      'FOREIGN KEY(user_id) REFERENCES users(id)',
    })

    schema.create_table('streams_accounts', {
      { 'stream_id', types.foreign_key },
      { 'account_id' , types.foreign_key },
      { 'rtmp_url', types.text },
      'FOREIGN KEY(stream_id) REFERENCES streams(id)',
      'FOREIGN KEY(account_id) REFERENCES accounts(id)',
      'PRIMARY KEY(stream_id, account_id)',
    })

    schema.create_table('keystore', {
      { 'stream_id', types.foreign_key },
      { 'account_id' , types.foreign_key },
      { 'key' , types.varchar },
      { 'value', types.text },
      { 'created_at', types.time },
      { 'updated_at', types.time },
      { 'expires_at', types.time({ null: false }) },
      'FOREIGN KEY(stream_id) REFERENCES streams(id)',
      'FOREIGN KEY(account_id) REFERENCES accounts(id)',
    })

  end,

  [1481421931] = function()
    schema.add_column('accounts','slug',types.varchar)
    local accounts = Account:select()
    for _,v in ipairs(accounts) do
      v:update({
        slug = util.slugify(slug)
      })
    end
  end,

  [1485029477] = function()
    schema.add_column('streams_accounts','ffmpeg_args',types.text)
  end,

  [1485036089] = function()
    schema.add_column('accounts','ffmpeg_args',types.text)
  end,

  [1485788609] = function()

  end,
  [1489949143] = function()

  end,
  [1492032677] = function()

  end,
  [1497734864] = function()

  end,
  [1500610370] = function()

  end,
}


migrations.run_migrations(schemas)

-- 1485788609.sql
-- 1489949143.sql
-- 1492032677.sql
-- 1497734864.sql
-- 1500610370.sql



create table if not exists shared_streams (
  user_id integer references users(id),
  stream_id integer references streams(id),
  chat_level integer default 0,
  metadata_level integer default 0,
  created_at timestamp without time zone NOT NULL,
  updated_at timestamp without time zone NOT NULL,
  primary key(user_id,stream_id)
);




