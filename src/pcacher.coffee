ms = require 'ms'
promise = require 'bluebird'
_ = require 'lodash'
redis = require 'redis'
co = require 'co'
stringify = require 'json-stable-stringify'
sh = require 'shorthash'
zlib = require 'zlib'

promise.promisifyAll(redis)

toS = (val) ->
  if typeof val is 'string' then ms(val) / 1e3 else val

execValue = (value) ->
  promise.resolve co value

objToKey = (obj, notConvertString) ->
  if notConvertString and _.isString(obj)
    obj
  else
    sh.unique(stringify(obj))

zip = (str, toBase64) ->
  promise.fromNode (cb) ->
    zlib.gzip(str, cb)
  .then (buf) ->
    if toBase64
      buf.toString('base64')
    else
      buf

unzip = (buf) ->
  # backward compatibility
  unless Buffer.isBuffer(buf)
    buf = new Buffer(buf, 'base64')
  promise.fromNode (cb) ->
    zlib.gunzip(buf, cb)
  .then (buf) ->
    buf.toString()


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
    gzip: false
  }

  ###
  Constructor
  @param {Object} config Config
  @option config {String} ns Prefix for saved keys
  @option options {Boolean} [gzip] Gzip data
  @option config {Object} redis Redis config. See see https://github.com/NodeRedis/node_redis#options-is-an-object-with-the-following-possible-properties
  @option config {String|Number} ttl TTL of key. Can be number of seconds or string, like '1h' or '15min'.
  ###
  constructor: (config = {}) ->
    @config = _.extend({}, Cacher.config, config)
    if config.redisClient
      @client = redisClient
    else
      @client = redis.createClient(_.extend(detect_buffers: true, @config.redis))
      @client.select(@config.redis.db) if @config.redis.db
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
  @option options {Boolean} [gzip] Gzip data
  @param {Function|Promise|Any} value Value to save. If type is a function, this function can return a promise
  ###
  memoize: (key, [options]..., value) ->
    if _.isString(options) || _.isNumber(options)
      options = {ttl: options}
    else
      options ||= {}
    options = _.extend({}, @config, options)
    ttl = toS(options.ttl)
    client = @client

    if options.nocache or !ttl
      return execValue(value)

    if options.memory
      key = options.ns + ':' + objToKey(key, true)
      prefix = key[0..2]
      mem = @memoryCache[prefix] ||= {}
      val = mem[key]
      if !val? || val.createTs + ttl * 1e3 < Date.now()
        execValue(value).then (res) ->
          if !res? || Array.isArray(res) && !res.length
            res
          else
            prefix = key[0..2]
            mem[key] =
              val: res
              createTs: Date.now()
            setTimeout(
              -> delete mem[key]
              ttl * 1e3
            )
            mem[key].val
      else
        promise.resolve(val.val)
    else
      key = options.ns + ':' + objToKey(key)
      client.getAsync(key).then (res) =>
        promise.resolve(res).then (res) ->
          if res && !options.reset
            if options.gzip
              unzip(res)
              .catch (e) ->
                console.error(e.stack) if e.stack
                console.error(e)
                console.error('key', key)
                console.error('value', res)
                res
              .then (unzipped) ->
                try
                  JSON.parse(unzipped)
                catch
                  JSON.parse(res)
            else
              JSON.parse(res)
        .catch (e) ->
          console.error(e.stack) if e.stack
          console.error(e)
        .then (res) =>
          if res?
            return res
          execValue(value).then (res) =>
            if !res? || Array.isArray(res) && !res.length
              res
            else
              str = JSON.stringify(res)
              promise.try =>
                if options.gzip
                  zip(str, !@client.detect_buffers)
                else
                  str
              .then (str) =>
                @client.multi()
                  .set(key, str)
                  .expire(key, ttl)
                  .execAsync()
                  .then -> res


module.exports = (config) ->
  new Cacher(config)

# global configuration
module.exports.config = (config) ->
  _.extend(Cacher.config, config)