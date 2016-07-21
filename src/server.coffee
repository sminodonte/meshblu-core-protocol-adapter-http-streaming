_                       = require 'lodash'
colors                  = require 'colors'
morgan                  = require 'morgan'
express                 = require 'express'
bodyParser              = require 'body-parser'
cors                    = require 'cors'
errorHandler            = require 'errorhandler'
meshbluHealthcheck      = require 'express-meshblu-healthcheck'
SendError               = require 'express-send-error'
redis                   = require 'ioredis'
RedisNS                 = require '@octoblu/redis-ns'
debug                   = require('debug')('meshblu-server-http:server')
Router                  = require './router'
RedisPooledJobManager   = require 'meshblu-core-redis-pooled-job-manager'
JobToHttp               = require './helpers/job-to-http'
PackageJSON             = require '../package.json'
MessengerManagerFactory = require 'meshblu-core-manager-messenger/factory'
UuidAliasResolver       = require 'meshblu-uuid-alias-resolver'
compression             = require 'compression'
class Server
  constructor: (options)->
    {
      @disableLogging
      @port
      @aliasServerUri
      @redisUri
      @firehoseRedisUri
      @namespace
      @jobTimeoutSeconds
      @maxConnections
      @jobLogRedisUri
      @jobLogQueue
      @jobLogSampleRate
    } = options
    @panic 'missing @jobLogQueue', 2 unless @jobLogQueue?
    @panic 'missing @jobLogRedisUri', 2 unless @jobLogRedisUri?

  address: =>
    @server.address()

  panic: (message, exitCode, error) =>
    error ?= new Error('generic error')
    console.error colors.red message
    console.error error?.stack
    process.exit exitCode

  run: (callback) =>
    app = express()
    app.use SendError()
    app.use meshbluHealthcheck()
    app.use compression()
    app.use morgan 'dev', immediate: false unless @disableLogging
    app.use errorHandler()
    app.use cors()
    app.use bodyParser.urlencoded limit: '50mb', extended : true
    app.use bodyParser.json limit : '50mb'

    jobManager = new RedisPooledJobManager {
      jobLogIndexPrefix: 'metric:meshblu-core-protocol-adapter-http-streaming'
      jobLogType: 'meshblu-core-protocol-adapter-http-streaming:request'
      @jobTimeoutSeconds
      @jobLogQueue
      @jobLogRedisUri
      @jobLogSampleRate
      @maxConnections
      @redisUri
      @namespace
    }

    jobToHttp = new JobToHttp

    uuidAliasClient = _.bindAll new RedisNS 'uuid-alias', redis.createClient(@redisUri, dropBufferSupport: true)
    uuidAliasResolver = new UuidAliasResolver
      cache: uuidAliasResolver
      aliasServerUri: @aliasServerUri

    messengerManagerFactory = new MessengerManagerFactory {uuidAliasResolver, @namespace, redisUri: @firehoseRedisUri}

    router = new Router {jobManager, jobToHttp, messengerManagerFactory}

    router.route app

    @server = app.listen @port, callback

  stop: (callback) =>
    @server.close callback

module.exports = Server
