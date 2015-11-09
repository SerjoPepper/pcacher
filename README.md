# Pcacher
Promisified cache for nodejs. Work on top of Redis. Also support in memory cache.

## Install
```sh
npm install pcacher
```

## Basic usage
```js
var pcacher = require('pcacher');
var cache = pcacher({
  redis: {port: 6379, host: '127.0.0.1'}, // Redis config
  ttl: '2h', // optional. default TTL. See https://github.com/rauchg/ms.js
  ns: 'pcacher' // optional. Prefix for keys in redis. Default is 'pcacher'
});

cache('key', function () {
  return 'value';
}).then(function (val) {
  val === 'value'; // true
});
```

## Value
Value can be a function (can return a promise) or promise or any JSON-serialized object.
```js
cache('key', '15min', function () {
  somePromisifiedQueryToDb(); // should return a promise, this query will be cached for 15 min
}).then(function (val) {
  console.log(val);
});

cache('key', '15min', function () {
  return {a: 1};
}).then(function (val) {
  console.log(val); // {a: 1}
});
```

## Options
Options can be a object, in this case it will be interpreted as list of options. Or it can be String or Number, in this case it will be interpreted as TTL.
There are follow options:
 - `ns`
 - `reset`
 - `memory`
 - `ttl` String or Number of seconds. If a string, use follow patterns `'2h'` or `'15min'`. More detailed [here](https://github.com/rauchg/ms.js).
 - `nocache` Boolean. Use it to off cache

```js
cache('key', {
  ns: 'my_namespace',
  reset: true, // Reset stored value, resave it
  memory: true, // Store data in memory, NOT in Redis
  nocache: true, // Off caching
  ttl: 60 // TTL is 60 seconds, equal '1m'
}, function () {
  return 'value';
}).then(function (val) {
  val === 'value'; // true
});
```
