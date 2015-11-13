ms = require 'ms'
promise = require 'bluebird'
ijson = require 'i-json'
crypto = require 'crypto'
_ = require 'lodash'
redis = require 'redis'
MAX_JSON_LENGTH = 1024 * 1024

promise.promisifyAll(redis)

toS = (val) ->
  if typeof val is 'string' then ms(val) / 1e3 else val

execValue = (value) ->
  promise.try ->
    value = if _.isFunction(value) then value() else value
    promise.resolve(value)


###
Cacher class
###
class Cacher

  ###
  Default config, can be extended
  ###
  @config: {
    ttl: '1h'
    ns: 'pcacher'
    redis: {}
  }

  ###
  Constructor
  @param {Object} config Config
  @option config {String} ns Prefix for saved keys
  @option config {Object} redis Redis config. See see https://github.com/NodeRedis/node_redis#options-is-an-object-with-the-following-possible-properties
  @option config {String|Number} ttl TTL of key. Can be number of seconds or string, like '1h' or '15min'.
  ###
  constructor: (config = {}) ->
    @config = _.extend({}, config, Cacher.config)
    @client = redis.createClient(@config.redis)
    @client.select(@config.db) if @config.db
    @memoryCache = {}

  ###
  Cache value
  @param {String} key Stored key name
  @param {Object} [options] Options
  @option options {Number|String} [ttl] Number in seconds or duration as string, like '15min' or '2h'
  @option options {Boolean} [reset] Reset stored value, resave it
  @option options {Boolean} [memory] Store data in memory, NOT in Redis
  @option options {Boolean} [ns] Prefix for saved keys
  @option options {Boolean} [nocache] Nocache value
  @param {Function|Promise|Any} value Value to save. If type is a function, this function can return a promise
  ###
  memoize: (key, [options]..., value) ->
    if _.isString(options) || _.isNumber(options)
      options = {ttl: options}
    else
      options ||= {}
    options = _.extend({}, @config, options)
    key = options.ns + ':' + (if _.isString(key) then key else JSON.stringify(key))
    ttl = toS(options.ttl)
    client = @client

    if options.nocache or !ttl
      return execValue(value)

    if options.memory
      key = crypto.createHash('sha1').update(key).digest('hex').toString()
      prefix = key[0..2]
      mem = @memoryCache[prefix] ||= {}
      val = mem[key]
      if !val? || val.createTs + ttl * 1000 < Date.now()
        execValue(value).then (res) ->
          if !res? || Array.isArray(res) && !res.length
            res
          else
            prefix = key[0..2]
            mem[key] = {
              val: res
              createTs: Date.now()
            }
            mem[key].val
      else
        promise.resolve(val.val)
    else
      client.getAsync(key)
      .then (res) =>
        if res && !options.reset
          buf = new Buffer(res)
          # если больше, начинает течь память (именно в новой ноде)
          if buf.length > MAX_JSON_LENGTH
            parser = ijson.createParser()
            parser.update(buf)
            parser.result()
          else
            JSON.parse(res)
        else
          execValue(value).then (res) =>
            if !res? || Array.isArray(res) && !res.length
              res
            else
              @client.multi()
                .set(key, JSON.stringify(res))
                .expire(key, ttl)
                .execAsync()
                .then -> res


module.exports = (config) ->
  new Cacher(config)

# global configuration
module.exports.config = (config) ->
  _.extend(Cacher.config, config)